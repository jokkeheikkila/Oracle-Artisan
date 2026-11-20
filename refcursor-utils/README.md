# REFCURSOR_UTILS_PKG

Utilities for working with `SYS_REFCURSOR` in PL/SQL:

- `procedure_wrapper` — Executes a dynamic PL/SQL block with a `SYS_REFCURSOR` `OUT` parameter in an autonomous transaction (commits) and returns the cursor (usable from SQL).
- `cursor_to_table` — Inserts all rows of a `SYS_REFCURSOR` into a target table by matching column names (`VARCHAR2`, `CHAR`, `NUMBER`, `DATE`).
- `procedure_to_table` — Runs `procedure_wrapper` and `cursor_to_table`, then commits.

## Installation

1. Optionally customize error logging in the `cursor_to_table` exception handler in `refcursor_utils_pkg.sql`.
2. Compile `refcursor_utils_pkg.sql`.
