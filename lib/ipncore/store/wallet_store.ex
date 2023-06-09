defmodule WalletStore do
  @table "wallet"
  @table_df "wallet_df"

  use Store.Sqlite,
    base: :wallet,
    # pool: :wallet_pool,
    table: @table,
    cache: true,
    cache_size: 50_000_000,
    mod: Ippan.Wallet,
    create: ["
    CREATE TABLE IF NOT EXISTS #{@table}(
      id TEXT PRIMARY KEY NOT NULL,
      pubkey BLOB NOT NULL,
      validator UNSIGNED INTEGER NOT NULL,
      created_at UNSIGNED BIGINT NOT NULL
    ) WITHOUT ROWID;", "CREATE TABLE IF NOT EXISTS #{@table_df}(
      id TEXT PRIMARY KEY NOT NULL,
      pubkey BLOB NOT NULL,
      validator UNSIGNED INTEGER NOT NULL,
      created_at UNSIGNED BIGINT NOT NULL,
      hash BLOB NOT NULL,
      round integer NOT nULL
    ) WITHOUT ROWID;"],
    stmt: %{
      insert: "INSERT INTO #{@table} VALUES(?1,?2,?3,?4)",
      validator: "SELECT pubkey, validator FROM #{@table} WHERE id=?1 AND validator=?2",
      lookup: "SELECT id, pubkey, validator FROM #{@table} WHERE id=?",
      exists: "SELECT 1 FROM #{@table} WHERE id=?",
      delete: "DELETE FROM #{@table} WHERE id=?"
    }
end