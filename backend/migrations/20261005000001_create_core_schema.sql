-- ==============================================================================
-- Classroom BLE Mesh Attendance System — Core Database Schema
-- Migration: 20261005000001_create_core_schema.sql
-- ==============================================================================

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─── 1. Profiles ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_user_id UUID UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    roll_number TEXT,
    role TEXT NOT NULL CHECK (role IN ('student', 'teacher', 'admin')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_profiles_auth_user ON public.profiles(auth_user_id);

-- ─── 2. Classes ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.classes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,             -- e.g. 'CMPN-C'
    branch TEXT NOT NULL,           -- e.g. 'Computer Engineering'
    semester INTEGER NOT NULL,      -- e.g. 5
    academic_year TEXT NOT NULL,    -- e.g. '2026-27'
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- ─── 3. Class Members (Student <-> Class Mapping) ───────────────────────────
CREATE TABLE IF NOT EXISTS public.class_members (
    class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    PRIMARY KEY (class_id, student_id)
);

CREATE INDEX IF NOT EXISTS idx_class_members_student ON public.class_members(student_id);

-- ─── 4. Classrooms ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.classrooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,             -- e.g. 'Room 405'
    building TEXT NOT NULL,         -- e.g. 'Main Academic Block'
    gateway_id TEXT,                -- Logical identifier e.g. 'ESP32_GATEWAY_405'
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- ─── 5. Gateways ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.gateways (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gateway_code TEXT UNIQUE NOT NULL, -- e.g. 'ESP32_GATEWAY_405'
    name TEXT NOT NULL,
    classroom_id UUID REFERENCES public.classrooms(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'ONLINE' CHECK (status IN ('ONLINE', 'OFFLINE', 'MAINTENANCE')),
    last_seen TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    firmware_version TEXT DEFAULT 'v0.5.0-phase4',
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- ─── 6. Subjects ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.subjects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,             -- e.g. 'Database Management Systems'
    code TEXT NOT NULL,             -- e.g. 'DBMS'
    class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
    teacher_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_subjects_teacher ON public.subjects(teacher_id);
CREATE INDEX IF NOT EXISTS idx_subjects_class ON public.subjects(class_id);

-- ─── 7. Attendance Sessions ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.attendance_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subject_id UUID NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
    class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
    teacher_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    classroom_id UUID REFERENCES public.classrooms(id) ON DELETE SET NULL,
    gateway_id TEXT,                -- Expected gateway logical code
    session_type TEXT NOT NULL DEFAULT 'LECTURE' CHECK (session_type IN ('LECTURE', 'LAB', 'TUTORIAL')),
    started_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    expires_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'CLOSED', 'EXPIRED')),
    session_nonce TEXT NOT NULL DEFAULT encode(gen_random_bytes(16), 'hex'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_attendance_sessions_class_status ON public.attendance_sessions(class_id, status);
CREATE INDEX IF NOT EXISTS idx_attendance_sessions_teacher ON public.attendance_sessions(teacher_id);

-- ─── 8. Attendance Records ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.attendance_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    session_id UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
    gateway_id TEXT,
    status TEXT NOT NULL DEFAULT 'PRESENT' CHECK (status IN ('PRESENT', 'PENDING', 'REJECTED')),
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    verified_at TIMESTAMPTZ,
    face_verified BOOLEAN NOT NULL DEFAULT false,
    gateway_verified BOOLEAN NOT NULL DEFAULT false,
    packet_id TEXT,
    verification_method TEXT DEFAULT 'DEVELOPMENT_DIRECT',
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_student_session UNIQUE (student_id, session_id)
);

CREATE INDEX IF NOT EXISTS idx_attendance_records_session ON public.attendance_records(session_id);
CREATE INDEX IF NOT EXISTS idx_attendance_records_student ON public.attendance_records(student_id);

-- ─── 9. Attendance Tokens (One-Time Temporary Tokens) ────────────────────────
CREATE TABLE IF NOT EXISTS public.attendance_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    session_id UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_attendance_tokens_lookup ON public.attendance_tokens(token_hash, session_id);
