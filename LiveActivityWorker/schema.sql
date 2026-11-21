-- Live Activity wake-up registrations. One row per device push token.
CREATE TABLE IF NOT EXISTS registrations (
  push_token TEXT PRIMARY KEY,
  activity_type TEXT NOT NULL,
  start_time INTEGER NOT NULL,         -- ms since epoch; rows expire after 8 hours
  last_push_time INTEGER NOT NULL DEFAULT 0,
  wakeup_count INTEGER NOT NULL DEFAULT 0
);
