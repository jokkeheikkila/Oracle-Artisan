# OS_PROGRAMS_PKG

Runs Linux host scripts from PL/SQL via `DBMS_SCHEDULER`, captures return code and stdout/stderr output, and serializes concurrent runs of the same job with `DBMS_LOCK`.

## Prerequisites

- Execute privilege on `DBMS_LOCK` and `UTL_FILE`.
- `CREATE JOB` and `CREATE EXTERNAL JOB` privileges (for `OS_PROGRAM_PROG` and script jobs).
- `READ, WRITE` privileges on the `OS_PROGRAM_OUTPUT_DIR` Oracle directory.

## Installation

1. Copy `host/run.sh` to the database server (e.g. `/path/to/scheduler/run.sh`), make it executable (`chmod +x run.sh`), and create an `output/` subfolder next to it.
2. Place your target shell scripts in the same folder as `run.sh`.
3. Update the directory path and uncomment/set the `GRANT` target schema in `scheduler/os_program_output_dir.sql`, then run it as a DBA/privileged user.
4. Update `program_action` in `scheduler/os_program_prog.sql` to point to `run.sh`, then run it.
5. Optionally customize `log_error` in `packages/os_programs_pkg.sql`, then compile `packages/os_programs_pkg.sql`.
6. Create a `DBMS_SCHEDULER` job per OS script using `program_name => 'OS_PROGRAM_PROG'`, with `P_PROGRAM_FILE` (argument 1) set to the script filename — see `scheduler/example_os_job.sql` for a template.

## Usage

```sql
declare
  l_ret_code varchar2(10);
  l_ret_msg  varchar2(4000);
begin
  os_programs_pkg.run_program(
    p_ret_code    => l_ret_code,
    p_ret_msg     => l_ret_msg,
    p_job_name    => 'EXAMPLE_OS_JOB',
    p_args        => os_programs_pkg.t_args('arg1', 'arg2'),
    p_remove_logs => true
  );
end;
/
```
