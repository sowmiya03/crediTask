/*
  # Task Applications and Application Buckets

  1. New Tables
    - `application_buckets`
      - `id` (uuid, primary key)
      - `project_id` (uuid, foreign key to projects)
      - `task_id` (uuid, foreign key to tasks)
      - `client_id` (uuid, foreign key to users)
      - `total_applications` (integer, default 0)
      - `reviewed_applications` (integer, default 0)
      - `approved_applications` (integer, default 0)
      - `rejected_applications` (integer, default 0)
      - `status` (text, default 'open')
      - `created_at` (timestamp)
      - `updated_at` (timestamp)
    - `task_applications`
      - `id` (uuid, primary key)
      - `task_id` (uuid, foreign key to tasks)
      - `worker_id` (uuid, foreign key to users)
      - `applied_at` (timestamp)
      - `bucket_id` (uuid, foreign key to application_buckets)
      - `selected` (boolean, default false)
      - `reviewed` (boolean, default false)
      - `status` (text, default 'pending')

  2. Security
    - Enable RLS on all tables
    - Workers can manage their own applications
    - Clients can view applications for their tasks
*/

-- Create application_buckets table first
CREATE TABLE IF NOT EXISTS application_buckets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  client_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  total_applications integer DEFAULT 0,
  reviewed_applications integer DEFAULT 0,
  approved_applications integer DEFAULT 0,
  rejected_applications integer DEFAULT 0,
  status text DEFAULT 'open' CHECK (status IN ('open', 'reviewing', 'closed')),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(task_id)
);

-- Create task_applications table
CREATE TABLE IF NOT EXISTS task_applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  worker_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  applied_at timestamptz DEFAULT now(),
  bucket_id uuid REFERENCES application_buckets(id) ON DELETE SET NULL,
  selected boolean DEFAULT false,
  reviewed boolean DEFAULT false,
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  UNIQUE(task_id, worker_id)
);

-- Enable RLS
ALTER TABLE task_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE application_buckets ENABLE ROW LEVEL SECURITY;

-- Task applications policies (drop existing ones first to avoid conflicts)
DROP POLICY IF EXISTS "Workers can manage own applications" ON task_applications;
DROP POLICY IF EXISTS "Clients can view applications for their tasks" ON task_applications;

CREATE POLICY "Workers can manage own applications" ON task_applications
  FOR ALL TO authenticated
  USING (worker_id = auth.uid());

CREATE POLICY "Clients can view applications for their tasks" ON task_applications
  FOR SELECT TO authenticated
  USING (task_id IN (
    SELECT t.id FROM tasks t
    JOIN projects p ON t.project_id = p.id
    WHERE p.client_id = auth.uid()
  ));

-- Application buckets policies (drop existing ones first to avoid conflicts)
DROP POLICY IF EXISTS "Clients can manage own application buckets" ON application_buckets;

CREATE POLICY "Clients can manage own application buckets" ON application_buckets
  FOR ALL TO authenticated
  USING (client_id = auth.uid());

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_task_applications_worker_task ON task_applications(worker_id, task_id);
CREATE INDEX IF NOT EXISTS idx_task_applications_bucket_id ON task_applications(bucket_id);
CREATE INDEX IF NOT EXISTS idx_task_applications_status ON task_applications(status);

-- Create trigger for updated_at
DROP TRIGGER IF EXISTS update_application_buckets_updated_at ON application_buckets;

CREATE TRIGGER update_application_buckets_updated_at
  BEFORE UPDATE ON application_buckets
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();