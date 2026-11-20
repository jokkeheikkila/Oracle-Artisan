create or replace package db_data_sync_pkg as
/*****************************************************************
* Package Name: DB_DATA_SYNC_PKG
*
* Description: Copies table data from a remote database to the local one.
*
*   Needs:
*   - table DB_DATA_SYNC_CONFIG (tables/db_data_sync_config.sql)
*
* Ver    Author                  Date             Comments
* 1.0    Jokke Heikkilä       26.09.2023        First version
******************************************************************/

  g_debug boolean := false; -- prints generated SQL to dbms_output

  type varchar2_array is table of varchar2(32767);

  -- runs all sync definitions
  procedure main;
  
  procedure copy_table_data(
    p_db                  in varchar2,                    -- DB link to the source (remote) database
    p_owner               in varchar2,                    -- table owner schema
    p_remote_owner        in varchar2,                    -- remote DB table owner
    p_table               in varchar2,                    -- table name
    p_remote_table        in varchar2,                    -- remote DB table name
    p_sync_actions        in varchar2,                    -- list of actions: update=updates changed records, insert=adds records missing from local side, delete=removes records missing from remote side
    p_where               in varchar2,                    -- where clause for getting only changed data
    p_log_select          in varchar2,                    -- select statement for logging copied data
    p_after_insert_update in varchar2 default null,       -- common update sql which needs to be done after insert
    p_after_update_update in varchar2 default null,       -- common update sql which needs to be done after update
    p_no_update_cols      in varchar2_array default null, -- which columns should be ignored in update
    p_partial_data_where  in varchar2 default null,       -- partial data selection where clause. only this data is synced in this table
    p_post_proc_call      in varchar2 default null        -- e.g. my_pkg.after_sync(:rowid);  one line, must contain :rowid and end with ;
  );

  function get_partial_data_rowids(
    p_sync_owner in varchar2,
    p_sync_table in varchar2,
    p_owner      in varchar2 default null,
    p_table      in varchar2 default null
  ) return varchar2_array;

  function is_member_of_partial_data(
    p_owner              in varchar2,
    p_table              in varchar2,
    p_rowid              in rowid,
    p_partial_data_where in varchar2
  ) return varchar2; -- true/false

end db_data_sync_pkg;
/

