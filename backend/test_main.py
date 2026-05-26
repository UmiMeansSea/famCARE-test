import os
import pytest
from datetime import datetime, timezone
from httpx import AsyncClient, ASGITransport
import main

pytestmark = pytest.mark.asyncio(loop_scope="function")

@pytest.fixture(autouse=True, scope="session")
async def init_pool():
    """
    Initializes the database connection pool once per test session.
    """
    if main.db_pool is None:
        main.db_pool = await main.asyncpg.create_pool(main.DB_URL)
    yield
    await main.db_pool.close()

@pytest.fixture(autouse=True, scope="function")
async def setup_test_db(init_pool):
    """
    Clears the database tables and populates base seed data before each test.
    """
    async with main.db_pool.acquire() as conn:
        # Clear tables
        await conn.execute("TRUNCATE bookings, caregivers, patients, services RESTART IDENTITY CASCADE;")
        
        # Insert services
        await conn.execute(
            """
            INSERT INTO services (name, duration_minutes, price) VALUES
            ('General Health Checkup', 30, 50.00),
            ('Elderly Care & Companion', 60, 90.00),
            ('Physical Therapy Session', 45, 120.00);
            """
        )
        
        # Insert caregivers
        await conn.execute(
            """
            INSERT INTO caregivers (name, email) VALUES
            ('Alice Smith', 'alice.smith@famcare.com'),
            ('Bob Johnson', 'bob.johnson@famcare.com'),
            ('Carol Williams', 'carol.williams@famcare.com');
            """
        )
        
        # Insert patients
        await conn.execute(
            """
            INSERT INTO patients (name, email) VALUES
            ('John Doe', 'john.doe@gmail.com'),
            ('Jane Doe', 'jane.doe@gmail.com');
            """
        )

async def test_get_services():
    transport = ASGITransport(app=main.app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/services")
        assert response.status_code == 200
        data = response.json()
        assert len(data) == 3
        assert data[0]["name"] == "General Health Checkup"
        assert data[0]["duration_minutes"] == 30

async def test_get_slots_available():
    transport = ASGITransport(app=main.app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/slots/available?service_id=1&date=2026-05-26")
        assert response.status_code == 200
        slots = response.json()
        assert len(slots) > 0
        assert slots[0]["start_time"] == "08:00"
        assert slots[0]["end_time"] == "08:30"
        assert slots[0]["caregiver_id"] == 1

async def test_successful_bulk_checkout():
    transport = ASGITransport(app=main.app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        payload = {
            "items": [
                {
                    "patient_id": 1,
                    "service_id": 1,
                    "caregiver_id": 1,
                    "date": "2026-05-26",
                    "start_time": "09:00"
                },
                {
                    "patient_id": 1,
                    "service_id": 2,
                    "caregiver_id": 2,
                    "date": "2026-05-26",
                    "start_time": "10:00"
                }
            ]
        }
        response = await client.post("/cart/checkout", json=payload)
        assert response.status_code == 200
        assert response.json()["message"] == "All bookings scheduled successfully"

async def test_caregiver_conflict_detection():
    transport = ASGITransport(app=main.app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        payload_1 = {
            "items": [
                {
                    "patient_id": 1,
                    "service_id": 1,
                    "caregiver_id": 1,
                    "date": "2026-05-26",
                    "start_time": "09:00"
                }
            ]
        }
        res = await client.post("/cart/checkout", json=payload_1)
        assert res.status_code == 200

        payload_2 = {
            "items": [
                {
                    "patient_id": 2,
                    "service_id": 1,
                    "caregiver_id": 1,
                    "date": "2026-05-26",
                    "start_time": "09:15"
                }
            ]
        }
        res_overlap = await client.post("/cart/checkout", json=payload_2)
        assert res_overlap.status_code == 400
        assert "Conflict" in res_overlap.json()["detail"]

async def test_patient_conflict_detection():
    transport = ASGITransport(app=main.app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        payload_1 = {
            "items": [
                {
                    "patient_id": 1,
                    "service_id": 1,
                    "caregiver_id": 1,
                    "date": "2026-05-26",
                    "start_time": "09:00"
                }
            ]
        }
        res = await client.post("/cart/checkout", json=payload_1)
        assert res.status_code == 200

        payload_2 = {
            "items": [
                {
                    "patient_id": 1,
                    "service_id": 1,
                    "caregiver_id": 2,
                    "date": "2026-05-26",
                    "start_time": "09:15"
                }
            ]
        }
        res_overlap = await client.post("/cart/checkout", json=payload_2)
        assert res_overlap.status_code == 400
        assert "overlapping service" in res_overlap.json()["detail"]

async def test_atomic_checkout_failure_rollback():
    transport = ASGITransport(app=main.app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        p1 = {
            "items": [
                {
                    "patient_id": 1,
                    "service_id": 1,
                    "caregiver_id": 1,
                    "date": "2026-05-26",
                    "start_time": "09:00"
                }
            ]
        }
        res1 = await client.post("/cart/checkout", json=p1)
        assert res1.status_code == 200

        p2 = {
            "items": [
                {
                    "patient_id": 1,
                    "service_id": 1,
                    "caregiver_id": 2,
                    "date": "2026-05-26",
                    "start_time": "14:00"
                },
                {
                    "patient_id": 2,
                    "service_id": 1,
                    "caregiver_id": 1,
                    "date": "2026-05-26",
                    "start_time": "09:15"
                }
            ]
        }
        res = await client.post("/cart/checkout", json=p2)
        assert res.status_code == 400

        p3 = {
            "items": [
                {
                    "patient_id": 1,
                    "service_id": 1,
                    "caregiver_id": 2,
                    "date": "2026-05-26",
                    "start_time": "14:00"
                }
            ]
        }
        res3 = await client.post("/cart/checkout", json=p3)
        assert res3.status_code == 200
