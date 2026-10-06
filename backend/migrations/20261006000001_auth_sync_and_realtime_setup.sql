-- ==============================================================================
-- Classroom BLE Mesh Attendance System — Auth Sync, Indices & Realtime Setup
-- Migration: 20261006000001_auth_sync_and_realtime_setup.sql
-- ==============================================================================

-- ─── 1. Ensure Unique Email Constraint on Profiles ───────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'uq_profiles_email' AND conrelid = 'public.profiles'::regclass
    ) THEN
        ALTER TABLE public.profiles ADD CONSTRAINT uq_profiles_email UNIQUE (email);
    END IF;
END $$;

-- ─── 2. Realtime Replica Identity ────────────────────────────────────────────
-- Set REPLICA IDENTITY FULL so WAL streams include all columns during UPDATE/DELETE
ALTER TABLE public.attendance_sessions REPLICA IDENTITY FULL;
ALTER TABLE public.attendance_records REPLICA IDENTITY FULL;

-- ─── 3. Realtime Publication Verification ────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        -- Safely ensure tables are added
        BEGIN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.attendance_sessions;
        EXCEPTION WHEN duplicate_object THEN
            NULL;
        END;
        BEGIN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.attendance_records;
        EXCEPTION WHEN duplicate_object THEN
            NULL;
        END;
    END IF;
END $$;

-- ─── 4. Seed Auth Users for Development & Testing ────────────────────────────
-- Automatically provisions teacher and student accounts in auth.users & auth.identities
-- Password for all seed accounts: password123
DO $$
DECLARE
    teacher_uid UUID := 'a0000000-0000-0000-0000-000000000001';
    student1_uid UUID := 'a0000000-0000-0000-0000-000000000002';
    student2_uid UUID := 'a0000000-0000-0000-0000-000000000003';
    pwd_hash TEXT;
BEGIN
    pwd_hash := crypt('password123', gen_salt('bf'));

    -- Teacher: Prof. Sharma
    INSERT INTO auth.users (
        instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        confirmation_token, recovery_token, email_change_token_new, email_change,
        email_change_token_current, phone_change, phone_change_token, reauthentication_token,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) VALUES (
        '00000000-0000-0000-0000-000000000000', teacher_uid, 'authenticated', 'authenticated',
        'teacher@college.edu', pwd_hash, now(),
        '', '', '', '', '', '', '', '',
        '{"provider":"email","providers":["email"]}'::jsonb,
        '{"name":"Prof. Sharma","role":"teacher"}'::jsonb,
        now(), now()
    ) ON CONFLICT (id) DO UPDATE SET 
        encrypted_password = pwd_hash, 
        email_confirmed_at = now(),
        confirmation_token = '',
        recovery_token = '',
        email_change_token_new = '',
        email_change = '',
        email_change_token_current = '',
        reauthentication_token = '';

    INSERT INTO auth.identities (
        id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
    ) VALUES (
        gen_random_uuid(), teacher_uid::text, teacher_uid,
        jsonb_build_object('sub', teacher_uid::text, 'email', 'teacher@college.edu'),
        'email', now(), now(), now()
    ) ON CONFLICT (provider, provider_id) DO NOTHING;

    -- Student 1: Aryan Darekar
    INSERT INTO auth.users (
        instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        confirmation_token, recovery_token, email_change_token_new, email_change,
        email_change_token_current, phone_change, phone_change_token, reauthentication_token,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) VALUES (
        '00000000-0000-0000-0000-000000000000', student1_uid, 'authenticated', 'authenticated',
        'student@college.edu', pwd_hash, now(),
        '', '', '', '', '', '', '', '',
        '{"provider":"email","providers":["email"]}'::jsonb,
        '{"name":"Aryan Darekar","role":"student","roll_number":"25102C0040"}'::jsonb,
        now(), now()
    ) ON CONFLICT (id) DO UPDATE SET 
        encrypted_password = pwd_hash, 
        email_confirmed_at = now(),
        confirmation_token = '',
        recovery_token = '',
        email_change_token_new = '',
        email_change = '',
        email_change_token_current = '',
        reauthentication_token = '';

    INSERT INTO auth.identities (
        id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
    ) VALUES (
        gen_random_uuid(), student1_uid::text, student1_uid,
        jsonb_build_object('sub', student1_uid::text, 'email', 'student@college.edu'),
        'email', now(), now(), now()
    ) ON CONFLICT (provider, provider_id) DO NOTHING;

    -- Student 2: Priya Patel
    INSERT INTO auth.users (
        instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        confirmation_token, recovery_token, email_change_token_new, email_change,
        email_change_token_current, phone_change, phone_change_token, reauthentication_token,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) VALUES (
        '00000000-0000-0000-0000-000000000000', student2_uid, 'authenticated', 'authenticated',
        'priya@college.edu', pwd_hash, now(),
        '', '', '', '', '', '', '', '',
        '{"provider":"email","providers":["email"]}'::jsonb,
        '{"name":"Priya Patel","role":"student","roll_number":"25102C0041"}'::jsonb,
        now(), now()
    ) ON CONFLICT (id) DO UPDATE SET 
        encrypted_password = pwd_hash, 
        email_confirmed_at = now(),
        confirmation_token = '',
        recovery_token = '',
        email_change_token_new = '',
        email_change = '',
        email_change_token_current = '',
        reauthentication_token = '';

    INSERT INTO auth.identities (
        id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
    ) VALUES (
        gen_random_uuid(), student2_uid::text, student2_uid,
        jsonb_build_object('sub', student2_uid::text, 'email', 'priya@college.edu'),
        'email', now(), now(), now()
    ) ON CONFLICT (provider, provider_id) DO NOTHING;

    -- Link profiles to auth_user_id
    UPDATE public.profiles SET auth_user_id = teacher_uid WHERE email = 'teacher@college.edu';
    UPDATE public.profiles SET auth_user_id = student1_uid WHERE email = 'student@college.edu';
    UPDATE public.profiles SET auth_user_id = student2_uid WHERE email = 'priya@college.edu';
END $$;
