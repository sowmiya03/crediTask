/*
  # Fix Duplicate RLS Policies

  1. Security
    - Safely drop and recreate all RLS policies to avoid duplicates
    - Ensure all policies are created only once, even on re-runs
    - Validate chat schema and fix any broken references

  2. Changes
    - Drop all existing policies with IF EXISTS
    - Recreate policies with proper error handling
    - Fix chat_messages table references
    - Ensure all RLS policies are consistent
*/

-- Function to safely drop policies
CREATE OR REPLACE FUNCTION drop_policy_if_exists(policy_name text, table_name text)
RETURNS void AS $$
BEGIN
  EXECUTE format('DROP POLICY IF EXISTS %I ON %I', policy_name, table_name);
EXCEPTION
  WHEN OTHERS THEN
    -- Ignore errors if policy doesn't exist
    NULL;
END;
$$ LANGUAGE plpgsql;

-- Drop all existing policies safely
SELECT drop_policy_if_exists('Users can read own profile', 'users');
SELECT drop_policy_if_exists('Users can update own profile', 'users');
SELECT drop_policy_if_exists('Users can insert own profile', 'users');

SELECT drop_policy_if_exists('Clients can manage own projects', 'projects');
SELECT drop_policy_if_exists('Workers can view open projects', 'projects');

SELECT drop_policy_if_exists('Clients can manage tasks in own projects', 'tasks');
SELECT drop_policy_if_exists('Workers can view available tasks', 'tasks');
SELECT drop_policy_if_exists('Workers can update assigned tasks', 'tasks');

SELECT drop_policy_if_exists('Clients can manage own application buckets', 'application_buckets');

SELECT drop_policy_if_exists('Workers can manage own applications', 'task_applications');
SELECT drop_policy_if_exists('Clients can view applications for their tasks', 'task_applications');

SELECT drop_policy_if_exists('Workers can manage own proposals', 'proposals');
SELECT drop_policy_if_exists('Clients can view proposals for their tasks', 'proposals');
SELECT drop_policy_if_exists('Clients can update proposals for their tasks', 'proposals');

SELECT drop_policy_if_exists('Workers can manage own submissions', 'submissions');
SELECT drop_policy_if_exists('Clients can view submissions for own projects', 'submissions');

SELECT drop_policy_if_exists('Users can manage own notifications', 'notifications');

SELECT drop_policy_if_exists('Users can create chat rooms', 'chat_rooms');
SELECT drop_policy_if_exists('Users can view their chat rooms', 'chat_rooms');

SELECT drop_policy_if_exists('Users can join chats they have access to', 'chat_participants');
SELECT drop_policy_if_exists('Users can view participants in their chats', 'chat_participants');

-- Drop chat_messages policies (both old and new names)
SELECT drop_policy_if_exists('Users can send messages to their chat rooms', 'chat_messages');
SELECT drop_policy_if_exists('Users can view messages in their chat rooms', 'chat_messages');
SELECT drop_policy_if_exists('Users can send messages to their channels', 'chat_messages');
SELECT drop_policy_if_exists('Users can view messages in their channels', 'chat_messages');

SELECT drop_policy_if_exists('Clients can manage own invitations', 'invitations');
SELECT drop_policy_if_exists('Workers can view and respond to their invitations', 'invitations');

SELECT drop_policy_if_exists('Users can manage own favorites', 'favorites');

SELECT drop_policy_if_exists('Clients can view timers for own tasks', 'auto_assignment_timers');
SELECT drop_policy_if_exists('System can manage auto-assignment timers', 'auto_assignment_timers');

-- Drop chat_channels policies if they exist
SELECT drop_policy_if_exists('Users can create project channels', 'chat_channels');
SELECT drop_policy_if_exists('Users can view channels they participate in', 'chat_channels');

-- Now recreate all policies
-- Users table policies
CREATE POLICY "Users can read own profile" ON users
  FOR SELECT TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON users
  FOR UPDATE TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON users
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = id);

-- Projects table policies
CREATE POLICY "Clients can manage own projects" ON projects
  FOR ALL TO authenticated
  USING (client_id = auth.uid());

CREATE POLICY "Workers can view open projects" ON projects
  FOR SELECT TO authenticated
  USING (status = 'open' OR client_id = auth.uid());

-- Tasks table policies
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
    project_id IN (
      SELECT id FROM projects WHERE client_id = auth.uid()
    )
  );

CREATE POLICY "Workers can update assigned tasks" ON tasks
  FOR UPDATE TO authenticated
  USING (assignee_id = auth.uid())
  WITH CHECK (assignee_id = auth.uid());

