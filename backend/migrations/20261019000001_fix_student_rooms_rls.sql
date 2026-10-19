-- ==============================================================================
-- Migration: 20261019000001_fix_student_rooms_rls.sql
-- Description: Add UPDATE policy on student_rooms to enable upsert operations
-- ==============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' 
          AND tablename = 'student_rooms' 
          AND cmd = 'UPDATE'
    ) THEN
        CREATE POLICY "Allow update student_rooms"
            ON public.student_rooms FOR UPDATE
            TO public
            USING (true)
            WITH CHECK (true);
    END IF;
END $$;
