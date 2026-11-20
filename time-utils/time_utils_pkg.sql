create or replace package time_utils_pkg as
/*****************************************************************
* Package Name: TIME_UTILS_PKG
*
* Description:
*   Utilities for time handling
*
* Ver    Author                  Date             Comments
* 1.0    Jokke Heikkilä       18.02.2016        First version
******************************************************************/

  function minutes_to_time(p_minutes in number) return varchar2; -- e.g. 90 -> '1:30'

  function hours_to_time(p_hours in number) return varchar2; -- e.g. 1.5 -> '1:30'

  function dates_overlapping(p_start in date, p_end in date, p_start2 in date, p_end2 in date) return varchar2; -- 'TRUE' if the two periods overlap, else 'FALSE'

  function timestamp_to_date(p_timestamp in timestamp with time zone) return date; -- returns the timestamp as date in the session time zone

  function get_server_time_zone return varchar2 result_cache;

  function get_local_time_zone return varchar2 result_cache;

  function convert_to_another_time_zone(
    p_source_date      in date,
    p_source_time_zone in varchar2 default get_server_time_zone(),
    p_target_time_zone in varchar2 default get_local_time_zone()
  ) return date;

  function sysdate_local return date; -- SYSDATE in the local time zone

end time_utils_pkg;
/

create or replace package body time_utils_pkg as

  /* Public subprograms *******************************/

  function minutes_to_time(
    p_minutes in number
  ) return varchar2 is
    l_time varchar2(12);
  begin
    select to_char(floor(p_minutes/60))||':'||to_char(mod(p_minutes, 60)
           , 'FM00')
      into l_time
      from dual;

    return l_time;

  end minutes_to_time;


  function hours_to_time(p_hours in number) return varchar2 is
  begin
    return minutes_to_time(p_hours * 60);

  end hours_to_time;


  function dates_overlapping(
    p_start  in date,
    p_end    in date,
    p_start2 in date,
    p_end2   in date
  ) return varchar2 is
    l_dummy pls_integer;
  begin

    select 1
      into l_dummy
      from dual
     where (p_start, p_end) overlaps (p_start2, p_end2);

    return 'TRUE';

  exception when no_data_found then
    return 'FALSE';

  end dates_overlapping;


  function timestamp_to_date(
    p_timestamp in timestamp with time zone
  ) return date is
  begin
    return cast(p_timestamp at local as date);
  end timestamp_to_date;


  function get_server_time_zone
  return varchar2 result_cache is
  begin
    -- Configure according to your system: time zone of the DB server OS (the time zone of SYSDATE), e.g. 'Europe/Helsinki'
    return 'UTC';
  end get_server_time_zone;


  function get_local_time_zone
  return varchar2 result_cache is
  begin
    -- Configure according to your system: local time zone of the users, e.g. 'Europe/Stockholm'
    return 'UTC';
  end get_local_time_zone;


  function convert_to_another_time_zone(
    p_source_date      in date,
    p_source_time_zone in varchar2 default get_server_time_zone(),
    p_target_time_zone in varchar2 default get_local_time_zone()
  ) return date is
  begin
    return
      cast(
        from_tz(
          cast(p_source_date as timestamp),
          p_source_time_zone
        ) at time zone p_target_time_zone as date
      );

  end convert_to_another_time_zone;


  function sysdate_local
  return date is
  begin
    return convert_to_another_time_zone(sysdate);
  end sysdate_local;


end time_utils_pkg;
/
