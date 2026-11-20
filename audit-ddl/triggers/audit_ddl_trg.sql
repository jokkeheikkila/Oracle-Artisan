-- Configure according to your system: schema that owns the AUDIT_DDL table and the AUDIT_ARRAY type
define audit_owner = <input_schema_name>

create or replace trigger sys.audit_ddl_trg
after ddl
on database
declare
/*****************************************************************
* Trigger Name:     audit_ddl_trg
*
* Description:
*   Adds DDL changes to audit log
*
* Ver    Author                Date             Comments
* 1.0    Jokke Heikkilä     28.05.2012        First version
******************************************************************/
  l_rec     &&audit_owner..audit_ddl%rowtype;
  user_list ora_name_list_t;
  priv_list ora_name_list_t;
  sql_list  ora_name_list_t;
  i         pls_integer;
begin
  -- only certain schemas and user changes (no temporary user objects or synonym compilations)
  -- Configure according to your system: schemas whose own DDL is audited
  if user not in ('SYS', upper('&&audit_owner.'))
  and nvl(ora_dict_obj_owner, '?') in (user, 'PUBLIC') then
    return;
  end if;

  -- user login
  if  ora_dict_obj_type = 'USER' and ora_sysevent = 'ALTER' then
    return;
  end if;

  -- no sys objects (except audit triggers); optionally add your DB export user here
  -- Configure according to your system: SYS objects to audit and users/schemas to exclude
  if nvl(ora_dict_obj_name, '?') not in ('AUDIT_DDL_TRG', 'AUDIT_DDL_DENIAL_TRG')
  and nvl(ora_dict_obj_owner, '?') = 'SYS'
  then
    return;
  end if;

  -- recycle bin
  if ora_dict_obj_name like 'BIN$%' then
    return;
  end if;

  -- comments
  if ora_sysevent = 'COMMENT' then
    return;
  end if;

  -- truncates
  if ora_sysevent = 'TRUNCATE' then
    return;
  end if;

  owa_util.who_called_me(l_rec.caller_owner, l_rec.caller_name, l_rec.caller_line_no, l_rec.caller_type);

  -- Optional: exclude scheduled/automated jobs or procedures (e.g. nightly grant/trigger scripts)
  -- if l_rec.caller_name = 'MY_NIGHTLY_GRANTS_PRC' then
  --   return;
  -- end if;

  -- if whole schema is compiled
  if l_rec.caller_name = 'DBMS_UTILITY' then
    return;
  end if;

  -- materialized view refresh
  if l_rec.caller_name = 'DBMS_SNAPSHOT' then
    return;
  end if;

  -- compression
  if l_rec.caller_name = 'PRVT_COMPRESSION' then
    return;
  end if;

  -- index rebuilds
  if ora_dict_obj_type = 'INDEX'
  and ora_sysevent = 'ALTER'
  and instr(l_rec.sql_statement, 'rebuild') > 0
  then
    return;
  end if;

  -- synonym compile
  if ora_dict_obj_type = 'SYNONYM'
  and ora_sysevent = 'ALTER'
  and instr(l_rec.sql_statement, 'compile') > 0
  then
    return;
  end if;

  -- sql statement
  i := sql_txt(sql_list);
  if sql_list is not empty then

    dbms_lob.createtemporary(l_rec.sql_statement, true, dbms_lob.call);

    for j in 1 .. sql_list.count loop
      dbms_lob.writeappend(l_rec.sql_statement, length(sql_list(j)), (sql_list(j)));
    end loop;

  end if;

  -- privileges
  l_rec.privilege_names := &&audit_owner..audit_array();
  l_rec.privilege_users := &&audit_owner..audit_array();

  i := ora_privilege_list(priv_list);
  if priv_list is not empty then
    for j in 1 .. priv_list.count loop
        l_rec.privilege_names.extend;
        l_rec.privilege_names(l_rec.privilege_names.last) := priv_list(j);
    end loop;

    case ora_sysevent
      when 'REVOKE' then
        i := revokee(user_list);
      when 'GRANT' then
        i := grantee(user_list);
    end case;

    -- users
    if user_list is not empty then
      for j in 1 .. user_list.count loop
        l_rec.privilege_users.extend;
        l_rec.privilege_users(l_rec.privilege_users.last) := user_list(j);
      end loop;
    end if;

  end if;

  -- APEX application user, if the DDL comes from an APEX session
  if user like 'APEX_%' then
    l_rec.db_user := sys_context('APEX$SESSION', 'APP_USER');
  end if;

  l_rec.db_user           := nvl(l_rec.db_user, user);
  l_rec.changed_date      := sysdate;
  l_rec.changed_timestamp := systimestamp;
  l_rec.owner             := ora_dict_obj_owner;
  l_rec.object_type       := ora_dict_obj_type;
  l_rec.object_name       := ora_dict_obj_name;
  l_rec.sysevent          := ora_sysevent;
  l_rec.os_user           := sys_context('USERENV', 'OS_USER');
  l_rec.user_host         := sys_context('USERENV', 'HOST');
  l_rec.user_terminal     := sys_context('USERENV', 'TERMINAL');

  insert into &&audit_owner..audit_ddl values l_rec;

exception when others then
  null; -- an audit error must never stop the DDL statement
end;
/
