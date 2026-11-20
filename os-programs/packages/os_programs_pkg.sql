create or replace package os_programs_pkg as
/*****************************************************************
* Package Name: OS_PROGRAMS_PKG
*
* Description:  Runs Linux scripts from PL/SQL
*
*   Needs:
*   - scheduler program OS_PROGRAM_PROG (scheduler/os_program_prog.sql)
*   - host script run.sh (host/run.sh)
*   - directory OS_PROGRAM_OUTPUT_DIR (scheduler/os_program_output_dir.sql)
*   - a scheduler job per OS script, which uses OS_PROGRAM_PROG.
*     Job argument 1 is the script file name.
*
* Ver    Author                  Date             Comments
* 1.0    Jokke Heikkilä       06.01.2014        First version
******************************************************************/

  type t_args is table of varchar2(32767);


  /*--------------------------------------------------------------*
  *  PROCEDURE run_program
  *  DESCRIPTION
  *    Runs an OS script through a scheduler job and waits for the result.
  *
  *  ARGUMENTS
  *     OUT:
  *       p_ret_code              Return code (1=success, 0=failure)
  *       p_ret_msg               Return message (success/error text)
  *     IN:
  *       p_job_name              Scheduler job name which executes OS program
  *       p_args                  Script arguments (max 17)
  *       p_remove_logs           Removes log files from OS after execution
  *---------------------------------------------------------------*/
  procedure run_program(
    p_ret_code    out varchar2,
    p_ret_msg     out varchar2,
    p_job_name    in  varchar2,
    p_args        in  t_args  default null,
    p_remove_logs in  boolean default false
  );


  /*--------------------------------------------------------------*
  *  PROCEDURE run_program
  *  DESCRIPTION
  *    Same as above, but raises an error if the script fails.
  *
  *  ARGUMENTS
  *     IN:
  *       p_job_name              Scheduler job name which executes OS program
  *       p_args                  Script arguments (max 17)
  *       p_remove_logs           Removes log files from OS after execution
  *---------------------------------------------------------------*/
  procedure run_program(
    p_job_name    in varchar2,
    p_args        in t_args  default null,
    p_remove_logs in boolean default false
  );


end os_programs_pkg;
/


create or replace package body os_programs_pkg as

  /* Forward declarations *****************************/
  function request_lock(p_lock_name in varchar2) return varchar2;

  procedure release_lock(p_lock_handle in varchar2);

  procedure log_error(p_text in varchar2);


  /* Constant variables *******************************/
  c_log_directory constant varchar2(40) := 'OS_PROGRAM_OUTPUT_DIR';


  /* Public subprograms *******************************/

  procedure run_program(
    p_ret_code    out varchar2,
    p_ret_msg     out varchar2,
    p_job_name    in  varchar2,
    p_args        in  t_args  default null,
    p_remove_logs in  boolean default false
  ) is
    l_lock_handle  varchar2(128);
    l_retcode_file varchar2(200);
    l_log_file     varchar2(200);

  begin
    -- program is not allwed to be run simultaneously --> get lock
    l_lock_handle := request_lock($$plsql_unit_owner || '.' || $$plsql_unit || '.' || p_job_name);

    l_retcode_file := sys_context('USERENV', 'DB_NAME')||'_'||p_job_name||'_'||
                    to_char(sysdate, 'YYYYMMDDHH24MISS')||'.retcode';
    l_log_file     := sys_context('USERENV', 'DB_NAME')||'_'||p_job_name||'_'||
                    to_char(sysdate, 'YYYYMMDDHH24MISS')||'.log';

    -- define retcode and log file name
    dbms_scheduler.set_job_argument_value(p_job_name, 2, l_retcode_file);
    dbms_scheduler.set_job_argument_value(p_job_name, 3, l_log_file);

     -- define other arguments
    if p_args is not empty then
      for i in 1 .. p_args.count loop
        dbms_scheduler.set_job_argument_value(p_job_name, i + 3, p_args(i));
      end loop;
    end if;

    -- run
    dbms_scheduler.run_job(
      job_name            => p_job_name,
      use_current_session => true
    );

    -- get output code from os
    begin
      p_ret_code := to_char(dbms_xslprocessor.read2clob(c_log_directory, l_retcode_file));

      if p_remove_logs then
        utl_file.fremove(c_log_directory, l_retcode_file);
      end if;

    exception when others then
      log_error(sqlerrm);
      p_ret_code := 0;
    end;

    -- get output message from os
    begin
      p_ret_msg := substr(dbms_xslprocessor.read2clob(c_log_directory, l_log_file), 1, 4000);

      if p_remove_logs then
        utl_file.fremove(c_log_directory, l_log_file);
      end if;

    exception when others then
      log_error(sqlerrm);
      p_ret_msg := sqlerrm;
    end;

    if nvl(substr(p_ret_code, 0, 1), '0') = '0' then
      log_error(p_job_name || ': ' || p_ret_msg);
    end if;

    -- formats other arguments
    if p_args is not empty then
      for i in 1 .. p_args.count loop
        dbms_scheduler.set_job_argument_value(p_job_name, i + 3, null);
      end loop;
    end if;

    -- release lock
    release_lock(l_lock_handle);

  exception when others then
    log_error(sqlerrm);
    release_lock(l_lock_handle);

    raise;

  end run_program;


  procedure run_program(
    p_job_name    in varchar2,
    p_args        in t_args  default null,
    p_remove_logs in boolean default false
  ) is
    lc varchar2(4000);
    lo varchar2(4000);
  begin
    os_programs_pkg.run_program(lc, lo, p_job_name, p_args, p_remove_logs);

    if nvl(substr(lc, 0, 1), '0') <> '1' then
      raise_application_error(-20000, lo);
    end if;

  end run_program;


  /* Private subprograms  *****************************/

  function request_lock(
    p_lock_name in varchar2
  ) return varchar2 is
    l_lock_handle varchar2(128);
    l_status      pls_integer;
  begin
    -- NOTE: allocate_unique does commit
    dbms_lock.allocate_unique(p_lock_name, l_lock_handle);

    l_status := dbms_lock.request(l_lock_handle, dbms_lock.x_mode);

    -- 0 = success, 4 = already own the lock
    if l_status not in (0, 4) then
      raise program_error;
    end if;

    return l_lock_handle;

  end request_lock;


  procedure release_lock(
    p_lock_handle in varchar2
  ) is
    l_status pls_integer;
  begin
    if p_lock_handle is null then
      return;
    end if;

    l_status := dbms_lock.release(p_lock_handle);

    -- 0 = success, 4 = do not own the lock
    if l_status not in (0, 4) then
      raise program_error;
    end if;

  end release_lock;


  procedure log_error(
    p_text in varchar2
  ) is
  begin
    dbms_output.put_line('OS_PROGRAMS_PKG: ' || p_text);

    -- Implement logging according to your system
  end log_error;

end os_programs_pkg;
/
