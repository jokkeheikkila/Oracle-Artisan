create or replace package refcursor_utils_pkg as
/*****************************************************************
* Package Name: REFCURSOR_UTILS_PKG
*
* Description:
*   Utilities for sys_refcursor handling.
*
* Ver    Author                  Date             Comments
* 1.0    Jokke Heikkilä       18.01.2021        First version
******************************************************************/


  /*--------------------------------------------------------------*
  *  FUNCTION procedure_wrapper
  *  DESCRIPTION
  *    Takes dynamic procedure call with sys_refcursor as out parameter
  *    (e.g. p_sql => 'begin my_proc(:1); end;') and returns the cursor
  *    to the caller. Can be used in a SQL query.
  *    Runs in an autonomous transaction and commits.
  *---------------------------------------------------------------*/
  function procedure_wrapper(
    p_sql in varchar2
  ) return sys_refcursor;


  /*--------------------------------------------------------------*
  *  PROCEDURE cursor_to_table
  *  DESCRIPTION
  *    Inserts all rows of the cursor into the table. Only columns with the same name are used.
  *    Table name can be TABLE, SCHEMA.TABLE or a synonym.
  *    Supports VARCHAR2, CHAR, NUMBER and DATE columns only.
  *---------------------------------------------------------------*/
  procedure cursor_to_table(
    p_table_name in varchar2,
    p_cursor in sys_refcursor
  );


  /*--------------------------------------------------------------*
  *  PROCEDURE procedure_to_table
  *  DESCRIPTION
  *    Runs procedure_wrapper and cursor_to_table. Commits.
  *---------------------------------------------------------------*/
  procedure procedure_to_table(
    p_table_name in varchar2,
    p_sql        in varchar2
  );



end refcursor_utils_pkg;
/


