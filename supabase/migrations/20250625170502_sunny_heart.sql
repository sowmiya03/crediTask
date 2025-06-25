/*
  # Add Proposals and Invitations Tables

  1. New Tables
    - `proposals` - Worker proposals for tasks
    - `invitations` - Client invitations to workers
    - `favorites` - User favorites system

  2. Security
    - Enable RLS on all new tables
    - Add appropriate policies for each table
*/

-- Proposals table
CREATE TABLE IF NOT EXISTS proposals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  worker_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  cover_letter text NOT NULL,
  proposed_rate numeric(10,2),
  estimated_hours integer,
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Add unique constraint if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'proposals_task_id_worker_id_key' 
    AND table_name = 'proposals'
  ) THEN
    ALTER TABLE proposals ADD CONSTRAINT proposals_task_id_worker_id_key UNIQUE(task_id, worker_id);
  END IF;
END $$;

ALTER TABLE proposals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Workers can manage own proposals" ON proposals;
CREATE POLICY "Workers can manage own proposals"
  ON proposals FOR ALL
  TO authenticated
  USING (worker_id = auth.uid());

DROP POLICY IF EXISTS "Clients can view proposals for their tasks" ON proposals;
CREATE POLICY "Clients can view proposals for their tasks"
  ON proposals FOR SELECT
  TO authenticated
  USING (task_id IN (
    SELECT t.id FROM tasks t
    JOIN projects p ON t.project_id = p.id
    WHERE p.client_id = auth.uid()
  ));

DROP POLICY IF EXISTS "Clients can update proposals for their tasks" ON proposals;
CREATE POLICY "Clients can update proposals for their tasks"
  ON proposals FOR UPDATE
  TO authenticated
  USING (task_id IN (
    SELECT t.id FROM tasks t
    JOIN projects p ON t.project_id = p.id
    WHERE p.client_id = auth.uid()
  ));

-- Invitations table
CREATE TABLE IF NOT EXISTS invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  client_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  worker_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  message text,
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Add unique constraint if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'invitations_task_id_worker_id_key' 
    AND table_name = 'invitations'
  ) THEN
    ALTER TABLE invitations ADD CONSTRAINT invitations_task_id_worker_id_key UNIQUE(task_id, worker_id);
  END IF;
END $$;

ALTER TABLE invitations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Clients can manage own invitations" ON invitations;
CREATE POLICY "Clients can manage own invitations"
  ON invitations FOR ALL
  TO authenticated
  USING (client_id = auth.uid());

DROP POLICY IF EXISTS "Workers can view and respond to their invitations" ON invitations;
CREATE POLICY "Workers can view and respond to their invitations"
  ON invitations FOR ALL
  TO authenticated
  USING (worker_id = auth.uid());

-- Favorites table
CREATE TABLE IF NOT EXISTS favorites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  favorite_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now()
);

-- Add unique constraint if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'favorites_user_id_favorite_user_id_key' 
    AND table_name = 'favorites'
  ) THEN
    ALTER TABLE favorites ADD CONSTRAINT favorites_user_id_favorite_user_id_key UNIQUE(user_id, favorite_user_id);
  END IF;
END $$;

ALTER TABLE favorites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own favorites" ON favorites;
CREATE POLICY "Users can manage own favorites"
  ON favorites FOR ALL
  TO authenticated
  USING (user_id = auth.uid());

-- Add triggers for updated_at
DROP TRIGGER IF EXISTS update_proposals_updated_at ON proposals;
CREATE TRIGGER update_proposals_updated_at
  BEFORE UPDATE ON proposals
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_invitations_updated_at ON invitations;
CREATE TRIGGER update_invitations_updated_at
  BEFORE UPDATE ON invitations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();