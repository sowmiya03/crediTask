/*
  # Initial Database Schema Setup

  1. New Tables
    - `users` - User profiles with role-based access
    - `projects` - Client projects
    - `tasks` - Individual tasks within projects
    - `submissions` - Task submissions from workers
    - `notifications` - User notifications

  2. Security
    - Enable RLS on all tables
    - Add appropriate policies for role-based access
    - Create update triggers for timestamp management

  3. Functions
    - `update_updated_at_column()` - Automatic timestamp updates
*/

-- Create update_updated_at_column function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create users table
CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text UNIQUE NOT NULL,
  name text,
  role text NOT NULL CHECK (role IN ('client', 'worker')),
  skills text[] DEFAULT '{}',
  rating numeric(3,2) DEFAULT 0 CHECK (rating >= 0 AND rating <= 5),
  wallet_balance numeric(10,2) DEFAULT 0,
  avatar_url text,
  tier text DEFAULT 'bronze' CHECK (tier IN ('bronze', 'silver', 'gold', 'platinum')),
  onboarding_completed boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create projects table
CREATE TABLE IF NOT EXISTS projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title text NOT NULL,
  description text NOT NULL,
  tags text[] DEFAULT '{}',
  budget numeric(10,2) NOT NULL CHECK (budget > 0),
  status text DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'completed', 'closed')),
  requirements_form jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create tasks table
CREATE TABLE IF NOT EXISTS tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  title text NOT NULL,
  description text NOT NULL,
  requirements_form jsonb,
  weight integer DEFAULT 1 CHECK (weight >= 1 AND weight <= 10),
  assignee_id uuid REFERENCES users(id) ON DELETE SET NULL,
  status text DEFAULT 'open' CHECK (status IN ('open', 'assigned', 'submitted', 'approved', 'rejected')),
  payout numeric(10,2) NOT NULL CHECK (payout > 0),
  deadline timestamptz,
  pricing_type text DEFAULT 'fixed' CHECK (pricing_type IN ('fixed', 'hourly')),
  hourly_rate numeric(10,2),
  estimated_hours integer,
  application_deadline timestamptz,
  required_skills text[] DEFAULT '{}',
  auto_assign boolean DEFAULT true,
  application_window_minutes integer DEFAULT 60,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create submissions table
CREATE TABLE IF NOT EXISTS submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  worker_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  files text[] DEFAULT '{}',
  comments text NOT NULL,
  verified_by text CHECK (verified_by IN ('ai', 'client')),
  outcome text DEFAULT 'pending' CHECK (outcome IN ('pass', 'fail', 'pending')),
  submitted_at timestamptz DEFAULT now(),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create notifications table
CREATE TABLE IF NOT EXISTS notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title text NOT NULL,
  message text NOT NULL,
  type text DEFAULT 'info' CHECK (type IN ('info', 'success', 'warning', 'error')),
  read boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Users policies
CREATE POLICY "Users can read own profile" ON users
  FOR SELECT TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON users
  FOR UPDATE TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON users
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = id);

-- Projects policies
CREATE POLICY "Clients can manage own projects" ON projects
  FOR ALL TO authenticated
  USING (client_id = auth.uid());

CREATE POLICY "Workers can view open projects" ON projects
  FOR SELECT TO authenticated
  USING (status = 'open' OR client_id = auth.uid());

-- Tasks policies
CREATE POLICY "Clients can manage tasks in own projects" ON tasks
  FOR ALL TO authenticated
  USING (project_id IN (
    SELECT id FROM projects WHERE client_id = auth.uid()
  ));

CREATE POLICY "Workers can view available tasks" ON tasks
  FOR SELECT TO authenticated
  USING (
    status = 'open' OR 
    assignee_id = auth.uid() OR 
    project_id IN (SELECT id FROM projects WHERE client_id = auth.uid())
  );

CREATE POLICY "Workers can update assigned tasks" ON tasks
  FOR UPDATE TO authenticated
  USING (assignee_id = auth.uid())
  WITH CHECK (assignee_id = auth.uid());

-- Submissions policies
CREATE POLICY "Workers can manage own submissions" ON submissions
  FOR ALL TO authenticated
  USING (worker_id = auth.uid());

CREATE POLICY "Clients can view submissions for own projects" ON submissions
  FOR SELECT TO authenticated
  USING (task_id IN (
    SELECT t.id FROM tasks t
    JOIN projects p ON t.project_id = p.id
    WHERE p.client_id = auth.uid()
  ));

-- Notifications policies
CREATE POLICY "Users can manage own notifications" ON notifications
  FOR ALL TO authenticated
  USING (user_id = auth.uid());

-- Create triggers for updated_at
CREATE TRIGGER update_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_projects_updated_at
  BEFORE UPDATE ON projects
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_tasks_updated_at
  BEFORE UPDATE ON tasks
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_submissions_updated_at
  BEFORE UPDATE ON submissions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_notifications_updated_at
  BEFORE UPDATE ON notifications
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();