create or replace package synchronized_pkg as
/*****************************************************************
* Package Name: SYNCHRONIZED_PKG
*
* Description:
*   Package provides PL/SQL block level lock handling.
*   So if start_block is executed in a program
*   then no one else can run that part of the program simultaneously.
*   Works like the synchronized keyword in Java.
*
*   NOTE!
*   1) start_block does commit
*   2) remember to put stop_block also in exception section.
*   Although lock is released when session is disconnected
*   it's good to release lock immediately when it's no longer needed.
*
* Ver    Author                  Date             Comments
* 1.0    Jokke Heikkilä       12.10.2011        First version
******************************************************************/

  /*--------------------------------------------------------------*
  *  FUNCTION start_block
  *  DESCRIPTION
  *    Gets a block level lock and returns ID of the lock.
  *    Waits until the lock is free.
  *    Does commit!
  *
  *  ARGUMENTS
  *     IN:
  *       p_lock_name    If lock name is defined then it's part of the lock handle.
  *                      I.e. allows the same part of the program to run simultaneously
  *                      with different lock names.
  *---------------------------------------------------------------*/
  function start_block(p_lock_name in varchar2 default null) return varchar2;


  /*--------------------------------------------------------------*
  *  PROCEDURE stop_block
  *  DESCRIPTION
  *    Releases a block level lock
  *
  *  ARGUMENTS
  *     IN:
  *       p_lock_id    Lock ID which was returned from the start_block function
  *---------------------------------------------------------------*/
  procedure stop_block(p_lock_id in varchar2);


end synchronized_pkg;
/


create or replace package body synchronized_pkg as

  /* Public subprograms *******************************/
  function start_block(p_lock_name in varchar2 default null) return varchar2 is
    l_owner      varchar2(2000);
    l_name       varchar2(2000);
    l_lineno     varchar2(2000);
    l_caller_t   varchar2(2000);
    l_lockname   varchar2(32767);
    l_lockhandle varchar2(32767);
    l_status     pls_integer;
  begin
    owa_util.who_called_me(l_owner, l_name, l_lineno, l_caller_t);

    -- generate unique lockname
    l_lockname :=  l_owner || l_name || l_lineno || l_caller_t || p_lock_name;

    -- create lockhandle if not already exist
    dbms_lock.allocate_unique(l_lockname, l_lockhandle);

    -- try to get a lock
    l_status := dbms_lock.request(l_lockhandle, 6);

    -- if success or already own lock
    if l_status not in (0,4) then
      raise program_error;
    end if;

    return l_lockhandle;
  end start_block;


  procedure stop_block(p_lock_id in varchar2) is
    l_status pls_integer;
  begin
    l_status := dbms_lock.release(p_lock_id);

    -- if success or do not own lock specified by lockhandle
    if l_status not in (0,4) then
      raise program_error;
    end if;

  end stop_block;


end synchronized_pkg;
/
