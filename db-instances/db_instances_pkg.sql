create or replace package db_instances_pkg authid current_user as
/*****************************************************************
* Package Name: DB_INSTANCES_PKG
*
* Description:  Queries over several databases through DB links
*
* Ver    Author                  Date             Comments
* 1.0    Jokke Heikkilä       21.04.2011        First version
******************************************************************/

  type instance_type is record (
    db_link varchar2(128),
    db_name varchar2(128)
  );
  type instance_types is table of instance_type;

  type process_type is record (
    db_link    varchar2(128),
    machine    varchar2(64),
    program    varchar2(84),
    sid        number,
    spid       varchar2(24),
    pid        varchar2(24),
    username   varchar2(128),
    logon_time date,
    module     varchar2(64)
  );
  type processes_type is table of process_type;

  -- returns the name of each database behind the DB links
  function get_list return instance_types pipelined;

  -- returns user sessions of all databases
  function list_processes return processes_type pipelined;

  -- write @DB_LINK@ after each remote table name, e.g. select * from dual@DB_LINK@.
  -- The query is run once for each DB link.
  function run_query(
    p_query in varchar2
  ) return sys_refcursor;

  -- write @DB_LINK@ after each remote table name, e.g. select * from dual@DB_LINK@.
  -- The query is run once for each DB link.
  function run_query_xml(
    p_query in varchar2
  ) return xmltype;

end db_instances_pkg;
/

create or replace package body db_instances_pkg as

  -- Customize this cursor according to your system if you want to filter which DB links are queried
  cursor database_links_cursor is
  select db_link
    from user_db_links;


  function get_list return instance_types pipelined is

    l_instance_type instance_type;

    unknown_db_exception exception;
    pragma exception_init(unknown_db_exception, -12514);
  begin
    for i in database_links_cursor loop
      l_instance_type.db_link := i.db_link;

      begin
        execute immediate
          'SELECT ora_database_name@' || l_instance_type.db_link || '
           FROM DUAL'
        into l_instance_type.db_name;

        pipe row(l_instance_type);

      exception when unknown_db_exception then
        null;
      end;
    end loop;
  end get_list;


 function list_processes return processes_type pipelined is

    l_rows processes_type;
    l_sql  varchar2(32767);

    unknown_db_exception exception;
    pragma exception_init(unknown_db_exception, -12514);
  begin
    for i in database_links_cursor loop

      begin
          l_sql :=
          'SELECT :1 db_link,
                  s.machine,
                  s.program,
                  s.sid,
                  p.spid,
                  substr(s.process, 1, instr(s.process, '':'') - 1) pid,
                  s.username,
                  s.logon_time,
                  s.module
             FROM gv$process@'||i.db_link||' p, gv$session@'||i.db_link||' s
            WHERE p.addr = s.paddr
              AND s.type <> ''BACKGROUND''';

        execute immediate l_sql
        bulk collect into l_rows
        using i.db_link;

        if l_rows is not empty then
          for i in 1 .. l_rows.count loop
            pipe row(l_rows(i));
          end loop;
        end if;

      exception when no_data_found or unknown_db_exception then
        null;
      when others then
        -- one unreachable database does not stop the list
        dbms_output.put_line('DB_INSTANCES_PKG: ' || i.db_link || ': ' || sqlerrm);
      end;

    end loop;

  end list_processes;


  function run_query(
    p_query in varchar2
  )
  return sys_refcursor is
    l_refcur sys_refcursor;
    l_temp   clob;
    l_q      varchar2(1) := '''';
    l_found  boolean := false;
  begin
    for i in database_links_cursor loop
      l_found := true;

      if l_temp is not null then
        l_temp := l_temp || ' union all ';
      end if;

      l_temp := l_temp || 'select '||l_q||i.db_link||l_q||' DB, qry.* from ('||replace(p_query, 'DB_LINK@', i.db_link)||') qry';
    end loop;

    if not l_found then
      l_temp := 'select null from dual';
    end if;

    open l_refcur for l_temp;

    return l_refcur;

  end run_query;


  function run_query_xml(
    p_query in varchar2
  ) return xmltype is
  begin
    return xmltype(run_query(p_query));
  end run_query_xml;


end db_instances_pkg;
/
