# Soulo — Database Schema

## Encryption
All SQLite databases use SQLCipher (AES-256). Key derived from device biometrics (Secure Enclave).

## Schema

```sql
-- ==========================================
-- CORE: Journal entries
-- ==========================================
CREATE TABLE entries (
    id              TEXT PRIMARY KEY,           -- UUID
    timestamp       INTEGER NOT NULL,           -- Unix epoch seconds
    timezone_offset INTEGER NOT NULL DEFAULT 0, -- minutes from UTC
    duration_ms     INTEGER NOT NULL,           -- recording length in ms
    
    -- Audio
    audio_format    TEXT NOT NULL DEFAULT 'aac',   -- aac or wav
    audio_encrypted INTEGER NOT NULL DEFAULT 1,    -- 1 = encrypted at rest
    audio_file_size INTEGER,                       -- bytes
    
    -- Transcription (populated async)
    transcript      TEXT,
    transcript_status TEXT NOT NULL DEFAULT 'pending', -- pending, processing, done, failed
    transcript_error TEXT,
    transcript_ms   INTEGER,                     -- processing time
    
    -- Biomarkers (populated async)
    biomarkers_json TEXT,                         -- serialized VoiceBiomarkers struct
    biomarkers_status TEXT NOT NULL DEFAULT 'pending',
    biomarkers_error TEXT,
    
    -- Emotion (populated async)
    emotion_json    TEXT,
    emotion_status  TEXT NOT NULL DEFAULT 'pending',
    emotion_error   TEXT,
    
    -- Topics (populated async)
    topics_json     TEXT,
    topics_status   TEXT NOT NULL DEFAULT 'pending',
    topics_error    TEXT,
    
    -- Metadata
    app_version     TEXT NOT NULL,
    device_model    TEXT,
    os_version      TEXT,
    created_at      INTEGER NOT NULL DEFAULT (unixepoch()),
    updated_at      INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX idx_entries_timestamp ON entries(timestamp DESC);
CREATE INDEX idx_entries_status ON entries(transcript_status);
CREATE INDEX idx_entries_created ON entries(created_at);

-- ==========================================
-- TOPICS (denormalized for fast queries)
-- ==========================================
CREATE TABLE topics (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id        TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    topic           TEXT NOT NULL,
    sentiment       REAL,                        -- -1.0 to 1.0
    energy          REAL,                        -- 0.0 to 1.0 (vocal energy when on this topic)
    keywords        TEXT,                        -- JSON array of associated keywords
    created_at      INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX idx_topics_entry ON topics(entry_id);
CREATE INDEX idx_topics_name ON topics(topic);
CREATE INDEX idx_topics_sentiment ON topics(sentiment);

-- ==========================================
-- ENTITIES (people, places, companies)
-- ==========================================
CREATE TABLE entities (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id        TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    entity_type     TEXT NOT NULL,               -- person, place, company, etc.
    entity_name     TEXT NOT NULL,
    sentiment       REAL,
    mention_count   INTEGER DEFAULT 1,
    created_at      INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX idx_entities_entry ON entities(entry_id);
CREATE INDEX idx_entities_name ON entities(entity_name);
CREATE INDEX idx_entities_type ON entities(entity_type);

-- ==========================================
-- PATTERNS (detected behavioral patterns)
-- ==========================================
CREATE TABLE patterns (
    id              TEXT PRIMARY KEY,            -- UUID
    pattern_type    TEXT NOT NULL,               -- broken_promise, avoidance, escalation, etc.
    severity        INTEGER NOT NULL DEFAULT 0,  -- 0-100
    title           TEXT NOT NULL,
    message         TEXT NOT NULL,
    data_json       TEXT,                        -- serialized evidence data
    first_detected  INTEGER NOT NULL,
    last_detected   INTEGER NOT NULL,
    occurrence_count INTEGER DEFAULT 1,
    dismissed       INTEGER DEFAULT 0,          -- 1 = user dismissed
    created_at      INTEGER NOT NULL DEFAULT (unixepoch()),
    updated_at      INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX idx_patterns_type ON patterns(pattern_type);
CREATE INDEX idx_patterns_severity ON patterns(severity DESC);
CREATE INDEX idx_patterns_dismissed ON patterns(dismissed);
CREATE INDEX idx_patterns_last ON patterns(last_detected DESC);

-- ==========================================
-- PATTERN EVIDENCE (which entries triggered a pattern)
-- ==========================================
CREATE TABLE pattern_evidence (
    pattern_id      TEXT NOT NULL REFERENCES patterns(id) ON DELETE CASCADE,
    entry_id        TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    relevance       REAL DEFAULT 1.0,            -- how strongly this entry supports the pattern
    created_at      INTEGER NOT NULL DEFAULT (unixepoch()),
    PRIMARY KEY (pattern_id, entry_id)
);

CREATE INDEX idx_evidence_pattern ON pattern_evidence(pattern_id);

-- ==========================================
-- USER BASELINES (rolling stats for anomaly detection)
-- ==========================================
CREATE TABLE user_baselines (
    metric          TEXT PRIMARY KEY,            -- speech_rate, vocal_energy, pitch_variance, etc.
    mean            REAL NOT NULL,
    stddev          REAL NOT NULL,
    min             REAL,
    max             REAL,
    p5              REAL,                        -- 5th percentile
    p25             REAL,                        -- 25th percentile
    p75             REAL,                        -- 75th percentile
    p95             REAL,                        -- 95th percentile
    sample_count    INTEGER NOT NULL DEFAULT 0,
    last_updated    INTEGER NOT NULL
);

-- ==========================================
-- GOALS (user-stated goals with tracking)
-- ==========================================
CREATE TABLE goals (
    id              TEXT PRIMARY KEY,            -- UUID
    goal_text       TEXT NOT NULL,
    original_entry  TEXT NOT NULL REFERENCES entries(id),
    status          TEXT NOT NULL DEFAULT 'active', -- active, abandoned, completed
    first_mentioned INTEGER NOT NULL,
    last_mentioned  INTEGER,
    mention_count   INTEGER DEFAULT 1,
    completion_date INTEGER,
    abandonment_date INTEGER,
    created_at      INTEGER NOT NULL DEFAULT (unixepoch()),
    updated_at      INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX idx_goals_status ON goals(status);
CREATE INDEX idx_goals_first ON goals(first_mentioned);

-- ==========================================
-- APP SETTINGS (user preferences)
-- ==========================================
CREATE TABLE settings (
    key             TEXT PRIMARY KEY,
    value           TEXT NOT NULL,
    updated_at      INTEGER NOT NULL DEFAULT (unixepoch())
);

-- Default settings
INSERT OR IGNORE INTO settings (key, value) VALUES
    ('daily_reminder_time', '09:00'),
    ('daily_reminder_enabled', 'true'),
    ('insight_severity_threshold', '50'),
    ('dark_mode', 'true'),
    ('biometric_lock', 'true'),
    ('backup_enabled', 'false'),
    ('backup_frequency', 'weekly'),
    ('export_include_audio', 'false'),
    ('onboarding_completed', 'false'),
    ('entries_until_paywall', '7'),
    ('subscription_status', 'free');

-- ==========================================
-- SUBSCRIPTION (cached from StoreKit)
-- ==========================================
CREATE TABLE subscription (
    id              INTEGER PRIMARY KEY CHECK (id = 1),  -- singleton row
    status          TEXT NOT NULL DEFAULT 'free',          -- free, trial, active, expired, cancelled
    plan_type       TEXT,                                  -- monthly, annual, family
    original_id     TEXT,                                  -- StoreKit original transaction ID
    current_id      TEXT,                                  -- StoreKit current transaction ID
    expires_at      INTEGER,
    auto_renew      INTEGER DEFAULT 1,
    trial_start     INTEGER,
    trial_end       INTEGER,
    updated_at      INTEGER NOT NULL DEFAULT (unixepoch())
);

INSERT OR IGNORE INTO subscription (id, status) VALUES (1, 'free');

-- ==========================================
-- CRASH LOGS (for debugging, user-opt-in)
-- ==========================================
CREATE TABLE debug_log (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    level           TEXT NOT NULL DEFAULT 'info',  -- info, warn, error, fatal
    component       TEXT,                          -- recording, transcription, biomarkers, etc.
    message         TEXT NOT NULL,
    details_json    TEXT,
    app_version     TEXT,
    device_model    TEXT,
    os_version      TEXT,
    created_at      INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX idx_debug_level ON debug_log(level);
CREATE INDEX idx_debug_component ON debug_log(component);
CREATE INDEX idx_debug_created ON debug_log(created_at DESC);

-- ==========================================
-- MIGRATIONS (schema version tracking)
-- ==========================================
CREATE TABLE schema_migrations (
    version         INTEGER PRIMARY KEY,
    applied_at      INTEGER NOT NULL DEFAULT (unixepoch()),
    description     TEXT NOT NULL
);

INSERT OR IGNORE INTO schema_migrations (version, description) VALUES
    (1, 'Initial schema: entries, topics, entities, patterns, baselines'),
    (2, 'Added goals table'),
    (3, 'Added debug_log table'),
    (4, 'Added subscription table'),
    (5, 'Added settings table');
```

