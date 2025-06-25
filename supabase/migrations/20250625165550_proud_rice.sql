/*
  # Add Auto-Assignment Timer System

  1. New Tables
    - `auto_assignment_timers` - Timers for auto-assignment of tasks

  2. Security
    - Enable RLS on new table
    - Add appropriate policies for timer management
*/

-- Auto-assignment timers table
CREATE TABLE IF NOT EXISTS auto_assignment_timers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  application_window_minutes integer DEFAULT 60,
  window_start timestamptz DEFAULT now(),
  window_end timestamptz NOT NULL,
  extensions_count integer DEFAULT 0,
  max_extensions integer DEFAULT 5,
  status text DEFAULT 'active' CHECK (status IN ('active', 'completed', 'cancelled')),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(task_id)
);

ALTER TABLE auto_assignment_timers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Clients can view timers for own tasks" ON auto_assignment_timers;
CREATE POLICY "Clients can view timers for own tasks"
  ON auto_assignment_timers FOR SELECT
  TO authenticated
  USING (task_id IN (
    SELECT t.id FROM tasks t
    JOIN projects p ON t.project_id = p.id
    WHERE p.client_id = auth.uid()
  ));

DROP POLICY IF EXISTS "System can manage auto-assignment timers" ON auto_assignment_timers;
CREATE POLICY "System can manage auto-assignment timers"
  ON auto_assignment_timers FOR ALL
  TO authenticated
  USING (true);

-- Add triggers for updated_at
DROP TRIGGER IF EXISTS update_auto_assignment_timers_updated_at ON auto_assignment_timers;
CREATE TRIGGER update_auto_assignment_timers_updated_at
  BEFORE UPDATE ON auto_assignment_timers
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();