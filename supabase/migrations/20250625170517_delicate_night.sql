/*
  # Add Chat System Tables

  1. New Tables
    - `chat_channels` - Chat channels for projects
    - `old__chat_rooms` - Legacy chat rooms (kept for compatibility)
    - `old__chat_participants` - Legacy chat participants
    - `old__chat_messages` - Legacy chat messages

  2. Security
    - Enable RLS on all new tables
    - Add appropriate policies for chat access
*/

-- Chat channels table (new system)
CREATE TABLE IF NOT EXISTS chat_channels (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  name text NOT NULL,
  type text DEFAULT 'project' CHECK (type IN ('project', 'direct')),
  participants uuid[] NOT NULL,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE chat_channels ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can create project channels" ON chat_channels;
CREATE POLICY "Users can create project channels"
  ON chat_channels FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = created_by);

DROP POLICY IF EXISTS "Users can view channels they participate in" ON chat_channels;
CREATE POLICY "Users can view channels they participate in"
  ON chat_channels FOR SELECT
  TO authenticated
  USING (auth.uid() = ANY(participants));

-- Legacy chat rooms (kept for compatibility)
CREATE TABLE IF NOT EXISTS old__chat_rooms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  is_group boolean DEFAULT false,
  project_id uuid REFERENCES projects(id) ON DELETE CASCADE,
  name text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE old__chat_rooms ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can create chat rooms" ON old__chat_rooms;
CREATE POLICY "Users can create chat rooms"
  ON old__chat_rooms FOR INSERT
  TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "Users can view their chat rooms" ON old__chat_rooms;
CREATE POLICY "Users can view their chat rooms"
  ON old__chat_rooms FOR SELECT
  TO authenticated
  USING (id IN (
    SELECT chat_room_id FROM old__chat_participants
    WHERE user_id = auth.uid()
  ));

-- Legacy chat participants
CREATE TABLE IF NOT EXISTS old__chat_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_room_id uuid NOT NULL REFERENCES old__chat_rooms(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at timestamptz DEFAULT now()
);

-- Add unique constraint if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'chat_participants_chat_room_id_user_id_key' 
    AND table_name = 'old__chat_participants'
  ) THEN
    ALTER TABLE old__chat_participants ADD CONSTRAINT chat_participants_chat_room_id_user_id_key UNIQUE(chat_room_id, user_id);
  END IF;
END $$;

ALTER TABLE old__chat_participants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can join chats they have access to" ON old__chat_participants;
CREATE POLICY "Users can join chats they have access to"
  ON old__chat_participants FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = auth.uid() OR 
    chat_room_id IN (
      SELECT cr.id FROM old__chat_rooms cr
      JOIN projects p ON cr.project_id = p.id
      WHERE p.client_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can view participants in their chats" ON old__chat_participants;
CREATE POLICY "Users can view participants in their chats"
  ON old__chat_participants FOR SELECT
  TO authenticated
  USING (chat_room_id IN (
    SELECT chat_room_id FROM old__chat_participants
    WHERE user_id = auth.uid()
  ));

-- Legacy chat messages
CREATE TABLE IF NOT EXISTS old__chat_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  channel_id uuid NOT NULL REFERENCES chat_channels(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content text NOT NULL,
  message_type text DEFAULT 'text' CHECK (message_type IN ('text', 'file', 'system')),
  file_url text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE old__chat_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can send messages to their channels" ON old__chat_messages;
CREATE POLICY "Users can send messages to their channels"
  ON old__chat_messages FOR INSERT
  TO authenticated
  WITH CHECK (channel_id IN (
    SELECT id FROM chat_channels
    WHERE auth.uid() = ANY(participants)
  ));

DROP POLICY IF EXISTS "Users can view messages in their channels" ON old__chat_messages;
CREATE POLICY "Users can view messages in their channels"
  ON old__chat_messages FOR SELECT
  TO authenticated
  USING (channel_id IN (
    SELECT id FROM chat_channels
    WHERE auth.uid() = ANY(participants)
  ));

-- Add triggers for updated_at
DROP TRIGGER IF EXISTS update_chat_channels_updated_at ON chat_channels;
CREATE TRIGGER update_chat_channels_updated_at
  BEFORE UPDATE ON chat_channels
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();