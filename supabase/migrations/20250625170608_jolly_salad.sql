/*
  # Add Database Functions and Triggers

  1. Functions
    - Task assignment trigger function
    - Project creation trigger function
    - Auto-assignment task handler
    - Task application handler
    - Notification creation function

  2. Triggers
    - Task assignment chat trigger
    - Project creation chat trigger
    - New auto-assign task trigger
    - New task application trigger
*/

-- Function to handle task assignment
CREATE OR REPLACE FUNCTION trigger_task_assignment()
RETURNS TRIGGER AS $$
BEGIN
  -- Only proceed if assignee_id actually changed and is not null
  IF OLD.assignee_id IS DISTINCT FROM NEW.assignee_id AND NEW.assignee_id IS NOT NULL THEN
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

-- Function to handle project creation
CREATE OR REPLACE FUNCTION trigger_project_creation()
RETURNS TRIGGER AS $$
BEGIN
  -- Create notification for project creator
  INSERT INTO notifications (user_id, title, message, type)
  VALUES (
    NEW.client_id,
    'Project Created',
    'Your project "' || NEW.title || '" has been created successfully',
    'success'
  );
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to handle new auto-assign tasks
CREATE OR REPLACE FUNCTION handle_new_auto_assign_task()
RETURNS TRIGGER AS $$
BEGIN
  -- Only create timer if auto_assign is true
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

-- Function to handle new task applications
CREATE OR REPLACE FUNCTION handle_new_task_application()
RETURNS TRIGGER AS $$
DECLARE
  bucket_id_var uuid;
  task_info RECORD;
BEGIN
  -- Get task and project info
  SELECT t.*, p.client_id, p.title as project_title
  INTO task_info
  FROM tasks t
  JOIN projects p ON t.project_id = p.id
  WHERE t.id = NEW.task_id;
  
  -- Get or create application bucket
  SELECT id INTO bucket_id_var
  FROM application_buckets
  WHERE task_id = NEW.task_id;
  
  IF bucket_id_var IS NULL THEN
    INSERT INTO application_buckets (
      project_id,
      task_id,
      client_id,
      total_applications,
      reviewed_applications,
      approved_applications,
      rejected_applications,
      status
    ) VALUES (
      task_info.project_id,
      NEW.task_id,
      task_info.client_id,
      1,
      0,
      0,
      0,
      'open'
    ) RETURNING id INTO bucket_id_var;
  ELSE
    -- Update application count
    UPDATE application_buckets
    SET total_applications = total_applications + 1
    WHERE id = bucket_id_var;
  END IF;
  
  -- Set the bucket_id for the new application
  NEW.bucket_id = bucket_id_var;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to create notifications for users (secure RPC)
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

-- Add triggers
DROP TRIGGER IF EXISTS task_assignment_chat_trigger ON tasks;
CREATE TRIGGER task_assignment_chat_trigger
  AFTER UPDATE OF assignee_id ON tasks
  FOR EACH ROW
  EXECUTE FUNCTION trigger_task_assignment();

DROP TRIGGER IF EXISTS project_creation_chat_trigger ON projects;
CREATE TRIGGER project_creation_chat_trigger
  AFTER INSERT ON projects
  FOR EACH ROW
  EXECUTE FUNCTION trigger_project_creation();

DROP TRIGGER IF EXISTS trigger_new_auto_assign_task ON tasks;
CREATE TRIGGER trigger_new_auto_assign_task
  AFTER INSERT ON tasks
  FOR EACH ROW
  EXECUTE FUNCTION handle_new_auto_assign_task();

DROP TRIGGER IF EXISTS trigger_new_task_application ON task_applications;
CREATE TRIGGER trigger_new_task_application
  BEFORE INSERT ON task_applications
  FOR EACH ROW
  EXECUTE FUNCTION handle_new_task_application();