-- Application buckets table policies
CREATE POLICY "Clients can manage own application buckets" ON application_buckets
  FOR ALL TO authenticated
  USING (client_id = auth.uid());

-- Task applications table policies
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

-- Proposals table policies
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

-- Submissions table policies
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

-- Notifications table policies
CREATE POLICY "Users can manage own notifications" ON notifications
  FOR ALL TO authenticated
  USING (user_id = auth.uid());

-- Chat rooms table policies
CREATE POLICY "Users can create chat rooms" ON chat_rooms
  FOR INSERT TO authenticated
  WITH CHECK (true);

CREATE POLICY "Users can view their chat rooms" ON chat_rooms
  FOR SELECT TO authenticated
  USING (id IN (
    SELECT chat_room_id FROM chat_participants
    WHERE user_id = auth.uid()
  ));

-- Chat participants table policies
CREATE POLICY "Users can join chats they have access to" ON chat_participants
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid() OR 
    chat_room_id IN (
      SELECT cr.id FROM chat_rooms cr
      JOIN projects p ON cr.project_id = p.id
      WHERE p.client_id = auth.uid()
    )
  );

CREATE POLICY "Users can view participants in their chats" ON chat_participants
  FOR SELECT TO authenticated
  USING (chat_room_id IN (
    SELECT chat_room_id FROM chat_participants
    WHERE user_id = auth.uid()
  ));

-- Chat messages table policies (ensure correct table structure first)
DO $$
BEGIN
  -- Ensure chat_messages has correct structure
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'chat_messages' AND column_name = 'chat_room_id'
  ) THEN
    -- If chat_room_id doesn't exist, add it
    ALTER TABLE chat_messages ADD COLUMN chat_room_id uuid;
    
    -- Add foreign key constraint
    ALTER TABLE chat_messages 
    ADD CONSTRAINT chat_messages_chat_room_id_fkey 
    FOREIGN KEY (chat_room_id) REFERENCES chat_rooms(id) ON DELETE CASCADE;
  END IF;
  
  -- Remove old channel_id column if it exists
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'chat_messages' AND column_name = 'channel_id'
  ) THEN
    -- Drop foreign key constraint first
    IF EXISTS (
      SELECT 1 FROM information_schema.table_constraints 
      WHERE constraint_name = 'chat_messages_channel_id_fkey' 
      AND table_name = 'chat_messages'
    ) THEN
      ALTER TABLE chat_messages DROP CONSTRAINT chat_messages_channel_id_fkey;
    END IF;
    
    -- Drop the column
    ALTER TABLE chat_messages DROP COLUMN channel_id;
  END IF;
END $$;

-- Now create chat_messages policies
CREATE POLICY "Users can send messages to their chat rooms" ON chat_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid() AND 
    chat_room_id IN (
      SELECT chat_room_id FROM chat_participants
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can view messages in their chat rooms" ON chat_messages
  FOR SELECT TO authenticated
  USING (chat_room_id IN (
    SELECT chat_room_id FROM chat_participants
    WHERE user_id = auth.uid()
  ));

-- Invitations table policies
CREATE POLICY "Clients can manage own invitations" ON invitations
  FOR ALL TO authenticated
  USING (client_id = auth.uid());

CREATE POLICY "Workers can view and respond to their invitations" ON invitations
  FOR ALL TO authenticated
  USING (worker_id = auth.uid());

-- Favorites table policies
CREATE POLICY "Users can manage own favorites" ON favorites
  FOR ALL TO authenticated
  USING (user_id = auth.uid());

-- Auto assignment timers table policies
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

-- Handle chat_channels table if it exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'chat_channels') THEN
    -- Create policies for chat_channels
    CREATE POLICY "Users can create project channels" ON chat_channels
      FOR INSERT TO authenticated
      WITH CHECK (auth.uid() = created_by);

    CREATE POLICY "Users can view channels they participate in" ON chat_channels
      FOR SELECT TO authenticated
      USING (auth.uid() = ANY(participants));
  END IF;
END $$;

-- Clean up the helper function
DROP FUNCTION IF EXISTS drop_policy_if_exists(text, text);

-- Ensure all tables have RLS enabled
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE application_buckets ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE proposals ENABLE ROW LEVEL SECURITY;
ALTER TABLE submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE auto_assignment_timers ENABLE ROW LEVEL SECURITY;

-- Enable RLS on chat_channels if it exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'chat_channels') THEN
    ALTER TABLE chat_channels ENABLE ROW LEVEL SECURITY;
  END IF;
END $$;