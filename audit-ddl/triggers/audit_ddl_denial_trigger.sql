-- Configure according to your system: schema that owns the AUDIT_DDL table
define audit_owner = <input_schema_name>

create or replace trigger sys.audit_ddl_denial_trg
before delete or update
on &&audit_owner..audit_ddl
referencing new as new old as old
for each row
declare
/*****************************************************************
* Trigger Name:     audit_ddl_denial_trg
*
* Description:
*   Prevents data updation or deletion on DDL audit table
*
* Ver    Author                Date             Comments
* 1.0    Jokke Heikkilä     03.12.2014        First version
******************************************************************/
begin

  if user <> 'SYS' then
    raise program_error;
  end if;

end audit_ddl_denial_trg;
/
