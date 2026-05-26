import os
from datetime import datetime, time, timedelta, timezone
from typing import List
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from psycopg_pool import AsyncConnectionPool
from psycopg.rows import dict_row

# Load .env file manually if exists
if os.path.exists(".env"):
    with open(".env") as f:
        for line in f:
            if line.strip() and not line.startswith("#"):
                parts = line.strip().split("=", 1)
                if len(parts) == 2:
                    os.environ[parts[0].strip()] = parts[1].strip()

# Database Connection Pool
raw_db_url = os.getenv("DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/famcare")
DB_URL = raw_db_url.replace("postgresql+asyncpg://", "postgresql://")
db_pool = AsyncConnectionPool(conninfo=DB_URL, kwargs={"row_factory": dict_row}, open=False)

# Initialize FastAPI App
app = FastAPI(title="FamCare Bulk Scheduler API")

# Enable CORS for Flutter app communication
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
async def startup():
    await db_pool.open()

@app.on_event("shutdown")
async def shutdown():
    await db_pool.close()

# Pydantic Schemas
class ServiceSchema(BaseModel):
    id: int
    name: str
    duration_minutes: int
    price: float

class SlotSchema(BaseModel):
    start_time: str  # "HH:MM"
    end_time: str    # "HH:MM"
    caregiver_id: int
    caregiver_name: str

class CheckoutItem(BaseModel):
    patient_id: int
    service_id: int
    caregiver_id: int
    date: str  # "YYYY-MM-DD"
    start_time: str  # "HH:MM"

class CheckoutRequest(BaseModel):
    items: List[CheckoutItem]

# Endpoints
@app.get("/services", response_model=List[ServiceSchema])
async def get_services():
    async with db_pool.connection() as conn:
        cur = await conn.execute("SELECT id, name, duration_minutes, price FROM services ORDER BY id")
        rows = await cur.fetchall()
        return [
            ServiceSchema(
                id=r["id"],
                name=r["name"],
                duration_minutes=r["duration_minutes"],
                price=float(r["price"])
            ) for r in rows
        ]

@app.get("/slots/available", response_model=List[SlotSchema])
async def get_available_slots(service_id: int, date: str):
    """
    Returns available 15-minute aligned slots for the given service on a specified date.
    Auto-assigns an available caregiver.
    """
    try:
        query_date = datetime.strptime(date, "%Y-%m-%d").date()
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")

    async with db_pool.connection() as conn:
        # Get service duration
        cur = await conn.execute("SELECT duration_minutes FROM services WHERE id = %s", (service_id,))
        service = await cur.fetchone()
        if not service:
            raise HTTPException(status_code=404, detail="Service not found")
        duration = service["duration_minutes"]

        # Get all caregivers
        cur = await conn.execute("SELECT id, name FROM caregivers ORDER BY id")
        caregivers = await cur.fetchall()
        if not caregivers:
            return []

        # Get all bookings on the target day (in timezone UTC)
        day_start = datetime.combine(query_date, time.min).replace(tzinfo=timezone.utc)
        day_end = datetime.combine(query_date, time.max).replace(tzinfo=timezone.utc)

        cur = await conn.execute(
            "SELECT caregiver_id, start_time, end_time FROM bookings WHERE start_time >= %s AND start_time <= %s",
            (day_start, day_end)
        )
        bookings = await cur.fetchall()

        # Standard business hours: 08:00 to 18:00
        start_hour = 8
        end_hour = 18
        current_time = datetime.combine(query_date, time(start_hour, 0)).replace(tzinfo=timezone.utc)
        day_limit = datetime.combine(query_date, time(end_hour, 0)).replace(tzinfo=timezone.utc)

        available_slots = []

        while current_time + timedelta(minutes=duration) <= day_limit:
            slot_start = current_time
            slot_end = current_time + timedelta(minutes=duration)

            assigned_caregiver = None
            for cg in caregivers:
                cg_id = cg["id"]
                has_conflict = False
                for b in bookings:
                    if b["caregiver_id"] == cg_id:
                        # Overlap query checks start_time < existing_end AND end_time > existing_start
                        if slot_start < b["end_time"] and slot_end > b["start_time"]:
                            has_conflict = True
                            break
                if not has_conflict:
                    assigned_caregiver = cg
                    break

            if assigned_caregiver:
                available_slots.append(
                    SlotSchema(
                        start_time=slot_start.strftime("%H:%M"),
                        end_time=slot_end.strftime("%H:%M"),
                        caregiver_id=assigned_caregiver["id"],
                        caregiver_name=assigned_caregiver["name"]
                    )
                )

            current_time += timedelta(minutes=15)

        return available_slots