## Key Queries

```sql
-- Daily streak calculation
WITH daily_counts AS (
    SELECT DISTINCT date(timestamp, 'unixepoch') as day
    FROM entries
    WHERE timestamp > unixepoch('now', '-90 days')
)
SELECT COUNT(*) as streak FROM (
    SELECT day, 
           julianday('now') - julianday(day) as days_ago,
           row_number() OVER (ORDER BY day DESC) as rn
    FROM daily_counts
)
WHERE days_ago = rn - 1;  -- consecutive days from today

-- Topic trend (last 30 days vs previous 30 days)
SELECT 
    topic,
    AVG(CASE WHEN e.timestamp > unixepoch('now', '-30 days') THEN sentiment END) as recent_sentiment,
    AVG(CASE WHEN e.timestamp BETWEEN unixepoch('now', '-60 days') AND unixepoch('now', '-30 days') THEN sentiment END) as previous_sentiment,
    COUNT(CASE WHEN e.timestamp > unixepoch('now', '-30 days') THEN 1 END) as recent_count
FROM topics t
JOIN entries e ON t.entry_id = e.id
WHERE e.timestamp > unixepoch('now', '-60 days')
GROUP BY topic
ORDER BY recent_count DESC;

-- Active patterns (non-dismissed, sorted by severity)
SELECT * FROM patterns
WHERE dismissed = 0
ORDER BY severity DESC
LIMIT 20;

-- Broken promise detection
SELECT g.*, e.timestamp as last_mentioned_at
FROM goals g
JOIN entries e ON g.original_entry = e.id
WHERE g.status = 'active'
  AND g.first_mentioned < unixepoch('now', '-30 days')
  AND (g.last_mentioned IS NULL OR g.last_mentioned < unixepoch('now', '-14 days'))
ORDER BY g.first_mentioned ASC;
```
