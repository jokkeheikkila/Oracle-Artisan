begin
  sys.dbms_scheduler.create_program
    (
      program_name         => 'OS_PROGRAM_PROG'
     ,program_type         => 'EXECUTABLE'
     ,program_action       => '/path/to/scheduler/run.sh' -- configure according to your system: full path of host/run.sh on the DB server
     ,number_of_arguments  => 20 -- 3 fixed (script, retcode file, log file) + max 17 script arguments
     ,enabled              => false
     ,comments             => 'Enables execution of Linux host scripts.'
    );

  sys.dbms_scheduler.define_program_argument
    (
      program_name         => 'OS_PROGRAM_PROG'
     ,argument_name        => 'P_PROGRAM_FILE'
     ,argument_position    => 1
     ,argument_type        => 'VARCHAR2'
     ,default_value        => ''
    );

  sys.dbms_scheduler.define_program_argument
    (
      program_name         => 'OS_PROGRAM_PROG'
     ,argument_name        => 'P_RETCODE_FILE'
     ,argument_position    => 2
     ,argument_type        => 'VARCHAR2'
     ,default_value        => ''
    );

  sys.dbms_scheduler.define_program_argument
    (
      program_name         => 'OS_PROGRAM_PROG'
     ,argument_name        => 'P_LOG_FILE'
     ,argument_position    => 3
     ,argument_type        => 'VARCHAR2'
     ,default_value        => ''
    );

  sys.dbms_scheduler.define_program_argument
    (
      program_name         => 'OS_PROGRAM_PROG'
     ,argument_name        => 'P_ATTRIBUTE1'
     ,argument_position    => 4
     ,argument_type        => 'VARCHAR2'
     ,default_value        => ''
    );

  sys.dbms_scheduler.define_program_argument
    (
      program_name         => 'OS_PROGRAM_PROG'
     ,argument_name        => 'P_ATTRIBUTE2'
     ,argument_position    => 5
     ,argument_type        => 'VARCHAR2'
     ,default_value        => ''
    );

  sys.dbms_scheduler.define_program_argument
    (
      program_name         => 'OS_PROGRAM_PROG'
     ,argument_name        => 'P_ATTRIBUTE3'
     ,argument_position    => 6
     ,argument_type        => 'VARCHAR2'
     ,default_value        => ''
    );

  sys.dbms_scheduler.define_program_argument
    (
      program_name         => 'OS_PROGRAM_PROG'
     ,argument_name        => 'P_ATTRIBUTE4'
     ,argument_position    => 7
     ,argument_type        => 'VARCHAR2'
     ,default_value        => ''
    );

  sys.dbms_scheduler.define_program_argument
    (
      program_name         => 'OS_PROGRAM_PROG'
     ,argument_name        => 'P_ATTRIBUTE5'
     ,argument_position    => 8
     ,argument_type        => 'VARCHAR2'
     ,default_value        => ''
    );

  sys.dbms_scheduler.define_program_argument
    (
      program_name         => 'OS_PROGRAM_PROG'
     ,argument_name        => 'P_ATTRIBUTE6'
     ,argument_position    => 9
     ,argument_type        => 'VARCHAR2'
     ,default_value        => ''
    );

  sys.dbms_scheduler.define_program_argument
    (
      program_name         => 'OS_PROGRAM_PROG'
     ,argument_name        => 'P_ATTRIBUTE7'
     ,argument_position    => 10
     ,argument_type        => 'VARCHAR2'
     ,default_value        => ''
    );

  sys.dbms_scheduler.define_program_argument
    (
      program_name         => 'OS_PROGRAM_PROG'
     ,argument_name        => 'P_ATTRIBUTE8'
     ,argument_position    => 11
     ,argument_type        => 'VARCHAR2'
     ,default_value        => ''
    );

  sys.dbms_scheduler.define_program_argument
    (
      program_name         => 'OS_PROGRAM_PROG'
     ,argument_name        => 'P_ATTRIBUTE9'
     ,argument_position    => 12
     ,argument_type        => 'VARCHAR2'
     ,default_value        => ''
    );

  sys.dbms_scheduler.define_program_argument
    (
      program_name         => 'OS_PROGRAM_PROG'
     ,argument_name        => 'P_ATTRIBUTE10'
     ,argument_position    => 13
     ,argument_type        => 'VARCHAR2'
     ,default_value        => ''
    );

  sys.dbms_scheduler.define_program_argument
    (
      program_name         => 'OS_PROGRAM_PROG'
     ,argument_name        => 'P_ATTRIBUTE11'
     ,argument_position    => 14
     ,argument_type        => 'VARCHAR2'
     ,default_value        => ''
    );

  sys.dbms_scheduler.define_program_argument
    (
      program_name         => 'OS_PROGRAM_PROG'
     ,argument_name        => 'P_ATTRIBUTE12'
     ,argument_position    => 15
     ,argument_type        => 'VARCHAR2'
     ,default_value        => ''
    );

  sys.dbms_scheduler.define_program_argument
    (
      program_name         => 'OS_PROGRAM_PROG'
     ,argument_name        => 'P_ATTRIBUTE13'
     ,argument_position    => 16
     ,argument_type        => 'VARCHAR2'
     ,default_value        => ''
    );

  sys.dbms_scheduler.define_program_argument
    (
      program_name         => 'OS_PROGRAM_PROG'
     ,argument_name        => 'P_ATTRIBUTE14'
     ,argument_position    => 17
     ,argument_type        => 'VARCHAR2'
     ,default_value        => ''
    );

  sys.dbms_scheduler.define_program_argument
    (
      program_name         => 'OS_PROGRAM_PROG'
     ,argument_name        => 'P_ATTRIBUTE15'
     ,argument_position    => 18
     ,argument_type        => 'VARCHAR2'
     ,default_value        => ''
    );

  sys.dbms_scheduler.define_program_argument
    (
      program_name         => 'OS_PROGRAM_PROG'
     ,argument_name        => 'P_ATTRIBUTE16'
     ,argument_position    => 19
     ,argument_type        => 'VARCHAR2'
     ,default_value        => ''
    );

  sys.dbms_scheduler.define_program_argument
    (
      program_name         => 'OS_PROGRAM_PROG'
     ,argument_name        => 'P_ATTRIBUTE17'
     ,argument_position    => 20
     ,argument_type        => 'VARCHAR2'
     ,default_value        => ''
    );

  sys.dbms_scheduler.enable
    (name                  => 'OS_PROGRAM_PROG');
end;
/