@app.post("/cart/checkout")
async def checkout(payload: CheckoutRequest):
    """
    Executes booking checkout atomically.
    Uses SELECT ... FOR UPDATE with ordered caregiver IDs to avoid deadlocks.
    Checks conflicts for both caregivers and patients.
    """
    if not payload.items:
        raise HTTPException(status_code=400, detail="Cart is empty")

    async with db_pool.connection() as conn:
        # Start Transaction block
        async with conn.transaction():
            # 1. Lock caregivers to avoid race conditions. Must order IDs to prevent deadlocks.
            caregiver_ids = sorted(list(set(item.caregiver_id for item in payload.items)))
            await conn.execute(
                "SELECT id FROM caregivers WHERE id = ANY(%s) ORDER BY id FOR UPDATE",
                (caregiver_ids,)
            )

            # 2. Iterate and validate each booking slot
            for idx, item in enumerate(payload.items):
                # Retrieve service duration
                cur = await conn.execute(
                    "SELECT name, duration_minutes FROM services WHERE id = %s",
                    (item.service_id,)
                )
                service = await cur.fetchone()
                if not service:
                    raise HTTPException(
                        status_code=400,
                        detail=f"Item {idx}: Service ID {item.service_id} not found."
                    )
                
                duration = service["duration_minutes"]
                service_name = service["name"]

                # Parse start time
                try:
                    start_dt = datetime.strptime(f"{item.date} {item.start_time}", "%Y-%m-%d %H:%M")
                    start_dt = start_dt.replace(tzinfo=timezone.utc)
                except ValueError:
                    raise HTTPException(
                        status_code=400,
                        detail=f"Item {idx}: Invalid date/time format. Use YYYY-MM-DD and HH:MM"
                    )

                end_dt = start_dt + timedelta(minutes=duration)

                # Check caregiver conflict
                cur = await conn.execute(
                    """
                    SELECT b.id, c.name AS caregiver_name, b.start_time, b.end_time 
                    FROM bookings b 
                    JOIN caregivers c ON b.caregiver_id = c.id
                    WHERE b.caregiver_id = %s 
                      AND b.start_time < %s 
                      AND b.end_time > %s
                    """,
                    (item.caregiver_id, end_dt, start_dt)
                )
                cg_conflict = await cur.fetchone()

                if cg_conflict:
                    raise HTTPException(
                        status_code=400,
                        detail=(
                            f"Conflict for {service_name} at {item.start_time}: "
                            f"Caregiver is already booked from "
                            f"{cg_conflict['start_time'].strftime('%H:%M')} to "
                            f"{cg_conflict['end_time'].strftime('%H:%M')}."
                        )
                    )

                # Check patient conflict (Patient cannot have two services overlapping)
                cur = await conn.execute(
                    """
                    SELECT b.id, p.name AS patient_name, b.start_time, b.end_time 
                    FROM bookings b 
                    JOIN patients p ON b.patient_id = p.id
                    WHERE b.patient_id = %s 
                      AND b.start_time < %s 
                      AND b.end_time > %s
                    """,
                    (item.patient_id, end_dt, start_dt)
                )
                patient_conflict = await cur.fetchone()

                if patient_conflict:
                    raise HTTPException(
                        status_code=400,
                        detail=(
                            f"Conflict for {service_name} at {item.start_time}: "
                            f"Patient already has an overlapping service from "
                            f"{patient_conflict['start_time'].strftime('%H:%M')} to "
                            f"{patient_conflict['end_time'].strftime('%H:%M')}."
                        )
                    )

                # Insert booking inside the transaction
                await conn.execute(
                    """
                    INSERT INTO bookings (patient_id, caregiver_id, service_id, start_time, end_time) 
                    VALUES (%s, %s, %s, %s, %s)
                    """,
                    (item.patient_id, item.caregiver_id, item.service_id, start_dt, end_dt)
                )

    return {"message": "All bookings scheduled successfully"}

class BookingHistorySchema(BaseModel):
    id: int
    service_name: str
    caregiver_name: str
    start_time: datetime
    end_time: datetime

@app.get("/patients/{patient_id}/bookings", response_model=List[BookingHistorySchema])
async def get_patient_bookings(patient_id: int):
    async with db_pool.connection() as conn:
        cur = await conn.execute(
            """
            SELECT b.id, s.name AS service_name, c.name AS caregiver_name, b.start_time, b.end_time 
            FROM bookings b
            JOIN services s ON b.service_id = s.id
            JOIN caregivers c ON b.caregiver_id = c.id
            WHERE b.patient_id = %s
            ORDER BY b.start_time DESC
            """,
            (patient_id,)
        )
        rows = await cur.fetchall()
        return [
            BookingHistorySchema(
                id=r["id"],
                service_name=r["service_name"],
                caregiver_name=r["caregiver_name"],
                start_time=r["start_time"],
                end_time=r["end_time"]
            ) for r in rows
        ]
