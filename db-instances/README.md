# DB_INSTANCES_PKG

Query remote database names, user sessions, and dynamic SQL across multiple databases through DB links.

## Prerequisites

- Database link(s) to the target database(s).
- `SELECT` privilege on `gv$session` and `gv$process` on the remote databases (required for `list_processes`).

## Setup

1. By default, `database_links_cursor` in `db_instances_pkg.sql` reads from `user_db_links`. Customize the cursor if you want to filter which DB links are queried.
2. Compile `db_instances_pkg.sql`.

## Usage

```sql
-- List reachable databases
select * from table(db_instances_pkg.get_list);

-- List sessions across all databases
select * from table(db_instances_pkg.list_processes);
```

For `run_query` and `run_query_xml`, place `@DB_LINK@` after each remote table name (e.g. `select * from dual@DB_LINK@`).
