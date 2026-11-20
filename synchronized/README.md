# SYNCHRONIZED_PKG

Provides PL/SQL block-level locking using `DBMS_LOCK`, similar to Java's `synchronized` block.

## Prerequisites

- Execute privilege on `DBMS_LOCK`.

## Installation

Compile `synchronized_pkg.sql`.

## Usage

```sql
declare
  l_lock_id varchar2(128);
begin
  l_lock_id := synchronized_pkg.start_block('MY_CRITICAL_SECTION');
  -- critical section
  synchronized_pkg.stop_block(l_lock_id);
exception
  when others then
    synchronized_pkg.stop_block(l_lock_id);
    raise;
end;
/
```

> **Note:** `start_block` performs a `COMMIT` (via `DBMS_LOCK.ALLOCATE_UNIQUE`). Always call `stop_block` in the exception handler as well.
