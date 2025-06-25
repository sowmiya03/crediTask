/*
  # Proposals, Invitations, and Favorites Tables

  1. New Tables
    - `proposals`
      - `id` (uuid, primary key)
      - `task_id` (uuid, foreign key to tasks)
      - `worker_id` (uuid, foreign key to users)
      - `cover_letter` (text)
      - `proposed_rate` (numeric)
      - `estimated_hours` (integer, optional)
      - `status` (text, default 'pending')
      - `created_at` (timestamp)
      - `updated_at` (timestamp)
    - `invitations`
      - `id` (uuid, primary key)
      - `task_id` (uuid, foreign key to tasks)
      - `client_id` (uuid, foreign key to users)
      - `worker_id` (uuid, foreign key to users)
      - `message` (text, optional)
      - `status` (text, default 'pending')
      - `created_at` (timestamp)
      - `updated_at` (timestamp)
    - `favorites`
      - `id` (uuid, primary key)
      - `user_id` (uuid, foreign key to users)
      - `favorite_user_id` (uuid, foreign key to users)
      - `created_at` (timestamp)

  2. Security
    - Enable RLS on all tables
    - Add policies for role-based access control
    - Workers can manage their own proposals
    - Clients can view/update proposals for their tasks
    - Users can manage their own invitations and favorites
*/

-- Create proposals table
CREATE TABLE IF NOT EXISTS proposals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  worker_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  cover_letter text NOT NULL,
  proposed_rate numeric(10,2),
  estimated_hours integer,
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(task_id, worker_id)
);

-- Create invitations table
CREATE TABLE IF NOT EXISTS invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  client_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  worker_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  message text,
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(task_id, worker_id)
);

-- Create favorites table
CREATE TABLE IF NOT EXISTS favorites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  favorite_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  UNIQUE(user_id, favorite_user_id)
);

-- Enable RLS
ALTER TABLE proposals ENABLE ROW LEVEL SECURITY;
ALTER TABLE invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE favorites ENABLE ROW LEVEL SECURITY;

-- Proposals policies (drop existing ones first to avoid conflicts)
DROP POLICY IF EXISTS "Workers can manage own proposals" ON proposals;
DROP POLICY IF EXISTS "Clients can view proposals for their tasks" ON proposals;
DROP POLICY IF EXISTS "Clients can update proposals for their tasks" ON proposals;

CREATE POLICY "Workers can manage own proposals" ON proposals
  FOR ALL TO authenticated
  USING (worker_id = auth.uid());

CREATE POLICY "Clients can view proposals for their tasks" ON proposals
  FOR SELECT TO authenticated
  USING (task_id IN (
    SELECT t.id FROM tasks t
    JOIN projects p ON t.project_id = p.id
    WHERE p.client_id = auth.uid()
  ));

CREATE POLICY "Clients can update proposals for their tasks" ON proposals
  FOR UPDATE TO authenticated
  USING (task_id IN (
    SELECT t.id FROM tasks t
    JOIN projects p ON t.project_id = p.id
    WHERE p.client_id = auth.uid()
  ));

-- Invitations policies (drop existing ones first to avoid conflicts)
DROP POLICY IF EXISTS "Clients can manage own invitations" ON invitations;
DROP POLICY IF EXISTS "Workers can view and respond to their invitations" ON invitations;

CREATE POLICY "Clients can manage own invitations" ON invitations
  FOR ALL TO authenticated
  USING (client_id = auth.uid());

CREATE POLICY "Workers can view and respond to their invitations" ON invitations
  FOR ALL TO authenticated
  USING (worker_id = auth.uid());

-- Favorites policies (drop existing ones first to avoid conflicts)
DROP POLICY IF EXISTS "Users can manage own favorites" ON favorites;

CREATE POLICY "Users can manage own favorites" ON favorites
  FOR ALL TO authenticated
  USING (user_id = auth.uid());

-- Create triggers for updated_at
DROP TRIGGER IF EXISTS update_proposals_updated_at ON proposals;
DROP TRIGGER IF EXISTS update_invitations_updated_at ON invitations;

CREATE TRIGGER update_proposals_updated_at
  BEFORE UPDATE ON proposals
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_invitations_updated_at
  BEFORE UPDATE ON invitations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();