CREATE TABLE IF NOT EXISTS env(
    name TEXT PRIMARY KEY NOT NULL,
    value BLOB,
    created_at BIGINT NOT NULL
) WITHOUT ROWID;