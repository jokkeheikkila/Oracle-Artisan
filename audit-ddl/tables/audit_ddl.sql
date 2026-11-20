create table audit_ddl
(
  changed_date       date,
  changed_timestamp  timestamp(6),
  owner              varchar2(30 char),
  object_type        varchar2(30 char),
  object_name        varchar2(128 char),
  sysevent           varchar2(30 char),
  privilege_names    audit_array,
  privilege_users    audit_array,
  sql_statement      clob,
  os_user            varchar2(255 char),
  db_user            varchar2(255 char),
  user_host          varchar2(255 char),
  user_terminal      varchar2(255 char),
  caller_owner       varchar2(2000 char),
  caller_name        varchar2(2000 char),
  caller_line_no     varchar2(2000 char),
  caller_type        varchar2(2000 char)
)
nested table privilege_names store as privilege_names_tab,
nested table privilege_users store as privilege_users_tab
/


create index audit_ddl_ind1 on audit_ddl (sysevent)
/


create index audit_ddl_ind2 on audit_ddl (object_name)
/


create index audit_ddl_ind3 on audit_ddl (trunc("CHANGED_DATE"))
/
