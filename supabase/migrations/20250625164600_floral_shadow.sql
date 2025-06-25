/*
  # Chat System Tables

  1. New Tables
    - `chat_rooms`
      - `id` (uuid, primary key)
      - `is_group` (boolean, default false)
      - `project_id` (uuid, foreign key to projects, optional)
      - `created_at` (timestamp)
    - `chat_participants`
      - `id` (uuid, primary key)
      - `chat_room_id` (uuid, foreign key to chat_rooms)
      - `user_id` (uuid, foreign key to users)
      - `joined_at` (timestamp)
    - `chat_messages`
      - `id` (uuid, primary key)
      - `chat_room_id` (uuid, foreign key to chat_rooms)
      - `sender_id` (uuid, foreign key to users)
      - `message` (text)
      - `sent_at` (timestamp)

  2. Security
    - Enable RLS on all tables
    - Add policies for chat access control
    - Users can only access chats they participate in
*/

-- Create chat_rooms table
CREATE TABLE IF NOT EXISTS chat_rooms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  is_group boolean DEFAULT false,
  project_id uuid REFERENCES projects(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now()
);

-- Create chat_participants table
CREATE TABLE IF NOT EXISTS chat_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_room_id uuid NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at timestamptz DEFAULT now(),
  UNIQUE(chat_room_id, user_id)
);

-- Create chat_messages table
CREATE TABLE IF NOT EXISTS chat_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_room_id uuid NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  message text NOT NULL,
  sent_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;

-- Chat rooms policies (drop existing ones first to avoid conflicts)
DROP POLICY IF EXISTS "Users can create chat rooms" ON chat_rooms;
DROP POLICY IF EXISTS "Users can view their chat rooms" ON chat_rooms;

CREATE POLICY "Users can create chat rooms" ON chat_rooms
  FOR INSERT TO authenticated
  WITH CHECK (true);

CREATE POLICY "Users can view their chat rooms" ON chat_rooms
  FOR SELECT TO authenticated
  USING (id IN (
    SELECT chat_room_id FROM chat_participants WHERE user_id = auth.uid()
  ));

-- Chat participants policies (drop existing ones first to avoid conflicts)
DROP POLICY IF EXISTS "Users can join chats they have access to" ON chat_participants;
DROP POLICY IF EXISTS "Users can view participants in their chats" ON chat_participants;

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
    SELECT chat_room_id FROM chat_participants WHERE user_id = auth.uid()
  ));

-- Chat messages policies (drop existing ones first to avoid conflicts)
DROP POLICY IF EXISTS "Users can send messages to their chat rooms" ON chat_messages;
DROP POLICY IF EXISTS "Users can view messages in their chat rooms" ON chat_messages;

CREATE POLICY "Users can send messages to their chat rooms" ON chat_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid() AND
    chat_room_id IN (
      SELECT chat_room_id FROM chat_participants WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can view messages in their chat rooms" ON chat_messages
  FOR SELECT TO authenticated
  USING (chat_room_id IN (
    SELECT chat_room_id FROM chat_participants WHERE user_id = auth.uid()
  ));

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_chat_participants_chat_room_id ON chat_participants(chat_room_id);
CREATE INDEX IF NOT EXISTS idx_chat_participants_user_id ON chat_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_participants_lookup ON chat_participants(chat_room_id, user_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_chat_room_id ON chat_messages(chat_room_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_sender_id ON chat_messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_sent_at ON chat_messages(sent_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_project_id ON chat_rooms(project_id);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_is_group ON chat_rooms(is_group);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_project_group ON chat_rooms(project_id, is_group) WHERE is_group = true;