create or replace package body refcursor_utils_pkg as

  /* Types ********************************************/
  type t_numbers is table of number;


  /* Forward declarations *****************************/
  function get_column_type(p_col_type in pls_integer) return varchar2;
  procedure resolve_table(p_table_name in varchar2, p_owner out varchar2, p_table out varchar2);
  function column_exists(p_owner in varchar2, p_table in varchar2, p_column in varchar2) return boolean;


  /* Public subprograms *******************************/
  function procedure_wrapper(
    p_sql in varchar2
  ) return sys_refcursor is
    l_cur sys_refcursor;

    pragma autonomous_transaction;
  begin
    execute immediate p_sql
    using out l_cur;

    commit;

    return l_cur;

  exception when others then
    rollback;
    raise;
  end procedure_wrapper;


  procedure cursor_to_table(
    p_table_name in varchar2,
    p_cursor     in sys_refcursor
  ) is
    l_cursor          sys_refcursor := p_cursor;
    l_cursor_number   number;
    l_columns         number;
    l_desc_tab        dbms_sql.desc_tab;
    l_text_var        varchar2(4000);
    l_num_var         number;
    l_date_var        date;
    l_column_name     varchar2(128);
    l_sql             varchar2(4000);
    l_sql_insert      varchar2(4000);
    l_q               varchar2(1) := '''';
    l_varchar_value   varchar2(4000);
    l_exclude_columns t_numbers;
    l_owner           varchar2(128);
    l_table           varchar2(128);
  begin
    savepoint ref_to_table_sp;

    -- find the real owner and name of the target table (also through a synonym)
    resolve_table(p_table_name, l_owner, l_table);

    --Convert cursor to DBMS_SQL cursor
    l_cursor_number := dbms_sql.to_cursor_number(rc => l_cursor);

    dbms_sql.describe_columns(l_cursor_number, l_columns, l_desc_tab);

    l_exclude_columns := t_numbers();

    for i in 1 .. l_desc_tab.count loop
      l_column_name := l_desc_tab(i).col_name;

      if column_exists(l_owner, l_table, l_column_name) then
        if l_sql is null then
          l_sql := 'insert into '||p_table_name||'(' || l_column_name;
        else
          l_sql := l_sql || ',' || l_column_name;
        end if;

        case get_column_type(l_desc_tab(i).col_type)
          when 'TEXT' then
            dbms_sql.define_column(l_cursor_number, i, l_text_var, l_desc_tab(i).col_max_len);
          when 'NUMBER' then
            dbms_sql.define_column(l_cursor_number, i, l_num_var);
          when 'DATE' then
            dbms_sql.define_column(l_cursor_number, i, l_date_var);
        end case;

      else
        l_exclude_columns.extend;
        l_exclude_columns(l_exclude_columns.last) := i;
      end if;
    end loop;

    if l_sql is null then
      return;
    end if;

    l_sql := l_sql || ') values (';

    while dbms_sql.fetch_rows(l_cursor_number) > 0 loop
      l_sql_insert := null;
      for i in 1 .. l_columns loop
        l_varchar_value := null;

        if i not member of l_exclude_columns then

          if l_sql_insert is not null then
            l_sql_insert := l_sql_insert || ',';
          end if;

          case get_column_type(l_desc_tab(i).col_type)
            when 'NUMBER' then
              dbms_sql.column_value(l_cursor_number, i, l_num_var);
              if l_num_var is not null then
                l_varchar_value := replace(to_char(l_num_var), ',', '.');
              end if;
            when 'TEXT' then
              dbms_sql.column_value(l_cursor_number, i, l_text_var);
              if l_text_var is not null then
                l_varchar_value := l_q || replace(l_text_var, '''', '''''') || l_q;
              end if;
            when 'DATE' then
              dbms_sql.column_value(l_cursor_number, i, l_date_var);
              if l_date_var is not null then
                l_varchar_value := 'TO_DATE('||l_q||to_char(l_date_var, 'DD.MM.YYYY HH24:MI:SS')||l_q||','||l_q||'DD.MM.YYYY HH24:MI:SS'||l_q||')';
              end if;
          end case;
          l_sql_insert := l_sql_insert || nvl(l_varchar_value, 'NULL');

        end if;
      end loop;

      l_sql_insert := l_sql || l_sql_insert || ')';

      execute immediate l_sql_insert;

    end loop;

  exception when others then
    -- Implement logging according to your system
    dbms_output.put_line('REFCURSOR_UTILS_PKG.cursor_to_table: '||sqlerrm);
    dbms_output.put_line(l_sql_insert);
    rollback to ref_to_table_sp;
    raise;
  end cursor_to_table;


  procedure procedure_to_table(
    p_table_name in varchar2,
    p_sql        in varchar2
  ) is
    l_cursor sys_refcursor;
  begin
    l_cursor := procedure_wrapper(p_sql);

    cursor_to_table(p_table_name, l_cursor);

    commit;

  end procedure_to_table;


  /* Private subprograms  *****************************/
  function get_column_type(
    p_col_type in pls_integer
  ) return varchar2 is
    l_type varchar2(20);
  begin
     if p_col_type in (1, 9, 96) then -- varchar, varchar2, char
       l_type := 'TEXT';
     elsif p_col_type = 2 then        -- number
       l_type := 'NUMBER';
     elsif p_col_type = 12 then       -- date
       l_type := 'DATE';
     else
       raise_application_error(-20100, 'Cannot recognize col_type '||to_char(p_col_type));
     end if;

     return l_type;

  end get_column_type;


  procedure resolve_table(
    p_table_name in  varchar2,
    p_owner      out varchar2,
    p_table      out varchar2
  ) is
    l_part2         varchar2(128);
    l_dblink        varchar2(128);
    l_part1_type    number;
    l_object_number number;
  begin
    -- resolves TABLE, SCHEMA.TABLE and synonyms in the same way as the insert statement does
    dbms_utility.name_resolve(
      name          => p_table_name,
      context       => 0, -- table or view
      schema        => p_owner,
      part1         => p_table,
      part2         => l_part2,
      dblink        => l_dblink,
      part1_type    => l_part1_type,
      object_number => l_object_number
    );

  end resolve_table;


  function column_exists(
    p_owner  in varchar2,
    p_table  in varchar2,
    p_column in varchar2
  ) return boolean is
    l_count number;
  begin
    select count(1)
      into l_count
      from all_tab_cols
     where owner       = p_owner
       and table_name  = p_table
       and column_name = p_column;

    if l_count = 0 then
      return false;
    else
      return true;
    end if;

  end column_exists;

end refcursor_utils_pkg;
/
