-- ==============================================================================
-- Classroom BLE Mesh Attendance System — Development Seed Data
-- ==============================================================================

-- ─── 1. Classrooms & Gateways ────────────────────────────────────────────────
INSERT INTO public.classrooms (id, name, building, gateway_id)
VALUES 
    ('11111111-1111-1111-1111-111111111101', 'Room 405', 'Main Academic Building', 'ESP32_GATEWAY_405'),
    ('11111111-1111-1111-1111-111111111102', 'Lab 201', 'Computer Engineering Wing', 'ESP32_GATEWAY_201')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.gateways (id, gateway_code, name, classroom_id, status, firmware_version)
VALUES 
    ('22222222-2222-2222-2222-222222222201', 'ESP32_GATEWAY_405', 'Room 405 Gateway', '11111111-1111-1111-1111-111111111101', 'ONLINE', 'v0.5.0-phase4'),
    ('22222222-2222-2222-2222-222222222202', 'ESP32_GATEWAY_201', 'Lab 201 Gateway', '11111111-1111-1111-1111-111111111102', 'ONLINE', 'v0.5.0-phase4')
ON CONFLICT (id) DO NOTHING;

-- ─── 2. Classes ──────────────────────────────────────────────────────────────
INSERT INTO public.classes (id, name, branch, semester, academic_year)
VALUES 
    ('33333333-3333-3333-3333-333333333301', 'CMPN-C', 'Computer Engineering', 5, '2026-27'),
    ('33333333-3333-3333-3333-333333333302', 'INFT-A', 'Information Technology', 5, '2026-27')
ON CONFLICT (id) DO NOTHING;

-- ─── 3. Seed Profiles (Demo Teacher and Student placeholders) ────────────────
-- Note: Replace or link auth_user_id when creating user accounts via Supabase Auth
INSERT INTO public.profiles (id, name, email, roll_number, role)
VALUES 
    ('44444444-4444-4444-4444-444444444401', 'Prof. Sharma', 'teacher@college.edu', NULL, 'teacher'),
    ('55555555-5555-5555-5555-555555555501', 'Aryan Darekar', 'student@college.edu', '25102C0040', 'student'),
    ('55555555-5555-5555-5555-555555555502', 'Priya Patel', 'priya@college.edu', '25102C0041', 'student')
ON CONFLICT (id) DO NOTHING;

-- ─── 4. Class Members ────────────────────────────────────────────────────────
INSERT INTO public.class_members (class_id, student_id)
VALUES 
    ('33333333-3333-3333-3333-333333333301', '55555555-5555-5555-5555-555555555501'),
    ('33333333-3333-3333-3333-333333333301', '55555555-5555-5555-5555-555555555502')
ON CONFLICT (class_id, student_id) DO NOTHING;

-- ─── 5. Subjects ─────────────────────────────────────────────────────────────
INSERT INTO public.subjects (id, name, code, class_id, teacher_id)
VALUES 
    ('66666666-6666-6666-6666-666666666601', 'Database Management Systems', 'DBMS', '33333333-3333-3333-3333-333333333301', '44444444-4444-4444-4444-444444444401'),
    ('66666666-6666-6666-6666-666666666602', 'Computer Networks', 'CN', '33333333-3333-3333-3333-333333333301', '44444444-4444-4444-4444-444444444401')
ON CONFLICT (id) DO NOTHING;
