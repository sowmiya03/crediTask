-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create or update users table
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

-- Create or update projects table
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

-- Create or update tasks table
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

-- Create or update application_buckets table
CREATE TABLE IF NOT EXISTS application_buckets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE UNIQUE,
  client_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  total_applications integer DEFAULT 0,
  reviewed_applications integer DEFAULT 0,
  approved_applications integer DEFAULT 0,
  rejected_applications integer DEFAULT 0,
  status text DEFAULT 'open' CHECK (status IN ('open', 'reviewing', 'closed')),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create or update task_applications table
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

-- Create or update proposals table
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

-- Create or update submissions table
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

-- Create or update notifications table
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

-- Create or update chat_rooms table
CREATE TABLE IF NOT EXISTS chat_rooms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  is_group boolean DEFAULT false,
  project_id uuid REFERENCES projects(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now()
);

-- Create or update chat_participants table
CREATE TABLE IF NOT EXISTS chat_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_room_id uuid NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at timestamptz DEFAULT now(),
  UNIQUE(chat_room_id, user_id)
);

-- Create or update chat_messages table
CREATE TABLE IF NOT EXISTS chat_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_room_id uuid NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  message text NOT NULL,
  sent_at timestamptz DEFAULT now()
);

-- Create or update invitations table
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

-- Create or update favorites table
CREATE TABLE IF NOT EXISTS favorites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  favorite_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  UNIQUE(user_id, favorite_user_id)
);

-- Create or update auto_assignment_timers table
CREATE TABLE IF NOT EXISTS auto_assignment_timers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE UNIQUE,
  application_window_minutes integer DEFAULT 60,
  window_start timestamptz DEFAULT now(),
  window_end timestamptz NOT NULL,
  extensions_count integer DEFAULT 0,
  max_extensions integer DEFAULT 5,
  status text DEFAULT 'active' CHECK (status IN ('active', 'completed', 'cancelled')),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_task_applications_bucket_id ON task_applications(bucket_id);
