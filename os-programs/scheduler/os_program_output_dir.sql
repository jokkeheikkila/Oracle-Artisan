-- Configure according to your system: full path of the "output" folder under the folder of host/run.sh
create or replace directory
os_program_output_dir as
'/path/to/scheduler/output'
/


-- Configure according to your system: grant to the schema that owns OS_PROGRAMS_PKG
-- GRANT READ, WRITE ON DIRECTORY OS_PROGRAM_OUTPUT_DIR TO <package owner>
-- /
