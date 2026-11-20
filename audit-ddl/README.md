# AUDIT_DDL

Database-wide DDL auditing with a tamper-protection trigger that blocks `UPDATE`/`DELETE` on the audit table for non-`SYS` users.

## Objects

- `types/audit_array.sql` — Nested table type for granted/revoked privileges and users.
- `tables/audit_ddl.sql` — Audit log table and indexes.
- `triggers/audit_ddl_trg.sql` — `SYS` database-level `AFTER DDL` trigger.
- `triggers/audit_ddl_denial_trigger.sql` — `SYS` trigger preventing non-`SYS` updates/deletes on `AUDIT_DDL`.

## Installation

1. Connect as the audit schema owner (e.g. `AUDIT_OWNER`) and run:
   ```sql
   @types/audit_array.sql
   @tables/audit_ddl.sql
   ```
2. Edit `DEFINE audit_owner` in both trigger scripts and adjust the schema/object filters in `triggers/audit_ddl_trg.sql` to match your environment.
3. Connect as `SYS` and run:
   ```sql
   @triggers/audit_ddl_trg.sql
   @triggers/audit_ddl_denial_trigger.sql
   ```