CREATE INDEX IF NOT EXISTS idx_task_applications_status ON task_applications(status);
CREATE INDEX IF NOT EXISTS idx_task_applications_worker_task ON task_applications(worker_id, task_id);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_is_group ON chat_rooms(is_group);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_project_id ON chat_rooms(project_id);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_project_group ON chat_rooms(project_id, is_group) WHERE is_group = true;
CREATE INDEX IF NOT EXISTS idx_chat_participants_chat_room_id ON chat_participants(chat_room_id);
CREATE INDEX IF NOT EXISTS idx_chat_participants_user_id ON chat_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_participants_lookup ON chat_participants(chat_room_id, user_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_chat_room_id ON chat_messages(chat_room_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_sender_id ON chat_messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_sent_at ON chat_messages(sent_at DESC);

-- Enable Row Level Security on all tables
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

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can read own profile" ON users;
DROP POLICY IF EXISTS "Users can update own profile" ON users;
DROP POLICY IF EXISTS "Users can insert own profile" ON users;

DROP POLICY IF EXISTS "Clients can manage own projects" ON projects;
DROP POLICY IF EXISTS "Workers can view open projects" ON projects;

DROP POLICY IF EXISTS "Clients can manage tasks in own projects" ON tasks;
DROP POLICY IF EXISTS "Workers can view available tasks" ON tasks;
DROP POLICY IF EXISTS "Workers can update assigned tasks" ON tasks;

DROP POLICY IF EXISTS "Clients can manage own application buckets" ON application_buckets;
DROP POLICY IF EXISTS "Clients can view own application buckets" ON application_buckets;

DROP POLICY IF EXISTS "Workers can manage own applications" ON task_applications;
DROP POLICY IF EXISTS "Clients can view applications for their tasks" ON task_applications;

DROP POLICY IF EXISTS "Workers can manage own proposals" ON proposals;
DROP POLICY IF EXISTS "Clients can view proposals for their tasks" ON proposals;
DROP POLICY IF EXISTS "Clients can update proposals for their tasks" ON proposals;

DROP POLICY IF EXISTS "Workers can manage own submissions" ON submissions;
DROP POLICY IF EXISTS "Clients can view submissions for own projects" ON submissions;

DROP POLICY IF EXISTS "Users can manage own notifications" ON notifications;

DROP POLICY IF EXISTS "Users can create chat rooms" ON chat_rooms;
DROP POLICY IF EXISTS "Users can view their chat rooms" ON chat_rooms;

DROP POLICY IF EXISTS "Users can join chats they have access to" ON chat_participants;
DROP POLICY IF EXISTS "Users can view participants in their chats" ON chat_participants;

DROP POLICY IF EXISTS "Users can send messages to their chat rooms" ON chat_messages;
DROP POLICY IF EXISTS "Users can view messages in their chat rooms" ON chat_messages;

DROP POLICY IF EXISTS "Clients can manage own invitations" ON invitations;
DROP POLICY IF EXISTS "Workers can view and respond to their invitations" ON invitations;

DROP POLICY IF EXISTS "Users can manage own favorites" ON favorites;

DROP POLICY IF EXISTS "Clients can view timers for own tasks" ON auto_assignment_timers;
DROP POLICY IF EXISTS "System can manage auto-assignment timers" ON auto_assignment_timers;

-- Create RLS policies for users table
CREATE POLICY "Users can read own profile" ON users
  FOR SELECT TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON users
  FOR UPDATE TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON users
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = id);

-- Create RLS policies for projects table
CREATE POLICY "Clients can manage own projects" ON projects
  FOR ALL TO authenticated
  USING (client_id = auth.uid());

CREATE POLICY "Workers can view open projects" ON projects
  FOR SELECT TO authenticated
  USING (status = 'open' OR client_id = auth.uid());

-- Create RLS policies for tasks table
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

-- Create RLS policies for application_buckets table
CREATE POLICY "Clients can manage own application buckets" ON application_buckets
  FOR ALL TO authenticated
  USING (client_id = auth.uid());

-- Create RLS policies for task_applications table
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

-- Create RLS policies for proposals table
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

-- Create RLS policies for submissions table
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

-- Create RLS policies for notifications table
CREATE POLICY "Users can manage own notifications" ON notifications
  FOR ALL TO authenticated
  USING (user_id = auth.uid());

-- Create RLS policies for chat_rooms table
CREATE POLICY "Users can create chat rooms" ON chat_rooms
  FOR INSERT TO authenticated
  WITH CHECK (true);

CREATE POLICY "Users can view their chat rooms" ON chat_rooms
  FOR SELECT TO authenticated
  USING (id IN (
    SELECT chat_room_id FROM chat_participants
    WHERE user_id = auth.uid()
  ));

-- Create RLS policies for chat_participants table
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

-- Create RLS policies for chat_messages table
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

-- Create RLS policies for invitations table
CREATE POLICY "Clients can manage own invitations" ON invitations
  FOR ALL TO authenticated
  USING (client_id = auth.uid());

CREATE POLICY "Workers can view and respond to their invitations" ON invitations
  FOR ALL TO authenticated
  USING (worker_id = auth.uid());

-- Create RLS policies for favorites table
CREATE POLICY "Users can manage own favorites" ON favorites
  FOR ALL TO authenticated
  USING (user_id = auth.uid());

-- Create RLS policies for auto_assignment_timers table
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

-- Create or replace the update_updated_at_column function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Drop the existing create_notification_for_user function if it exists
DROP FUNCTION IF EXISTS create_notification_for_user(uuid, text, text, text);
DROP FUNCTION IF EXISTS create_notification_for_user(uuid, text, text);

-- Create the create_notification_for_user function
CREATE OR REPLACE FUNCTION create_notification_for_user(
  target_user_id uuid,
  notification_title text,
  notification_message text,
  notification_type text DEFAULT 'info'
)
RETURNS void AS $$
BEGIN
  INSERT INTO notifications (user_id, title, message, type)
  VALUES (target_user_id, notification_title, notification_message, notification_type);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create or replace trigger functions
CREATE OR REPLACE FUNCTION handle_new_task_application()
RETURNS TRIGGER AS $$
BEGIN
  -- Set the bucket_id based on the task_id
  IF NEW.bucket_id IS NULL THEN
    SELECT id INTO NEW.bucket_id
    FROM application_buckets
    WHERE task_id = NEW.task_id;
    
    -- If no bucket exists, create one
    IF NEW.bucket_id IS NULL THEN
      INSERT INTO application_buckets (
        project_id,
        task_id,
        client_id,
        total_applications,
        reviewed_applications,
        approved_applications,
        rejected_applications,
        status
      )
      SELECT 
        t.project_id,
        t.id,
        p.client_id,
        0,
        0,
        0,
        0,
        'open'
      FROM tasks t
      JOIN projects p ON t.project_id = p.id
      WHERE t.id = NEW.task_id
      RETURNING id INTO NEW.bucket_id;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION handle_new_auto_assign_task()
RETURNS TRIGGER AS $$
BEGIN
  -- Only create timer for auto-assign tasks
  IF NEW.auto_assign = true THEN
    INSERT INTO auto_assignment_timers (
      task_id,
      application_window_minutes,
      window_start,
      window_end,
      status
    ) VALUES (
      NEW.id,
      COALESCE(NEW.application_window_minutes, 60),
      now(),
      now() + INTERVAL '1 minute' * COALESCE(NEW.application_window_minutes, 60),
      'active'
    );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trigger_task_assignment()
RETURNS TRIGGER AS $$
BEGIN
  -- Only trigger if assignee_id changed from null to a value
  IF OLD.assignee_id IS NULL AND NEW.assignee_id IS NOT NULL THEN
    -- Create notification for assigned worker
    PERFORM create_notification_for_user(
      NEW.assignee_id,
      'Task Assigned',
      'You have been assigned to task: ' || NEW.title,
      'info'
    );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trigger_project_creation()
RETURNS TRIGGER AS $$
BEGIN
  -- Create a project chat room
  INSERT INTO chat_rooms (is_group, project_id)
  VALUES (true, NEW.id);
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing triggers
DROP TRIGGER IF EXISTS update_users_updated_at ON users;
DROP TRIGGER IF EXISTS update_projects_updated_at ON projects;
DROP TRIGGER IF EXISTS update_tasks_updated_at ON tasks;
DROP TRIGGER IF EXISTS update_application_buckets_updated_at ON application_buckets;
DROP TRIGGER IF EXISTS update_proposals_updated_at ON proposals;
DROP TRIGGER IF EXISTS update_submissions_updated_at ON submissions;
DROP TRIGGER IF EXISTS update_notifications_updated_at ON notifications;
DROP TRIGGER IF EXISTS update_invitations_updated_at ON invitations;
DROP TRIGGER IF EXISTS update_auto_assignment_timers_updated_at ON auto_assignment_timers;

DROP TRIGGER IF EXISTS trigger_new_task_application ON task_applications;
DROP TRIGGER IF EXISTS trigger_new_auto_assign_task ON tasks;
DROP TRIGGER IF EXISTS task_assignment_chat_trigger ON tasks;
DROP TRIGGER IF EXISTS project_creation_chat_trigger ON projects;

-- Create updated_at triggers
CREATE TRIGGER update_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_projects_updated_at
  BEFORE UPDATE ON projects
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_tasks_updated_at
  BEFORE UPDATE ON tasks
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_application_buckets_updated_at
  BEFORE UPDATE ON application_buckets
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_proposals_updated_at
  BEFORE UPDATE ON proposals
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_submissions_updated_at
  BEFORE UPDATE ON submissions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_notifications_updated_at
  BEFORE UPDATE ON notifications
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_invitations_updated_at
  BEFORE UPDATE ON invitations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_auto_assignment_timers_updated_at
  BEFORE UPDATE ON auto_assignment_timers
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Create functional triggers
CREATE TRIGGER trigger_new_task_application
  BEFORE INSERT ON task_applications
  FOR EACH ROW EXECUTE FUNCTION handle_new_task_application();

CREATE TRIGGER trigger_new_auto_assign_task
  AFTER INSERT ON tasks
  FOR EACH ROW EXECUTE FUNCTION handle_new_auto_assign_task();

CREATE TRIGGER task_assignment_chat_trigger
  AFTER UPDATE OF assignee_id ON tasks
  FOR EACH ROW EXECUTE FUNCTION trigger_task_assignment();

CREATE TRIGGER project_creation_chat_trigger
  AFTER INSERT ON projects
  FOR EACH ROW EXECUTE FUNCTION trigger_project_creation();