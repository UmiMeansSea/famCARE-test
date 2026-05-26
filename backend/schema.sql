-- FamCare PostgreSQL Database Schema

-- Drop tables if they exist
DROP TABLE IF EXISTS bookings CASCADE;
DROP TABLE IF EXISTS caregivers CASCADE;
DROP TABLE IF EXISTS patients CASCADE;
DROP TABLE IF EXISTS services CASCADE;

-- Services Table
CREATE TABLE services (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    duration_minutes INTEGER NOT NULL,
    price NUMERIC(10, 2) NOT NULL
);

-- Patients Table
CREATE TABLE patients (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL
);

-- Caregivers Table
CREATE TABLE caregivers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL
);

-- Bookings Table (TIMESTAMPTZ start and end times)
CREATE TABLE bookings (
    id SERIAL PRIMARY KEY,
    patient_id INTEGER REFERENCES patients(id) ON DELETE CASCADE,
    caregiver_id INTEGER REFERENCES caregivers(id) ON DELETE CASCADE,
    service_id INTEGER REFERENCES services(id) ON DELETE CASCADE,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL
);

-- Insert Seed Data
INSERT INTO services (name, duration_minutes, price) VALUES
('General Health Checkup', 30, 50.00),
('Elderly Care & Companion', 60, 90.00),
('Physical Therapy Session', 45, 120.00);

INSERT INTO caregivers (name, email) VALUES
('Alice Smith', 'alice.smith@famcare.com'),
('Bob Johnson', 'bob.johnson@famcare.com'),
('Carol Williams', 'carol.williams@famcare.com');

INSERT INTO patients (name, email) VALUES
('John Doe', 'john.doe@gmail.com'),
('Jane Doe', 'jane.doe@gmail.com');
