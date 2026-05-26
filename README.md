# FamCare — Multi-Service Bulk Scheduler

FamCare is a multi-service bulk scheduler for a home healthcare platform. It allows patients to schedule multiple healthcare services (e.g., general health checkups, elderly care, physical therapy sessions) across multiple days in a single, atomic checkout. Caregivers are auto-assigned, and overlapping bookings for both caregivers and patients are strictly prevented at the database level.

---

## 1. Setup & Installation

The project is split into a **FastAPI backend** (with a containerized PostgreSQL database) and a **Flutter/Riverpod frontend**.

### Prerequisites
* Docker & Docker Compose
* Python 3.10+
* Flutter SDK (3.0.0+)

### Step 1: Start the Database (Docker)
The database is fully containerized. Run the following command from the project root to pull and launch the PostgreSQL instance:
```bash
docker compose up -d
```

### Step 2: Set Up & Run the Backend
1. Navigate to the backend directory:
   ```bash
   cd backend
   ```
2. Install the Python dependencies:
   ```bash
   pip install -r requirements.txt
   ```
3. Initialize the database schema and seed data:
   * **PowerShell**:
     ```powershell
     Get-Content schema.sql | docker exec -i famcare-postgres psql -U postgres -d famcare
     ```
   * **Bash/UNIX**:
     ```bash
     docker exec -i famcare-postgres psql -U postgres -d famcare < schema.sql
     ```
4. Start the FastAPI server:
   ```bash
   uvicorn main:app --reload
   ```
   *The server runs locally at `http://localhost:8000`.*

### Step 3: Run the Test Suite
You can execute the automated test suite with the following commands inside the `backend` folder:
```bash
pytest test_main.py -v
```

### Step 4: Set Up & Run the Frontend
1. Navigate to the frontend directory:
   ```bash
   cd frontend
   ```
2. Fetch Flutter packages:
   ```bash
   flutter pub get
   ```
3. Run the app (for target web/Chrome):
   ```bash
   flutter run -d chrome
   ```

---

## 2. Design Decision: Atomic Checkout

A primary requirement of the bulk scheduler is that the checkout must be **atomic**—meaning either all scheduled slots are successfully booked, or none are. 

### Why Database Transactions & Row-Level Locking?
To guarantee atomicity and strict consistency, we utilized a standard PostgreSQL database transaction block (`async with conn.transaction()`) combined with explicit row-level locking (`SELECT ... FOR UPDATE`):

```sql
SELECT id FROM caregivers WHERE id = ANY(%s) ORDER BY id FOR UPDATE;
```

#### Rationale over Optimistic Locking:
* **Strict Consistency**: In a healthcare environment, double-bookings are unacceptable. Optimistic locking checks versions during commit, which can result in transaction rollbacks after the user has completed their checkout details. Pessimistic row-level locking ensures that a caregiver slot is locked immediately upon transaction processing.
* **Safer Conflict Resolution**: Enforcing the lock directly in the database is much safer than managing concurrent state and version mismatches in the application memory.

#### Deadlock Prevention:
To prevent database deadlocks, the caregiver IDs are explicitly sorted in ascending order before the locks are acquired. This ensures that concurrent checkout requests always request row locks in the exact same sequence.

---

## 3. Conflict Correctness

The overlap check evaluates conflicts using the **full service duration** rather than just the start time.

### Logic & Overlap Formula
1. The backend fetches the service duration from the `services` table.
2. It calculates the proposed booking's end time in UTC (`end_dt = start_dt + duration`).
3. It performs a collision check against existing bookings for **both** the caregiver and the patient using the following overlapping window formula:
   $$\text{start\_time} < \text{existing\_end\_time} \quad \text{AND} \quad \text{end\_time} > \text{existing\_start\_time}$$

### Overlap Query
The conflict queries evaluate overlapping windows using:
```sql
SELECT b.id, c.name AS caregiver_name, b.start_time, b.end_time 
FROM bookings b 
JOIN caregivers c ON b.caregiver_id = c.id
WHERE b.caregiver_id = %s 
  AND b.start_time < %s 
  AND b.end_time > %s;
```

---

## 4. System Limits (What breaks first under load?)

While our row-level locking (`SELECT ... FOR UPDATE`) guarantees absolute data integrity, it introduces a scalability tradeoff:

* **Lock Contention**: The row lock is synchronous. If hundreds of concurrent requests attempt to book slots with the exact same caregiver at the exact same millisecond, those transactions will queue and wait.
* **Connection Pool Exhaustion**: Because transactions are held open while waiting for locks to release, database connections stay occupied longer. Under high concurrent load, this can deplete the connection pool, leading to transaction timeouts or database connection failures.

---

## 5. Future Improvements (Tradeoffs & Next Steps)

1. **WebSocket Integration**: 
   The platform currently relies on HTTP polling to fetch available slots. Implementing WebSockets would allow the backend to broadcast newly booked slots in real-time. If User A successfully books a slot, it would instantly disappear from User B's screen before User B attempts to click "Checkout". This improves the UX and dramatically reduces database lock contention.
2. **Booking Statuses for Payments**:
   To scale the platform for commercial use, a status column (e.g., `Pending`, `Confirmed`, `Cancelled`) should be added to the `bookings` table. This allows the system to hold a slot as `Pending` while processing external payment gateways, turning it to `Confirmed` only upon payment verification.