create or replace package body db_data_sync_pkg as

  /* Types ********************************************/
  type rowids_type is table of rowid;


  /* Forward declarations *****************************/
  procedure do_debug(
    p_log in clob
  );

  procedure log_info(
    p_text in varchar2
  );

  procedure log_error(
    p_text in varchar2
  );

  function split_string(
    p_value    in varchar2,
    p_sep_char in varchar2 default ','
  ) return varchar2_array;

  function get_log_text(
    p_owner      in varchar2,
    p_table      in varchar2,
    p_rowid      in rowid,
    p_log_select in varchar2
  ) return varchar2;

  procedure do_logging(
    p_rowid    in rowid,
    p_log_text in varchar2
  );

  function get_local_rowid(
    p_db           in varchar2,
    p_owner        in varchar2,
    p_remote_owner in varchar2,
    p_table        in varchar2,
    p_remote_table in varchar2,
    p_remote_rowid in rowid
  ) return rowid;

  function get_changed_records_sql(
    p_db           in varchar2,
    p_owner        in varchar2,
    p_remote_owner in varchar2,
    p_table        in varchar2,
    p_remote_table in varchar2,
    p_where        in varchar2
  ) return clob;

  function get_missing_local_records_sql(
    p_db           in varchar2,
    p_owner        in varchar2,
    p_remote_owner in varchar2,
    p_table        in varchar2,
    p_remote_table in varchar2,
    p_where        in varchar2
  ) return clob;

  function get_removed_local_records_sql(
    p_db           in varchar2,
    p_owner        in varchar2,
    p_remote_owner in varchar2,
    p_table        in varchar2,
    p_remote_table in varchar2,
    p_where        in varchar2
  ) return clob;

  function get_insert_from_remote_sql(
    p_db           in varchar2,
    p_owner        in varchar2,
    p_remote_owner in varchar2,
    p_table        in varchar2,
    p_remote_table in varchar2
  ) return clob;

  function get_update_from_remote_sql(
    p_db              in varchar2,
    p_owner           in varchar2,
    p_remote_owner    in varchar2,
    p_table           in varchar2,
    p_remote_table    in varchar2,
    p_exclude_columns in varchar2_array default null
  ) return clob;

  function get_update_local_sql(
    p_owner         in varchar2,
    p_table         in varchar2,
    p_update_clause in varchar2
  ) return clob;

  function get_delete_local_sql(
    p_owner in varchar2,
    p_table in varchar2
  ) return clob;

  function get_primary_key_columns_where(
    p_owner in varchar2,
    p_table in varchar2
  ) return clob;

  function get_column_list(
    p_owner           in varchar2,
    p_table           in varchar2,
    p_include_pk      in varchar2,
    p_exclude_columns in varchar2_array default null
  ) return clob;

  function get_post_proc_call_sql(
    p_post_proc_call in varchar2
  ) return varchar2;


  /* Public subprograms *******************************/
  procedure main is
    l_sysdate            date;
    l_date_mask          varchar2(30) := 'YYYY-MM-DD HH24:MI:SS';
    l_db_link            varchar2(128);
    l_table_owner        varchar2(128);
    l_remote_table_owner varchar2(128);
    l_table_name         varchar2(128);
    l_remote_table_name  varchar2(128);
    l_failed_count       pls_integer := 0;

    cursor sync_definitions_cur is
    select id,
           db_link,
           upper(table_owner)                     table_owner,
           upper(nvl(remote_table_owner, table_owner))
                                                  remote_table_owner,
           upper(table_name)                      table_name,
           upper(nvl(remote_table_name, table_name))
                                                  remote_table_name,
           replace(
             where_clause,
             ':LAST_IMPORT_DATE',
             'to_date('''||to_char(nvl(last_import_date, date '1000-01-01'), l_date_mask)||''', '''||l_date_mask||''')'
           )                                      where_clause,
           log_select,
           upper(no_update_cols)                  no_update_cols,
           after_insert_update,
           after_update_update,
           upper(sync_actions)                    sync_actions,
           partial_data_where,
           post_proc_call
      from db_data_sync_config
     where enabled = 'Y'
     order by sort_order, id;
  begin
    log_info('Start DB data sync');

    l_sysdate := sysdate;
    for i in sync_definitions_cur loop
      begin
        l_db_link            := dbms_assert.qualified_sql_name(i.db_link);
        l_table_owner        := dbms_assert.schema_name(i.table_owner);
        l_remote_table_owner := dbms_assert.qualified_sql_name(i.remote_table_owner);
        l_table_name         := dbms_assert.qualified_sql_name(i.table_name);
        l_remote_table_name  := dbms_assert.qualified_sql_name(i.remote_table_name);

        copy_table_data(
          p_db                  => l_db_link,
          p_owner               => l_table_owner,
          p_remote_owner        => l_remote_table_owner,
          p_table               => l_table_name,
          p_remote_table        => l_remote_table_name,
          p_where               => i.where_clause,
          p_sync_actions        => i.sync_actions,
          p_log_select          => i.log_select,
          p_after_insert_update => i.after_insert_update,
          p_after_update_update => i.after_update_update,
          p_no_update_cols      => split_string(i.no_update_cols),
          p_partial_data_where  => i.partial_data_where,
          p_post_proc_call      => i.post_proc_call
        );

        update db_data_sync_config
           set last_import_date = l_sysdate
         where id = i.id;

        commit;
      exception when others then
        -- one failed table does not stop the other tables
        rollback;
        log_error(i.db_link || ' ' || i.table_owner || '.' || i.table_name || ': ' || sqlerrm);
        l_failed_count := l_failed_count + 1;
      end;
    end loop;

    log_info('End DB data sync');

    if l_failed_count > 0 then
      raise_application_error(-20000, 'DB data sync failed for '||l_failed_count||' table(s), see dbms_output');
    end if;

  exception when others then
    rollback;
    log_error(sqlerrm);
    raise;
  end main;


  procedure copy_table_data(
    p_db                  in varchar2,
    p_owner               in varchar2,
    p_remote_owner        in varchar2,
    p_table               in varchar2,
    p_remote_table        in varchar2,
    p_sync_actions        in varchar2,
    p_where               in varchar2,
    p_log_select          in varchar2,
    p_after_insert_update in varchar2 default null,
    p_after_update_update in varchar2 default null,
    p_no_update_cols      in varchar2_array default null,
    p_partial_data_where  in varchar2 default null,
    p_post_proc_call      in varchar2 default null
  ) is
    l_recs        rowids_type;
    l_sql         clob;
    l_local_rowid rowid;
    l_actions     varchar2_array := split_string(p_sync_actions);
    l_log_text    varchar2(2000);
  begin
    log_info('Start table copy: '||p_db||' '||p_owner||'.'||p_table||' '||p_sync_actions||' '||case when p_partial_data_where is not null then 'PARTIAL' else 'FULL' end);

    ----------------------------------------------------------------------------
    if 'UPDATE' member of l_actions then
      l_sql := get_changed_records_sql(p_db, p_owner, p_remote_owner, p_table, p_remote_table, p_where);
      do_debug(l_sql);
      execute immediate l_sql
      bulk collect into l_recs;

      if l_recs is not empty then
        for i in 1..l_recs.count loop
          log_info('Remote record found: '||rowidtochar(l_recs(i)));

          l_local_rowid := get_local_rowid(p_db, p_owner, p_remote_owner, p_table, p_remote_table, l_recs(i));

          if l_local_rowid is not null then -- should not need this check
            l_sql := get_update_from_remote_sql(p_db, p_owner, p_remote_owner, p_table, p_remote_table, p_no_update_cols);
            do_debug(l_sql);
            execute immediate l_sql
            using in l_recs(i), in l_local_rowid;

            -- post updates
            if p_after_update_update is not null then
              l_sql := get_update_local_sql(p_owner, p_table, p_after_update_update);
              do_debug(l_sql);
              execute immediate l_sql
              using in l_local_rowid;
            end if;

            -- post procedure call if something else still needed
            if p_post_proc_call is not null then
              l_sql := get_post_proc_call_sql(p_post_proc_call);
              do_debug(l_sql);
              execute immediate l_sql
              using in l_local_rowid;
            end if;

            do_logging(l_local_rowid, get_log_text(p_owner, p_table, l_local_rowid, '''Updated: ''||'||p_log_select));
          end if;
        end loop;
      end if;
    end if;
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    if 'INSERT' member of l_actions then
      l_sql := get_missing_local_records_sql(p_db, p_owner, p_remote_owner, p_table, p_remote_table, p_partial_data_where);
      do_debug(l_sql);
      execute immediate l_sql
      bulk collect into l_recs;

      if l_recs is not empty then
        for i in 1..l_recs.count loop
          log_info('Remote record found: '||rowidtochar(l_recs(i)));

          l_sql := get_insert_from_remote_sql(p_db, p_owner, p_remote_owner, p_table, p_remote_table);
          do_debug(l_sql);
          execute immediate l_sql
          using in l_recs(i);

          -- select rowid from newly added record
          l_local_rowid := get_local_rowid(p_db, p_owner, p_remote_owner, p_table, p_remote_table, l_recs(i));

          -- post updates
          if p_after_insert_update is not null then
            l_sql := get_update_local_sql(p_owner, p_table, p_after_insert_update);
            do_debug(l_sql);
            execute immediate l_sql
            using in l_local_rowid;
          end if;

          -- post procedure call if something else still needed
          if p_post_proc_call is not null then
            l_sql := get_post_proc_call_sql(p_post_proc_call);
            do_debug(l_sql);
            execute immediate l_sql
            using in l_local_rowid;
          end if;

          do_logging(l_local_rowid, get_log_text(p_owner, p_table, l_local_rowid, '''Added: ''||'||p_log_select));

        end loop;
      end if;
    end if;
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    if 'DELETE' member of l_actions then
      l_recs.delete;
      l_sql := get_removed_local_records_sql(p_db, p_owner, p_remote_owner, p_table, p_remote_table, p_partial_data_where);
      do_debug(l_sql);
      execute immediate l_sql
      bulk collect into l_recs;

      if l_recs is not empty then
        for i in 1..l_recs.count loop
          l_log_text := get_log_text(p_owner, p_table, l_recs(i), '''Deleted: ''||'||p_log_select);

          -- DELETE
          l_sql := get_delete_local_sql(p_owner, p_table);
          do_debug(l_sql);
          execute immediate l_sql
          using in l_recs(i);

          -- post procedure call if something else still needed
          if p_post_proc_call is not null then
            l_sql := get_post_proc_call_sql(p_post_proc_call);
            do_debug(l_sql);
            execute immediate l_sql
            using in l_recs(i);
          end if;

          do_logging(l_recs(i), l_log_text);

        end loop;
      end if;
    end if;
    ----------------------------------------------------------------------------

  end copy_table_data;


  function get_partial_data_rowids(
    p_sync_owner in varchar2,
    p_sync_table in varchar2,
    p_owner      in varchar2 default null,
    p_table      in varchar2 default null
  ) return varchar2_array is
    l_sql           clob;
    l_arr           varchar2_array := varchar2_array();
    l_partial_where db_data_sync_config.partial_data_where%type;
  begin
    begin
      select distinct partial_data_where
        into l_partial_where
        from db_data_sync_config
       where enabled            = 'Y'
         and upper(table_owner) = upper(p_sync_owner)
         and upper(table_name)  = upper(p_sync_table);
    exception when no_data_found then
      null;
    end;

    if l_partial_where is not null then
      l_sql := 'select ROWIDTOCHAR(rowid) from '||nvl(p_owner, p_sync_owner)||'.'||nvl(p_table, p_sync_table)||' where '||l_partial_where;
      do_debug(l_sql);
      execute immediate l_sql
      bulk collect into l_arr;
    end if;

    return l_arr;

  end get_partial_data_rowids;


  function is_member_of_partial_data(
    p_owner              in varchar2,
    p_table              in varchar2,
    p_rowid              in rowid,
    p_partial_data_where in varchar2
  ) return varchar2 is
    l_count pls_integer;
    l_sql   clob;
  begin
    l_sql := 'select count(1) from '||p_owner||'.'||p_table||' where '||p_partial_data_where||' and rowid = :1';
    do_debug(l_sql);
    execute immediate l_sql
    into l_count
    using p_rowid;

    return case when l_count > 0 then 'true' else 'false' end;

  end is_member_of_partial_data;


  /* Private subprograms  *****************************/
  procedure do_debug(p_log in clob) is
    l_offset pls_integer := 1;
  begin
    if g_debug then
      loop
        exit when l_offset > nvl(dbms_lob.getlength(p_log), 0);
        dbms_output.put(dbms_lob.substr(p_log, 255, l_offset));
        l_offset := l_offset + 255;
      end loop;
      dbms_output.new_line;
    end if;

    -- Implement debugging according to your system
  end do_debug;


  procedure log_info(p_text in varchar2) is
  begin
    dbms_output.put_line('DB_DATA_SYNC_PKG: ' || p_text);

    -- Implement logging according to your system
  end log_info;


  procedure log_error(p_text in varchar2) is
  begin
    dbms_output.put_line('DB_DATA_SYNC_PKG ERROR: ' || p_text);

    -- Implement logging according to your system
  end log_error;


  function split_string(
    p_value    in varchar2,
    p_sep_char in varchar2 default ','
  ) return varchar2_array is
    l_array varchar2_array  := varchar2_array();
    l_str   varchar2(32767) := p_value;
    l_pos   pls_integer;
    l_sep_l pls_integer     := length(p_sep_char);
  begin
    if p_value is not null then
      loop
        l_pos := instr(l_str, p_sep_char);
        exit when nvl(l_pos, 0) = 0;
        l_array.extend;
        l_array(l_array.last) := substr(l_str, 1, l_pos-1);
        l_str := substr(l_str, l_pos+l_sep_l);
      end loop;
      l_array.extend;
      l_array(l_array.last) := l_str;
    end if;

    return l_array;
  end split_string;


  function get_log_text(
    p_owner      in varchar2,
    p_table      in varchar2,
    p_rowid      in rowid,
    p_log_select in varchar2
  ) return varchar2 is
    l_sql       clob;
    l_log_entry varchar2(400);
  begin
    l_sql := 'select '||p_log_select||' from '||p_owner||'.'||p_table||' where rowid = :1';
    do_debug(l_sql);
    execute immediate l_sql
    into l_log_entry
    using p_rowid;

    return l_log_entry;

  end get_log_text;


  procedure do_logging(
    p_rowid    in rowid,
    p_log_text in varchar2
  ) is
  begin
    log_info(p_log_text||' ('||rowidtochar(p_rowid)||')');

  end do_logging;


  function get_local_rowid(
    p_db           in varchar2,
    p_owner        in varchar2,
    p_remote_owner in varchar2,
    p_table        in varchar2,
    p_remote_table in varchar2,
    p_remote_rowid in rowid
  ) return rowid is
    l_sql         clob;
    l_local_rowid rowid;
  begin
    l_sql :=
      'select rowid
         from '||p_owner||'.'||p_table||' local_table
        where exists (
          select 1
            from '||p_remote_owner||'.'||p_remote_table||'@'||p_db||' remote_table
           where remote_table.rowid = :1';

    l_sql := l_sql || get_primary_key_columns_where(p_owner, p_table);

    l_sql := l_sql ||')';

    do_debug(l_sql);
    begin
      execute immediate l_sql
      into l_local_rowid
      using p_remote_rowid;
    exception when no_data_found then
      null;
    end;

    return l_local_rowid;

  end get_local_rowid;


  function get_changed_records_sql(
    p_db           in varchar2,
    p_owner        in varchar2,
    p_remote_owner in varchar2,
    p_table        in varchar2,
    p_remote_table in varchar2,
    p_where        in varchar2
  ) return clob is
    l_sql clob;
  begin
    l_sql := 'select rowid
                from '||p_remote_owner||'.'||p_remote_table||'@'||p_db||' remote_table
               where exists (
                 select 1
                   from '||p_owner||'.'||p_table||' local_table
                  where 1 = 1 ';

    l_sql := l_sql || get_primary_key_columns_where(p_owner, p_table) || ')';

    if p_where is not null then
      l_sql := l_sql || ' and ' || p_where;
    end if;

    return l_sql;
  end get_changed_records_sql;


  function get_missing_local_records_sql(
    p_db           in varchar2,
    p_owner        in varchar2,
    p_remote_owner in varchar2,
    p_table        in varchar2,
    p_remote_table in varchar2,
    p_where        in varchar2
  ) return clob is
    l_sql clob;
  begin
    l_sql := 'select rowid
                from '||p_remote_owner||'.'||p_remote_table||'@'||p_db||' remote_table
               where not exists (
                 select 1
                   from '||p_owner||'.'||p_table||' local_table
                  where 1 = 1 ';

    l_sql := l_sql || get_primary_key_columns_where(p_owner, p_table);

    if p_where is not null then
      l_sql := l_sql || ' and ' || p_where;
    end if;

    l_sql := l_sql ||')';

    if p_where is not null then
      l_sql := l_sql || ' and ' || p_where;
    end if;

    return l_sql;
  end get_missing_local_records_sql;


  function get_removed_local_records_sql(
    p_db           in varchar2,
    p_owner        in varchar2,
    p_remote_owner in varchar2,
    p_table        in varchar2,
    p_remote_table in varchar2,
    p_where        in varchar2
  ) return clob is
    l_sql clob;
  begin
    l_sql := 'select rowid from '||p_owner||'.'||p_table||' local_table
              where not exists (
                select 1
                  from '||p_remote_owner||'.'||p_remote_table||'@'||p_db||' remote_table
                 where 1 = 1 ';

    l_sql := l_sql || get_primary_key_columns_where(p_owner, p_table);

    if p_where is not null then
      l_sql := l_sql || ' and ' || p_where;
    end if;

    l_sql := l_sql ||')';

    if p_where is not null then
      l_sql := l_sql || ' and ' || p_where;
    end if;

    return l_sql;
  end get_removed_local_records_sql;


  function get_insert_from_remote_sql(
    p_db           in varchar2,
    p_owner        in varchar2,
    p_remote_owner in varchar2,
    p_table        in varchar2,
    p_remote_table in varchar2
  ) return clob is
    l_sql  clob;
    l_cols clob := get_column_list(p_owner, p_table, 'TRUE');
  begin
    l_sql := 'insert into '||p_owner||'.'||p_table||'('||l_cols||')
              select '||l_cols||'
               from '||p_remote_owner||'.'||p_remote_table||'@'||p_db||' where rowid = :1';

    return l_sql;
  end get_insert_from_remote_sql;


  function get_update_from_remote_sql(
    p_db              in varchar2,
    p_owner           in varchar2,
    p_remote_owner    in varchar2,
    p_table           in varchar2,
    p_remote_table    in varchar2,
    p_exclude_columns in varchar2_array default null
  ) return clob is
    l_sql  clob;
    l_cols clob := get_column_list(p_owner, p_table, 'FALSE', p_exclude_columns);
  begin
    l_sql := 'update '||p_owner||'.'||p_table||
             ' set ('||l_cols ||') = (select '||l_cols||' from '||p_remote_owner||'.'||p_remote_table||'@'||p_db||' where rowid = :1)'||
             ' where rowid = :2';

    return l_sql;
  end get_update_from_remote_sql;


  function get_update_local_sql(
    p_owner         in varchar2,
    p_table         in varchar2,
    p_update_clause in varchar2
  ) return clob is
    l_sql clob;
  begin
    l_sql := 'update '||p_owner||'.'||p_table||
             ' set '||p_update_clause||
             ' where rowid = :1';

    return l_sql;
  end get_update_local_sql;


  function get_delete_local_sql(
    p_owner in varchar2,
    p_table in varchar2
  ) return clob is
    l_sql clob;
  begin
    l_sql := 'delete from '||p_owner||'.'||p_table||
             ' where rowid = :1';

    return l_sql;
  end get_delete_local_sql;


  function get_primary_key_columns_where(
    p_owner in varchar2,
    p_table in varchar2
  ) return clob is
    l_sql clob;
  begin
    for i in (
      select ac.column_name
        from all_cons_columns ac,
             all_constraints uc
       where ac.constraint_name = uc.constraint_name
         and ac.owner           = uc.owner
         and ac.table_name      = uc.table_name
         and uc.constraint_type = 'P'
         and uc.table_name      = p_table
         and uc.owner           = p_owner
       order by ac.position
    ) loop
      l_sql := l_sql || ' and remote_table.'||i.column_name||' = local_table.'||i.column_name;
    end loop;

    return l_sql;
  end get_primary_key_columns_where;

  function get_column_list(
    p_owner           in varchar2,
    p_table           in varchar2,
    p_include_pk      in varchar2,
    p_exclude_columns in varchar2_array default null
  ) return clob is
    l_list clob;
  begin
    for i in (
      select column_name
        from all_tab_cols atc
       where atc.owner          = p_owner
         and atc.table_name     = p_table
         and atc.virtual_column = 'NO'
         and (p_include_pk = 'TRUE'
            or atc.column_name not in (
           select ac.column_name
             from all_cons_columns ac,
                  all_constraints uc
            where ac.constraint_name = uc.constraint_name
              and ac.owner           = uc.owner
              and ac.table_name      = uc.table_name
              and uc.constraint_type = 'P'
              and uc.table_name      = atc.table_name
              and uc.owner           = atc.owner
          )
         )
      order by column_id
    ) loop
      if p_exclude_columns is not null
      and i.column_name member of p_exclude_columns then
        continue;
      end if;

      if l_list is not null then
        l_list := l_list || ',';
      end if;

      l_list := l_list || i.column_name;
    end loop;

    return l_list;
  end get_column_list;


  function get_post_proc_call_sql(
    p_post_proc_call in varchar2
  ) return varchar2 is
  begin
    if instr(p_post_proc_call, ';') <> length(p_post_proc_call)
    or instr(p_post_proc_call, ':rowid') = 0
    or instr(p_post_proc_call, chr(10)) > 0
    or instr(p_post_proc_call, chr(13)) > 0
    then
      raise program_error;
    end if;

    return 'begin '||p_post_proc_call||' end;';
  end get_post_proc_call_sql;


end db_data_sync_pkg;
/
