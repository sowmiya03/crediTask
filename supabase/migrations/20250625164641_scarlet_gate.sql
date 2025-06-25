/*
  # Database Functions and Triggers

  1. Functions
    - `trigger_project_creation()` - Creates chat channel when project is created
    - `trigger_task_assignment()` - Creates notification when task is assigned
    - `handle_new_auto_assign_task()` - Creates timer for auto-assign tasks
    - `handle_new_task_application()` - Manages application buckets
    - `create_notification_for_user()` - Secure function to create notifications

  2. Triggers
    - Project creation trigger
    - Task assignment trigger
    - Auto-assign task trigger
    - Task application trigger
*/

-- Create trigger function for project creation
CREATE OR REPLACE FUNCTION trigger_project_creation()
RETURNS TRIGGER AS $$
BEGIN
  -- Create a project chat channel
  INSERT INTO chat_channels (project_id, name, type, participants, created_by)
  VALUES (
    NEW.id,
    NEW.title || ' - Project Chat',
    'project',
    ARRAY[NEW.client_id],
    NEW.client_id
  );
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger function for task assignment
CREATE OR REPLACE FUNCTION trigger_task_assignment()
RETURNS TRIGGER AS $$
BEGIN
  -- Only trigger if assignee_id changed from null to a value
  IF OLD.assignee_id IS NULL AND NEW.assignee_id IS NOT NULL THEN
    -- Create notification for assigned worker
    INSERT INTO notifications (user_id, title, message, type)
    VALUES (
      NEW.assignee_id,
      'Task Assigned',
      'You have been assigned to task: ' || NEW.title,
      'info'
    );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger function for new auto-assign tasks
CREATE OR REPLACE FUNCTION handle_new_auto_assign_task()
RETURNS TRIGGER AS $$
BEGIN
  -- If auto_assign is true, create timer
  IF NEW.auto_assign = true THEN
    INSERT INTO auto_assignment_timers (
      task_id,
      application_window_minutes,
      window_start,
      window_end
    ) VALUES (
      NEW.id,
      COALESCE(NEW.application_window_minutes, 60),
      now(),
      now() + INTERVAL '1 minute' * COALESCE(NEW.application_window_minutes, 60)
    );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger function for new task applications
CREATE OR REPLACE FUNCTION handle_new_task_application()
RETURNS TRIGGER AS $$
DECLARE
  bucket_id_var uuid;
BEGIN
  -- Get or create application bucket
  SELECT id INTO bucket_id_var
  FROM application_buckets
  WHERE task_id = NEW.task_id;
  
  IF bucket_id_var IS NULL THEN
    -- Create new bucket
    INSERT INTO application_buckets (project_id, task_id, client_id, total_applications)
    SELECT t.project_id, NEW.task_id, p.client_id, 1
    FROM tasks t
    JOIN projects p ON t.project_id = p.id
    WHERE t.id = NEW.task_id
    RETURNING id INTO bucket_id_var;
  ELSE
    -- Update existing bucket
    UPDATE application_buckets
    SET total_applications = total_applications + 1
    WHERE id = bucket_id_var;
  END IF;
  
  -- Set bucket_id on the application
  NEW.bucket_id = bucket_id_var;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create function to create notifications for users
CREATE OR REPLACE FUNCTION create_notification_for_user(
  target_user_id uuid,
  notification_title text,
  notification_message text,
  notification_type text DEFAULT 'info'
)
RETURNS void AS $$
BEGIN
  -- Validate notification type
  IF notification_type NOT IN ('info', 'success', 'warning', 'error') THEN
    RAISE EXCEPTION 'Invalid notification type: %', notification_type;
  END IF;
  
  -- Insert notification
  INSERT INTO notifications (user_id, title, message, type)
  VALUES (target_user_id, notification_title, notification_message, notification_type);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop existing triggers to avoid conflicts
DROP TRIGGER IF EXISTS project_creation_chat_trigger ON projects;
DROP TRIGGER IF EXISTS task_assignment_chat_trigger ON tasks;
DROP TRIGGER IF EXISTS trigger_new_auto_assign_task ON tasks;
DROP TRIGGER IF EXISTS trigger_new_task_application ON task_applications;

-- Create triggers
CREATE TRIGGER project_creation_chat_trigger
  AFTER INSERT ON projects
  FOR EACH ROW EXECUTE FUNCTION trigger_project_creation();

CREATE TRIGGER task_assignment_chat_trigger
  AFTER UPDATE OF assignee_id ON tasks
  FOR EACH ROW EXECUTE FUNCTION trigger_task_assignment();

CREATE TRIGGER trigger_new_auto_assign_task
  AFTER INSERT ON tasks
  FOR EACH ROW EXECUTE FUNCTION handle_new_auto_assign_task();

CREATE TRIGGER trigger_new_task_application
  BEFORE INSERT ON task_applications
  FOR EACH ROW EXECUTE FUNCTION handle_new_task_application();