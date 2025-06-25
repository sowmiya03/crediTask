/*
  # Add Task Applications and Application Buckets

  1. New Tables
    - `task_applications` - Worker applications to tasks
    - `application_buckets` - Buckets to organize applications

  2. Security
    - Enable RLS on all new tables
    - Add appropriate policies for applications management
*/

-- Task applications table
CREATE TABLE IF NOT EXISTS task_applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  worker_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  applied_at timestamptz DEFAULT now(),
  bucket_id uuid,
  selected boolean DEFAULT false,
  reviewed boolean DEFAULT false,
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  UNIQUE(task_id, worker_id)
);

ALTER TABLE task_applications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Workers can manage own applications" ON task_applications;
CREATE POLICY "Workers can manage own applications"
  ON task_applications FOR ALL
  TO authenticated
  USING (worker_id = auth.uid());

DROP POLICY IF EXISTS "Clients can view applications for their tasks" ON task_applications;
CREATE POLICY "Clients can view applications for their tasks"
  ON task_applications FOR SELECT
  TO authenticated
  USING (task_id IN (
    SELECT t.id FROM tasks t
    JOIN projects p ON t.project_id = p.id
    WHERE p.client_id = auth.uid()
  ));

-- Application buckets table
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

ALTER TABLE application_buckets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Clients can manage own application buckets" ON application_buckets;
CREATE POLICY "Clients can manage own application buckets"
  ON application_buckets FOR ALL
  TO authenticated
  USING (client_id = auth.uid());

-- Add foreign key for bucket_id in task_applications
ALTER TABLE task_applications 
ADD CONSTRAINT task_applications_bucket_id_fkey 
FOREIGN KEY (bucket_id) REFERENCES application_buckets(id) ON DELETE SET NULL;

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_task_applications_worker_task ON task_applications(worker_id, task_id);
CREATE INDEX IF NOT EXISTS idx_task_applications_bucket_id ON task_applications(bucket_id);
CREATE INDEX IF NOT EXISTS idx_task_applications_status ON task_applications(status);

-- Add triggers for updated_at
DROP TRIGGER IF EXISTS update_application_buckets_updated_at ON application_buckets;
CREATE TRIGGER update_application_buckets_updated_at
  BEFORE UPDATE ON application_buckets
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();