create table db_data_sync_config (
  id                  number generated always as identity primary key,
  enabled             varchar2(1)   default 'Y' not null,
  sort_order          number        default 0   not null,
  db_link             varchar2(128) not null,
  table_owner         varchar2(128) not null,
  remote_table_owner  varchar2(128),
  table_name          varchar2(128) not null,
  remote_table_name   varchar2(128),
  sync_actions        varchar2(100) not null,
  where_clause        varchar2(4000),
  last_import_date    date,
  log_select          varchar2(4000) not null,
  no_update_cols      varchar2(4000),
  after_insert_update varchar2(4000),
  after_update_update varchar2(4000),
  partial_data_where  varchar2(4000),
  post_proc_call      varchar2(4000),
  constraint db_data_sync_cfg_enabled_ck check (enabled in ('Y', 'N'))
)
/

comment on table  db_data_sync_config                     is 'Table sync definitions for DB_DATA_SYNC_PKG.';
comment on column db_data_sync_config.enabled             is 'Y = active, N = disabled.';
comment on column db_data_sync_config.sort_order          is 'Execution order for DB_DATA_SYNC_PKG.main.';
comment on column db_data_sync_config.db_link             is 'Database link to the source (remote) database.';
comment on column db_data_sync_config.table_owner         is 'Local table owner schema.';
comment on column db_data_sync_config.remote_table_owner  is 'Remote table owner schema. Defaults to table_owner when null.';
comment on column db_data_sync_config.table_name          is 'Local table name.';
comment on column db_data_sync_config.remote_table_name   is 'Remote table name. Defaults to table_name when null.';
comment on column db_data_sync_config.sync_actions        is 'Comma-separated actions: INSERT, UPDATE, DELETE.';
comment on column db_data_sync_config.where_clause        is 'Optional WHERE clause for changed records. Supports :LAST_IMPORT_DATE placeholder.';
comment on column db_data_sync_config.last_import_date    is 'Timestamp of the last successful sync run. Updated automatically by main.';
comment on column db_data_sync_config.log_select          is 'SQL expression evaluated against the synced row for logging.';
comment on column db_data_sync_config.no_update_cols      is 'Optional comma-separated list of columns to exclude from UPDATE.';
comment on column db_data_sync_config.after_insert_update is 'Optional SET clause executed on the local row after INSERT.';
comment on column db_data_sync_config.after_update_update is 'Optional SET clause executed on the local row after UPDATE.';
comment on column db_data_sync_config.partial_data_where  is 'Optional WHERE clause limiting sync to a subset of rows.';
comment on column db_data_sync_config.post_proc_call      is 'Optional single-line PL/SQL call run after each row change, e.g. my_pkg.after_sync(:rowid);';
