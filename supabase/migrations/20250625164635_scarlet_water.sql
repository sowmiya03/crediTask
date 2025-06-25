/*
  # Chat Channels System

  1. New Tables
    - `chat_channels`
      - `id` (uuid, primary key)
      - `project_id` (uuid, foreign key to projects)
      - `name` (text)
      - `type` (text, default 'project')
      - `participants` (uuid array)
      - `created_by` (uuid, foreign key to users)
      - `created_at` (timestamp)
      - `updated_at` (timestamp)

  2. Security
    - Enable RLS on table
    - Users can create project channels
    - Users can view channels they participate in
*/

-- Create chat_channels table
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

-- Enable RLS
ALTER TABLE chat_channels ENABLE ROW LEVEL SECURITY;

-- Chat channels policies (drop existing ones first to avoid conflicts)
DROP POLICY IF EXISTS "Users can create project channels" ON chat_channels;
DROP POLICY IF EXISTS "Users can view channels they participate in" ON chat_channels;

CREATE POLICY "Users can create project channels" ON chat_channels
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Users can view channels they participate in" ON chat_channels
  FOR SELECT TO authenticated
  USING (auth.uid() = ANY(participants));

-- Create trigger for updated_at
DROP TRIGGER IF EXISTS update_chat_channels_updated_at ON chat_channels;

CREATE TRIGGER update_chat_channels_updated_at
  BEFORE UPDATE ON chat_channels
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();