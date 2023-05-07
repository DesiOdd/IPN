defmodule BlockStore do
  @table "block"

  use Store.Sqlite,
    base: :block,
    table: @table,
    create: """
    CREATE TABLE IF NOT EXISTS #{@table}(
      height UNSIGNED BIGINT PRIMARY KEY NOT NULL,
      hash BLOB NOT NULL,
      prev BLOB,
      hashfile BLOB NOT NULL,
      round UNSIGNED BIGINT,
      timestamp UNSIGNED BIGINT NOT NULL,
      ev_count UNSIGNED BIGINT DEFAULT 0,
      vsn SMALLINT NOT NULL
    ) WITHOUT ROWID;
    """,
    stmt: %{
      insert: "INSERT INTO #{@table} values(?1,?2,?3,?4,?5,?6,?7,?8)",
      replace: "REPLACE INTO #{@table} values(?1,?2,?3,?4,?5,?6,?7,?8)",
      lookup: "SELECT * FROM #{@table} WHERE height = ?",
      lookup_hash: "SELECT * FROM #{@table} WHERE hash = ? LIMIT 1",
      exists: "SELECT 1 FROM #{@table} WHERE height = ?",
      delete: "DELETE FROM #{@table} WHERE height = ?"
    }
end