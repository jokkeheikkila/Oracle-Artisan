# DB_DATA_SYNC_PKG

Copies table data (`INSERT`, `UPDATE`, `DELETE`) from remote Oracle databases to local tables over database links, driven by the `DB_DATA_SYNC_CONFIG` configuration table.

## Prerequisites

- Database link(s) to the source database(s).
- `SELECT` privilege on remote source tables and DML privileges (`INSERT`, `UPDATE`, `DELETE`) on local target tables.
- Local target tables must have a primary key.

## Installation

1. Optionally customize `do_debug`, `log_info`, and `log_error` in `packages/db_data_sync_pkg.sql`.
2. Run `install.sql` in SQL*Plus or SQLcl:
   ```sql
   @install.sql
   ```

This creates:
- `tables/db_data_sync_config.sql` — Sync definitions table (`DB_DATA_SYNC_CONFIG`).
- `packages/db_data_sync_pkg.sql` — Sync engine (`DB_DATA_SYNC_PKG`).

## Usage

1. Insert one row per synced table into `DB_DATA_SYNC_CONFIG` (see column comments in `tables/db_data_sync_config.sql`).
2. Run all enabled sync definitions:
   ```sql
   begin
     db_data_sync_pkg.main;
   end;
   /
   ```
