/*
  # Fix Chat Messages Table Reference

  1. Tables
    - Fix chat_messages table to reference correct chat_rooms table
    - Ensure all foreign key references are correct

  2. Security
    - Maintain existing RLS policies
    - Fix any broken policy references
*/

-- Fix chat_messages table to reference the correct chat_rooms table
-- First, check if the old table exists and drop the constraint if needed
DO $$
BEGIN
  -- Drop the foreign key constraint if it exists with old reference
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'chat_messages_channel_id_fkey' 
    AND table_name = 'chat_messages'
  ) THEN
    ALTER TABLE chat_messages DROP CONSTRAINT chat_messages_channel_id_fkey;
  END IF;
  
  -- Drop the old column if it exists
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'chat_messages' AND column_name = 'channel_id'
  ) THEN
    ALTER TABLE chat_messages DROP COLUMN channel_id;
  END IF;
END $$;

-- Ensure chat_messages has the correct structure
DO $$
BEGIN
  -- Add chat_room_id column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'chat_messages' AND column_name = 'chat_room_id'
  ) THEN
    ALTER TABLE chat_messages ADD COLUMN chat_room_id uuid NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE;
  END IF;
END $$;

-- Fix any broken RLS policies that might reference old table names
DROP POLICY IF EXISTS "Users can send messages to their channels" ON chat_messages;
DROP POLICY IF EXISTS "Users can view messages in their channels" ON chat_messages;

-- Recreate the correct policies
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

-- Ensure all tables exist with correct structure
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

-- Enable RLS on chat_channels if it exists
ALTER TABLE chat_channels ENABLE ROW LEVEL SECURITY;

-- Create policies for chat_channels
DROP POLICY IF EXISTS "Users can create project channels" ON chat_channels;
DROP POLICY IF EXISTS "Users can view channels they participate in" ON chat_channels;

CREATE POLICY "Users can create project channels" ON chat_channels
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Users can view channels they participate in" ON chat_channels
  FOR SELECT TO authenticated
  USING (auth.uid() = ANY(participants));

-- Create trigger for chat_channels updated_at
DROP TRIGGER IF EXISTS update_chat_channels_updated_at ON chat_channels;
CREATE TRIGGER update_chat_channels_updated_at
  BEFORE UPDATE ON chat_channels
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Fix any references to old chat tables in the old__chat_messages table
DO $$
BEGIN
  -- Check if old__chat_messages exists and has wrong references
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'old__chat_messages') THEN
    -- Drop and recreate the foreign key constraint if needed
    IF EXISTS (
      SELECT 1 FROM information_schema.table_constraints 
      WHERE constraint_name = 'chat_messages_channel_id_fkey' 
      AND table_name = 'old__chat_messages'
    ) THEN
      ALTER TABLE old__chat_messages DROP CONSTRAINT chat_messages_channel_id_fkey;
    END IF;
    
    -- Add correct foreign key if channel_id column exists
    IF EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_name = 'old__chat_messages' AND column_name = 'channel_id'
    ) THEN
      ALTER TABLE old__chat_messages 
      ADD CONSTRAINT old_chat_messages_channel_id_fkey 
      FOREIGN KEY (channel_id) REFERENCES chat_channels(id) ON DELETE CASCADE;
    END IF;
  END IF;
END $$;