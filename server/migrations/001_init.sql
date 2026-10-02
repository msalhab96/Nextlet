CREATE TABLE app_meta (
  key text PRIMARY KEY,
  value jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 60),
  color text NOT NULL CHECK (color ~ '^#[0-9A-Fa-f]{6}$'),
  sort_order double precision NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Quick add matches "#name" against project names, so names must be unambiguous.
CREATE UNIQUE INDEX projects_name_key ON projects (lower(btrim(name)));

CREATE TABLE tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 500),
  notes text NOT NULL DEFAULT '' CHECK (char_length(notes) <= 20000),
  project_id uuid REFERENCES projects (id) ON DELETE SET NULL,
  -- Tasks belong to a day, never an hour. NULL means the task sits in the Inbox.
  -- Once a task is completed, day is the day it was done.
  day date,
  -- The day the task was last deliberately scheduled for. Pushing a task to the
  -- next day leaves this alone, which is how the app knows to say "From Tue".
  planned_day date,
  estimate_minutes integer CHECK (estimate_minutes BETWEEN 1 AND 1440),
  priority smallint NOT NULL DEFAULT 0 CHECK (priority BETWEEN 0 AND 3),
  repeat jsonb,
  sort_order double precision NOT NULL DEFAULT 0,
  completed_at timestamptz,
  -- Where the task was scheduled before it was completed, so "undo" can put it back.
  completed_from_day date,
  -- Set when the task was pushed to a later day; cleared when it is rescheduled.
  postponed_at timestamptz,
  -- The occurrence created when a repeating task was completed.
  next_occurrence_id uuid REFERENCES tasks (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX tasks_open_idx ON tasks (day, sort_order) WHERE completed_at IS NULL;
CREATE INDEX tasks_done_day_idx ON tasks (day) WHERE completed_at IS NOT NULL;
CREATE INDEX tasks_project_idx ON tasks (project_id);

CREATE TABLE subtasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES tasks (id) ON DELETE CASCADE,
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 500),
  done boolean NOT NULL DEFAULT false,
  sort_order double precision NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX subtasks_task_idx ON subtasks (task_id, sort_order);
