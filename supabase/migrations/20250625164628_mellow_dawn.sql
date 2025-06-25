/*
  # Auto Assignment Timers

  1. New Tables
    - `auto_assignment_timers`
      - `id` (uuid, primary key)
      - `task_id` (uuid, foreign key to tasks)
      - `application_window_minutes` (integer, default 60)
      - `window_start` (timestamp, default now)
      - `window_end` (timestamp)
      - `extensions_count` (integer, default 0)
      - `max_extensions` (integer, default 5)
      - `status` (text, default 'active')
      - `created_at` (timestamp)
      - `updated_at` (timestamp)

  2. Security
    - Enable RLS on table
    - Clients can view timers for their tasks
    - System can manage all timers
*/

-- Create auto_assignment_timers table
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

-- Enable RLS
ALTER TABLE auto_assignment_timers ENABLE ROW LEVEL SECURITY;

-- Auto assignment timers policies (drop existing ones first to avoid conflicts)
DROP POLICY IF EXISTS "Clients can view timers for own tasks" ON auto_assignment_timers;
DROP POLICY IF EXISTS "System can manage auto-assignment timers" ON auto_assignment_timers;

CREATE POLICY "Clients can view timers for own tasks" ON auto_assignment_timers
  FOR SELECT TO authenticated
  USING (task_id IN (
    SELECT t.id FROM tasks t
    JOIN projects p ON t.project_id = p.id
    WHERE p.client_id = auth.uid()
  ));

CREATE POLICY "System can manage auto-assignment timers" ON auto_assignment_timers
  FOR ALL TO authenticated
  USING (true);

-- Create trigger for updated_at
DROP TRIGGER IF EXISTS update_auto_assignment_timers_updated_at ON auto_assignment_timers;

CREATE TRIGGER update_auto_assignment_timers_updated_at
  BEFORE UPDATE ON auto_assignment_timers
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();