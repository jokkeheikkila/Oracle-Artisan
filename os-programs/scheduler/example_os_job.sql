-- Example scheduler job for running a Linux script via OS_PROGRAMS_PKG.
-- Configure job_name, P_PROGRAM_FILE, and comments according to your system.

BEGIN
  SYS.DBMS_SCHEDULER.CREATE_JOB
    (
       job_name        => 'EXAMPLE_OS_JOB'
      -- Far-future start_date prevents the job from running automatically when enabled;
      -- it is executed on demand by OS_PROGRAMS_PKG.run_program.
      ,start_date      => TIMESTAMP '4000-01-01 00:00:00 UTC'
      ,repeat_interval => NULL
      ,end_date        => NULL
      ,program_name    => 'OS_PROGRAM_PROG'
      ,comments        => 'Example job for OS_PROGRAMS_PKG. Runs a Linux host script on demand.'
    );
  SYS.DBMS_SCHEDULER.SET_ATTRIBUTE
    ( name      => 'EXAMPLE_OS_JOB'
     ,attribute => 'RESTARTABLE'
     ,value     => FALSE);
  SYS.DBMS_SCHEDULER.SET_ATTRIBUTE
    ( name      => 'EXAMPLE_OS_JOB'
     ,attribute => 'LOGGING_LEVEL'
     ,value     => SYS.DBMS_SCHEDULER.LOGGING_OFF);
  SYS.DBMS_SCHEDULER.SET_ATTRIBUTE_NULL
    ( name      => 'EXAMPLE_OS_JOB'
     ,attribute => 'MAX_FAILURES');
  SYS.DBMS_SCHEDULER.SET_ATTRIBUTE_NULL
    ( name      => 'EXAMPLE_OS_JOB'
     ,attribute => 'MAX_RUNS');
  SYS.DBMS_SCHEDULER.SET_ATTRIBUTE
    ( name      => 'EXAMPLE_OS_JOB'
     ,attribute => 'STOP_ON_WINDOW_CLOSE'
     ,value     => FALSE);
  SYS.DBMS_SCHEDULER.SET_ATTRIBUTE
    ( name      => 'EXAMPLE_OS_JOB'
     ,attribute => 'JOB_PRIORITY'
     ,value     => 3);
  SYS.DBMS_SCHEDULER.SET_ATTRIBUTE_NULL
    ( name      => 'EXAMPLE_OS_JOB'
     ,attribute => 'SCHEDULE_LIMIT');
  SYS.DBMS_SCHEDULER.SET_ATTRIBUTE
    ( name      => 'EXAMPLE_OS_JOB'
     ,attribute => 'AUTO_DROP'
     ,value     => FALSE);

  -- Script path relative to host/run.sh (e.g. 'my_script.sh' or 'subfolder/my_script.sh').
  -- P_RETCODE_FILE, P_LOG_FILE, and P_ATTRIBUTE1..P_ATTRIBUTE17 are set dynamically by OS_PROGRAMS_PKG.
  SYS.DBMS_SCHEDULER.SET_JOB_ARGUMENT_VALUE
    ( job_name             => 'EXAMPLE_OS_JOB'
     ,argument_name        => 'P_PROGRAM_FILE'
     ,argument_value       => 'example_script.sh');

  SYS.DBMS_SCHEDULER.ENABLE
    (name                  => 'EXAMPLE_OS_JOB');
END;
/
