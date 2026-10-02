-- Optional tags on a task, such as {phone, errands}. Most tasks have none.
ALTER TABLE tasks ADD COLUMN tags text[] NOT NULL DEFAULT '{}';
ALTER TABLE tasks ADD CONSTRAINT tasks_tags_check CHECK (cardinality(tags) <= 20);
CREATE INDEX tasks_tags_idx ON tasks USING gin (tags);
