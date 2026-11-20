begin
  sys.dbms_scheduler.create_job
    (
       job_name        => 'EMAIL_QUEUE_JOB'
      ,start_date      => systimestamp
      ,repeat_interval => 'FREQ=MINUTELY;INTERVAL=10'
      ,end_date        => null
      ,job_type        => 'STORED_PROCEDURE'
      ,job_action      => 'EMAIL_PKG.PROCESS_QUEUE'
      ,comments        => 'Sends emails from queue'
    );
  sys.dbms_scheduler.set_attribute
    ( name      => 'EMAIL_QUEUE_JOB'
     ,attribute => 'RESTARTABLE'
     ,value     => false);
  sys.dbms_scheduler.set_attribute
    ( name      => 'EMAIL_QUEUE_JOB'
     ,attribute => 'LOGGING_LEVEL'
     ,value     => sys.dbms_scheduler.logging_off);
  sys.dbms_scheduler.set_attribute_null
    ( name      => 'EMAIL_QUEUE_JOB'
     ,attribute => 'MAX_FAILURES');
  sys.dbms_scheduler.set_attribute_null
    ( name      => 'EMAIL_QUEUE_JOB'
     ,attribute => 'MAX_RUNS');
  sys.dbms_scheduler.set_attribute
    ( name      => 'EMAIL_QUEUE_JOB'
     ,attribute => 'STOP_ON_WINDOW_CLOSE'
     ,value     => false);
  sys.dbms_scheduler.set_attribute
    ( name      => 'EMAIL_QUEUE_JOB'
     ,attribute => 'JOB_PRIORITY'
     ,value     => 3);
  sys.dbms_scheduler.set_attribute_null
    ( name      => 'EMAIL_QUEUE_JOB'
     ,attribute => 'SCHEDULE_LIMIT');
  sys.dbms_scheduler.set_attribute
    ( name      => 'EMAIL_QUEUE_JOB'
     ,attribute => 'AUTO_DROP'
     ,value     => false);
  sys.dbms_scheduler.set_attribute
    ( name      => 'EMAIL_QUEUE_JOB'
     ,attribute => 'RESTART_ON_RECOVERY'
     ,value     => false);
  sys.dbms_scheduler.set_attribute
    ( name      => 'EMAIL_QUEUE_JOB'
     ,attribute => 'RESTART_ON_FAILURE'
     ,value     => false);
  sys.dbms_scheduler.set_attribute
    ( name      => 'EMAIL_QUEUE_JOB'
     ,attribute => 'STORE_OUTPUT'
     ,value     => true);

  sys.dbms_scheduler.enable
    (name                  => 'EMAIL_QUEUE_JOB');
end;
/
