-- ==============================================================================
-- Classroom BLE Mesh Attendance System — Row Level Security (RLS) Policies
-- Migration: 20261005000002_create_rls_policies.sql
-- ==============================================================================

-- Enable RLS on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.class_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.classrooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gateways ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_tokens ENABLE ROW LEVEL SECURITY;

-- Helper function to get current user's profile ID
CREATE OR REPLACE FUNCTION public.current_profile_id()
RETURNS UUID AS $$
    SELECT id FROM public.profiles WHERE auth_user_id = auth.uid() LIMIT 1;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Helper function to check if current user is a teacher
CREATE OR REPLACE FUNCTION public.is_teacher()
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE auth_user_id = auth.uid() AND role IN ('teacher', 'admin')
    );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- ─── 1. Profiles Policies ─────────────────────────────────────────────────────
CREATE POLICY "Users can view their own profile"
    ON public.profiles FOR SELECT
    USING (auth_user_id = auth.uid() OR public.is_teacher());

CREATE POLICY "Users can update their own profile"
    ON public.profiles FOR UPDATE
    USING (auth_user_id = auth.uid());

CREATE POLICY "Enable insert for authenticated users during registration"
    ON public.profiles FOR INSERT
    WITH CHECK (auth_user_id = auth.uid());

-- ─── 2. Classes & Members Policies ───────────────────────────────────────────
CREATE POLICY "Authenticated users can view classes"
    ON public.classes FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Students and teachers can view class memberships"
    ON public.class_members FOR SELECT
    TO authenticated
    USING (true);

-- ─── 3. Classrooms & Gateways ────────────────────────────────────────────────
CREATE POLICY "Authenticated users can view classrooms"
    ON public.classrooms FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Authenticated users can view gateways"
    ON public.gateways FOR SELECT
    TO authenticated
    USING (true);

-- ─── 4. Subjects Policies ─────────────────────────────────────────────────────
CREATE POLICY "Authenticated users can view subjects"
    ON public.subjects FOR SELECT
    TO authenticated
    USING (true);

-- ─── 5. Attendance Sessions Policies ──────────────────────────────────────────
-- Teachers can manage sessions for their subjects
CREATE POLICY "Teachers can view all sessions"
    ON public.attendance_sessions FOR SELECT
    TO authenticated
    USING (
        teacher_id = public.current_profile_id() 
        OR EXISTS (
            -- Student enrolled in the class of this session
            SELECT 1 FROM public.class_members cm
            WHERE cm.class_id = attendance_sessions.class_id
              AND cm.student_id = public.current_profile_id()
        )
    );

CREATE POLICY "Teachers can insert sessions for their classes"
    ON public.attendance_sessions FOR INSERT
    TO authenticated
    WITH CHECK (
        public.is_teacher() 
        AND teacher_id = public.current_profile_id()
    );

CREATE POLICY "Teachers can update their own sessions"
    ON public.attendance_sessions FOR UPDATE
    TO authenticated
    USING (
        teacher_id = public.current_profile_id()
    );

-- ─── 6. Attendance Records Policies ───────────────────────────────────────────
-- Teachers view all records for their sessions; students view their own
CREATE POLICY "Users can view attendance records"
    ON public.attendance_records FOR SELECT
    TO authenticated
    USING (
        student_id = public.current_profile_id()
        OR EXISTS (
            SELECT 1 FROM public.attendance_sessions s
            WHERE s.id = attendance_records.session_id
              AND s.teacher_id = public.current_profile_id()
        )
    );

-- Students can insert their own attendance for ACTIVE sessions where they are class members
CREATE POLICY "Students can mark attendance for active sessions"
    ON public.attendance_records FOR INSERT
    TO authenticated
    WITH CHECK (
        student_id = public.current_profile_id()
        AND EXISTS (
            SELECT 1 FROM public.attendance_sessions s
            JOIN public.class_members cm ON cm.class_id = s.class_id
            WHERE s.id = attendance_records.session_id
              AND s.status = 'ACTIVE'
              AND s.expires_at > timezone('utc'::text, now())
              AND cm.student_id = public.current_profile_id()
        )
    );

-- ─── 7. Enable Realtime Replication ──────────────────────────────────────────
-- Add tables to supabase_realtime publication
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.attendance_sessions;
        ALTER PUBLICATION supabase_realtime ADD TABLE public.attendance_records;
    END IF;
END $$;
