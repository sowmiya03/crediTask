/*
  # Add Auto-Assignment System

  1. New Tables
    - `auto_assignment_timers` - Timers for auto-assignment windows

  2. Security
    - Enable RLS on timer table
    - Add policies for client access
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

-- Auto assignment timers policies
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
CREATE TRIGGER update_auto_assignment_timers_updated_at
  BEFORE UPDATE ON auto_assignment_timers
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();