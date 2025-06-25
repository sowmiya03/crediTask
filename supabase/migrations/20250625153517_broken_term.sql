/*
  # Fix Task Applications System

  1. Tables Updated
    - `task_applications` - Add missing columns (bucket_id, selected, reviewed, status)
    - `proposals` - Create table for application proposals
    - `application_buckets` - Create table for managing application collections

  2. Security
    - Enable RLS on all new tables
    - Add policies for secure access control
    - Create notification function for client alerts

  3. Performance
    - Add indexes for frequently queried columns
    - Add constraints for data integrity
*/

-- Ensure task_applications table has all required columns
DO $$
BEGIN
  -- Add bucket_id column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'task_applications' AND column_name = 'bucket_id'
  ) THEN
    ALTER TABLE task_applications ADD COLUMN bucket_id uuid;
  END IF;

  -- Add selected column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'task_applications' AND column_name = 'selected'
  ) THEN
    ALTER TABLE task_applications ADD COLUMN selected boolean DEFAULT false;
  END IF;

  -- Add reviewed column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'task_applications' AND column_name = 'reviewed'
  ) THEN
    ALTER TABLE task_applications ADD COLUMN reviewed boolean DEFAULT false;
  END IF;

  -- Add status column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'task_applications' AND column_name = 'status'
  ) THEN
    ALTER TABLE task_applications ADD COLUMN status text DEFAULT 'pending';
  END IF;
END $$;

-- Ensure application_buckets table exists first (needed for foreign key)
CREATE TABLE IF NOT EXISTS application_buckets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  client_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  total_applications integer DEFAULT 0,
  reviewed_applications integer DEFAULT 0,
  status text DEFAULT 'open' NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  approved_applications integer DEFAULT 0,
  rejected_applications integer DEFAULT 0
);

-- Add foreign key constraint for bucket_id after application_buckets exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'task_applications_bucket_id_fkey'
  ) THEN
    ALTER TABLE task_applications 
    ADD CONSTRAINT task_applications_bucket_id_fkey 
    FOREIGN KEY (bucket_id) REFERENCES application_buckets(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Add status constraint if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'task_applications_status_check'
  ) THEN
    ALTER TABLE task_applications ADD CONSTRAINT task_applications_status_check 
    CHECK (status IN ('pending', 'approved', 'rejected'));
  END IF;
END $$;

-- Add unique constraint for application_buckets task_id
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'application_buckets_task_id_key'
  ) THEN
    ALTER TABLE application_buckets ADD CONSTRAINT application_buckets_task_id_key UNIQUE (task_id);
  END IF;
END $$;

-- Add status constraint for application_buckets
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'application_buckets_status_check'
  ) THEN
    ALTER TABLE application_buckets ADD CONSTRAINT application_buckets_status_check 
    CHECK (status IN ('open', 'reviewing', 'closed'));
  END IF;
END $$;

-- Ensure proposals table exists with proper structure
CREATE TABLE IF NOT EXISTS proposals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  worker_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  cover_letter text NOT NULL,
  proposed_rate numeric(10,2),
  estimated_hours integer,
  status text DEFAULT 'pending' NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Add unique constraint for proposals
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'proposals_task_id_worker_id_key'
  ) THEN
    ALTER TABLE proposals ADD CONSTRAINT proposals_task_id_worker_id_key UNIQUE (task_id, worker_id);
  END IF;
END $$;

-- Add status constraint for proposals
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'proposals_status_check'
  ) THEN
    ALTER TABLE proposals ADD CONSTRAINT proposals_status_check 
    CHECK (status IN ('pending', 'accepted', 'rejected'));
  END IF;
END $$;

-- Enable RLS on proposals
ALTER TABLE proposals ENABLE ROW LEVEL SECURITY;

-- Enable RLS on application_buckets
ALTER TABLE application_buckets ENABLE ROW LEVEL SECURITY;

-- RLS policies for proposals
DROP POLICY IF EXISTS "Workers can manage own proposals" ON proposals;
CREATE POLICY "Workers can manage own proposals"
  ON proposals
  FOR ALL
  TO authenticated
  USING (worker_id = auth.uid());

DROP POLICY IF EXISTS "Clients can view proposals for their tasks" ON proposals;
CREATE POLICY "Clients can view proposals for their tasks"
  ON proposals
  FOR SELECT
  TO authenticated
  USING (
    task_id IN (
      SELECT t.id FROM tasks t
      JOIN projects p ON t.project_id = p.id
      WHERE p.client_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Clients can update proposals for their tasks" ON proposals;
CREATE POLICY "Clients can update proposals for their tasks"
  ON proposals
  FOR UPDATE
  TO authenticated
  USING (
    task_id IN (
      SELECT t.id FROM tasks t
      JOIN projects p ON t.project_id = p.id
      WHERE p.client_id = auth.uid()
    )
  );

-- RLS policies for application_buckets
DROP POLICY IF EXISTS "Clients can manage own application buckets" ON application_buckets;
CREATE POLICY "Clients can manage own application buckets"
  ON application_buckets
  FOR ALL
  TO authenticated
  USING (client_id = auth.uid());

DROP POLICY IF EXISTS "Clients can view own application buckets" ON application_buckets;
CREATE POLICY "Clients can view own application buckets"
  ON application_buckets
  FOR SELECT
  TO authenticated
  USING (client_id = auth.uid());

-- Add updated_at trigger for proposals
DROP TRIGGER IF EXISTS update_proposals_updated_at ON proposals;
CREATE TRIGGER update_proposals_updated_at
  BEFORE UPDATE ON proposals
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Add updated_at trigger for application_buckets
DROP TRIGGER IF EXISTS update_application_buckets_updated_at ON application_buckets;
CREATE TRIGGER update_application_buckets_updated_at
  BEFORE UPDATE ON application_buckets
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Create secure notification function
CREATE OR REPLACE FUNCTION create_notification_for_user(
  target_user_id uuid,
  notification_title text,
  notification_message text,
  notification_type text DEFAULT 'info'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Validate notification type
  IF notification_type NOT IN ('info', 'success', 'warning', 'error') THEN
    notification_type := 'info';
  END IF;

  -- Insert notification
  INSERT INTO notifications (user_id, title, message, type)
  VALUES (target_user_id, notification_title, notification_message, notification_type);
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION create_notification_for_user TO authenticated;

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_task_applications_bucket_id ON task_applications(bucket_id);
CREATE INDEX IF NOT EXISTS idx_task_applications_status ON task_applications(status);
CREATE INDEX IF NOT EXISTS idx_task_applications_worker_task ON task_applications(worker_id, task_id);
CREATE INDEX IF NOT EXISTS idx_proposals_task_worker ON proposals(task_id, worker_id);
CREATE INDEX IF NOT EXISTS idx_proposals_status ON proposals(status);