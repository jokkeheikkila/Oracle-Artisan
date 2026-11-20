create or replace package ad_pkg as
/*****************************************************************
* Package Name: AD_PKG
*
* Description:  Programs for interacting with Active Directory (LDAP). 
*               Opens the LDAP connection when needed.
*               
*       Needs:  Network ACL to the LDAP server
*
*
* Ver    Author                  Date             Comments
* 1.0    Jokke Heikkilä       11.03.2020        First version
******************************************************************/

  g_debug                 boolean := false; -- prints to dbms_output
  g_leave_connection_open boolean := false; -- true = keep the connection between calls, call close_connection yourself

  type varchar2_array is table of varchar2(32767);

  type lookup_type is record (
    l_index varchar2(4000), -- attribute name
    l_value clob            -- attribute value(s), several values separated with line feed
  );

  type lookups_type is table of lookup_type;   -- attributes of one entry

  type lookups_array is table of lookups_type; -- entries


  /*--------------------------------------------------------------*
  *  PROCEDURE new_connection
  *  DESCRIPTION
  *    Connects to AD with LDAP
  *
  *---------------------------------------------------------------*/
  procedure new_connection(p_force in boolean default false);


  /*--------------------------------------------------------------*
  *  PROCEDURE close_connection
  *  DESCRIPTION
  *    Closes the LDAP connection
  *
  *---------------------------------------------------------------*/
  procedure close_connection;


  /*--------------------------------------------------------------*
  *  FUNCTION get_data
  *  DESCRIPTION
  *    Retrieves data from AD.
  *    Search filter must be in LDAP search format.
  *    Retrieved attributes can be defined. Otherwise retrieves all attributes from AD.
  *
  *---------------------------------------------------------------*/
  function get_data(p_search_filter in varchar2, p_attributes in varchar2_array default varchar2_array()) return lookups_array;


  /*--------------------------------------------------------------*
  *  FUNCTION get_attribute_value
  *  DESCRIPTION
  *    Retrieves user's attribute value from AD.
  *
  *---------------------------------------------------------------*/
  function get_attribute_value(p_ad_user in varchar2, p_attribute in varchar2) return clob;


  /*--------------------------------------------------------------*
  *  FUNCTION get_all_attribute_values
  *  DESCRIPTION
  *    Returns all attributes of the user.
  *
  *---------------------------------------------------------------*/
  function get_all_attribute_values(p_ad_user in varchar2) return lookups_type;


  /*--------------------------------------------------------------*
  *  PROCEDURE print_all_attribute_values
  *  DESCRIPTION
  *    Prints all attributes of the user to dbms_output.
  *
  *---------------------------------------------------------------*/
  procedure print_all_attribute_values(p_ad_user in varchar2);


  /*--------------------------------------------------------------*
  *  FUNCTION get_user_status
  *  DESCRIPTION
  *    Returns user AD status (N/A=no status or not exists, ENABLED=enabled in AD, DISABLED=disabled in AD).
  *
  *---------------------------------------------------------------*/
  function get_user_status(p_ad_user in varchar2) return varchar2;


  /*--------------------------------------------------------------*
  *  FUNCTION get_group_members
  *  DESCRIPTION
  *    Returns all active AD users (account names in upper case) who are members
  *    of the given AD groups. Group is given as distinguished name,
  *    e.g. CN=MyGroup,OU=Groups,DC=example,DC=com.
  *
  *---------------------------------------------------------------*/
  function get_group_members(p_groups in varchar2_array) return varchar2_array;


  /*--------------------------------------------------------------*
  *  FUNCTION get_manager
  *  DESCRIPTION
  *    Returns the account name of the user's manager
  *
  *---------------------------------------------------------------*/
  function get_manager(p_ad_user in varchar2) return varchar2;


  /*--------------------------------------------------------------*
  *  FUNCTION disabled_user_status
  *  DESCRIPTION
  *    Returns disabled user status string
  *
  *---------------------------------------------------------------*/
  function disabled_user_status return varchar2;


  /*--------------------------------------------------------------*
  *  FUNCTION enabled_user_status
  *  DESCRIPTION
  *    Returns enabled user status string
  *
  *---------------------------------------------------------------*/
  function enabled_user_status return varchar2;


  /*--------------------------------------------------------------*
  *  FUNCTION get_user_filter
  *  DESCRIPTION
  *    Returns LDAP search filter for AD user
  *
  *---------------------------------------------------------------*/
  function get_user_filter(p_ad_user in varchar2) return varchar2;


  /*--------------------------------------------------------------*
  *  FUNCTION get_group_user_filter
  *  DESCRIPTION
  *    Returns LDAP search filter for the members of the AD group
  *
  *---------------------------------------------------------------*/
  function get_group_user_filter(p_ad_group in varchar2) return varchar2;


  /*--------------------------------------------------------------*
  *  FUNCTION get_distinguished_name_filter
  *  DESCRIPTION
  *    Returns LDAP search filter for the user with the given distinguished name
  *
  *---------------------------------------------------------------*/
  function get_distinguished_name_filter(
    p_dist_name in varchar2
  ) return varchar2;


end ad_pkg;
/


create or replace package body ad_pkg as

  /* Exceptions ***************************************/

  subscriptbeyondcount exception;
  pragma exception_init(subscriptbeyondcount, -6533);


  /* Forward declarations *****************************/

  procedure initialize;

  function convert_status(p_code in varchar2) return varchar2;

  function get_value(p_ldap_values in dbms_ldap.string_collection) return clob;

  function get_value(p_ldap_values in dbms_ldap.binval_collection) return clob;

  procedure print_clob(p_clob in clob);

  procedure do_debug(p_text in varchar2);

  procedure log_error(p_text in varchar2);


  /* Constant variables *******************************/

  c_user_status_attr   constant varchar2(40)     := 'userAccountControl';
  c_username_attr      constant varchar2(40)     := 'sAMAccountName';
  c_groups_attr        constant varchar2(40)     := 'memberOf';
  c_dist_name_attr     constant varchar2(40)     := 'distinguishedName';
  c_foreman_attr       constant varchar2(40)     := 'manager';
  c_status_enabled     constant varchar2(12)     := 'ENABLED';
  c_status_disabled    constant varchar2(12)     := 'DISABLED';
  c_status_na          constant varchar2(12)     := 'N/A';
  c_object_filter      constant varchar2(60)     := '(objectCategory=person)(objectClass=person)';


  /* Global variables *********************************/

  g_session dbms_ldap.session;
  g_host    varchar2(80);
  g_port    varchar2(6);
  g_user    varchar2(256);
  g_pwd     varchar2(40);
  g_base    varchar2(2000);


  /* Public subprograms *******************************/

  procedure new_connection(
    p_force in boolean default false
  ) is
    l_retval pls_integer;
  begin
    if g_host is null then
      initialize;
    end if;

    if p_force then
      close_connection;
    end if;

    if g_session is null then
      do_debug('New connection');

      g_session := dbms_ldap.init(
        hostname => g_host,
        portnum  => g_port
      );

      l_retval := dbms_ldap.simple_bind_s(
        ld     => g_session,
        dn     => g_user,
        passwd => g_pwd
      );
    end if;

  end new_connection;


  procedure close_connection is
    l_retval pls_integer;
  begin
    do_debug('Close connection');
    l_retval := dbms_ldap.unbind_s(ld => g_session);

  exception when others then
    null;
  end close_connection;


  function get_data(
    p_search_filter in varchar2,
    p_attributes    in varchar2_array default varchar2_array()
  ) return lookups_array is
    l_value        varchar2(32767);
    l_entries      lookups_array := lookups_array();
    l_attr_values  lookups_type := lookups_type();
    l_attrs        dbms_ldap.string_collection;
    l_message      dbms_ldap.message;
    l_entry        dbms_ldap.message;
    l_attr_name    varchar2(256);
    l_ber_element  dbms_ldap.ber_element;
    l_retval       pls_integer;
  begin
    new_connection;

    do_debug(p_search_filter);

    if p_attributes is empty then
      l_attrs(1) := '*';
      do_debug(l_attrs(1));

    else
      for i in 1..p_attributes.count loop
        l_attrs(i) := p_attributes(i);
        do_debug(l_attrs(i));
      end loop;
    end if;

    l_retval := dbms_ldap.search_s(
      ld       => g_session,
      base     => g_base,
      scope    => dbms_ldap.scope_subtree,
      filter   => p_search_filter,
      attrs    => l_attrs,
      attronly => 0,
      res      => l_message
    );

    if dbms_ldap.count_entries(ld => g_session, msg => l_message) > 0 then

      l_entry := dbms_ldap.first_entry(ld => g_session, msg => l_message);

      while l_entry is not null loop
        l_attr_values := lookups_type();

        l_attr_name := dbms_ldap.first_attribute(
          ld        => g_session,
          ldapentry => l_entry,
          ber_elem  => l_ber_element
        );

        while l_attr_name is not null loop
          if l_attr_name in ('thumbnailPhoto') then
            l_value := '<excluded>';
          else
            l_value := get_value(dbms_ldap.get_values_len(ld => g_session, ldapentry => l_entry, attr => l_attr_name));
          end if;

          l_attr_values.extend;
          l_attr_values(l_attr_values.last).l_index := l_attr_name;
          l_attr_values(l_attr_values.last).l_value := l_value;

          l_attr_name := dbms_ldap.next_attribute(ld => g_session, ldapentry => l_entry, ber_elem => l_ber_element);
        end loop;

        l_entries.extend;
        l_entries(l_entries.last) := l_attr_values;

        l_entry := dbms_ldap.next_entry(ld => g_session, msg => l_entry);

      end loop entry_loop;

    end if;

    if not g_leave_connection_open then
      close_connection;
    end if;

    return l_entries;

  exception when others then
    log_error(sqlerrm || ' (attribute: ' || l_attr_name || ')');
    close_connection;
    raise;
  end get_data;


  function get_attribute_value(
    p_ad_user  in varchar2,
    p_attribute in varchar2
  ) return clob is
  begin
    return get_data(get_user_filter(p_ad_user), varchar2_array(p_attribute))(1)(1).l_value;

  exception
    when subscriptbeyondcount then
      return null;
  end get_attribute_value;


  function get_all_attribute_values(
    p_ad_user  in varchar2
  ) return lookups_type is
  begin
    return get_data(get_user_filter(p_ad_user))(1);

  end get_all_attribute_values;


  procedure print_all_attribute_values(
    p_ad_user in varchar2
  ) is
    type t_sorted is table of pls_integer index by varchar2(4000);

    l_values lookups_type := get_all_attribute_values(p_ad_user);
    l_sorted t_sorted;
    l_key    varchar2(4000);
  begin
    -- sort by attribute name
    for i in 1..l_values.count loop
      l_sorted(upper(l_values(i).l_index)) := i;
    end loop;

    l_key := l_sorted.first;
    while l_key is not null loop
      print_clob(l_values(l_sorted(l_key)).l_index||': '||l_values(l_sorted(l_key)).l_value);
      dbms_output.put_line(' ');
      l_key := l_sorted.next(l_key);
    end loop;

  end print_all_attribute_values;


  function get_user_status(
    p_ad_user in varchar2
  ) return varchar2 is
  begin
    return convert_status(get_attribute_value(p_ad_user, c_user_status_attr));

  end get_user_status;


  function get_group_members(
    p_groups in varchar2_array
  ) return varchar2_array is
    l_data     lookups_array := lookups_array();
    l_temp     lookups_array := lookups_array();
    l_users    varchar2_array := varchar2_array();
    l_username varchar2(256);
    l_active   boolean;

    type distinct_assoc_arr is table of boolean index by varchar2(256);
    l_distinct_arr distinct_assoc_arr;
  begin
    if p_groups is not empty then
      for g in 1..p_groups.count loop
        l_temp := get_data(get_group_user_filter(p_groups(g)), varchar2_array(c_user_status_attr, c_username_attr));

        for e in 1..l_temp.count loop
          l_data.extend;
          l_data(l_data.last) := l_temp(e);
        end loop;
      end loop;
    end if;

    if l_data is not empty then
      for i in 1..l_data.count loop
        if l_data(i) is not empty then
          l_active := false;
          l_username := null;

          for j in 1..l_data(i).count loop

            case l_data(i)(j).l_index
              when c_user_status_attr then
                l_active := convert_status(l_data(i)(j).l_value) = enabled_user_status();
              when c_username_attr then
                l_username := upper(l_data(i)(j).l_value);
            end case;

          end loop;

          if l_active and l_username is not null and not l_distinct_arr.exists(l_username) then
            l_distinct_arr(l_username) := true;
            l_users.extend;
            l_users(l_users.last) := l_username;
          end if;

        end if;
      end loop;
    end if;

    return l_users;

  end get_group_members;


  function get_manager(
    p_ad_user in varchar2
  ) return varchar2 is
    l_manager         varchar2(400);
    l_manager_ad_user varchar2(256);
  begin
    l_manager := ad_pkg.get_attribute_value(p_ad_user, c_foreman_attr);

    if l_manager is not null then
      l_manager_ad_user := get_data(get_distinguished_name_filter(l_manager), varchar2_array(c_username_attr))(1)(1).l_value;
    end if;

    return l_manager_ad_user;

  end get_manager;


  function disabled_user_status
  return varchar2 is
  begin
    return c_status_disabled;
  end disabled_user_status;


  function enabled_user_status
  return varchar2 is
  begin
    return c_status_enabled;
  end enabled_user_status;


  function get_user_filter(
    p_ad_user in varchar2
  ) return varchar2 is
  begin
    return '(&'||c_object_filter||'('||c_username_attr||'='||p_ad_user||'))';

  end get_user_filter;


  function get_group_user_filter(
    p_ad_group in varchar2
  ) return varchar2 is
  begin
    return '(&'||c_object_filter||'('||c_groups_attr||'='||p_ad_group||')'||')';

  end get_group_user_filter;


  function get_distinguished_name_filter(
    p_dist_name in varchar2
  ) return varchar2 is
  begin
    return '(&'||c_object_filter||'('||c_dist_name_attr||'='||p_dist_name||'))';

  end get_distinguished_name_filter;



  /* Private subprograms  *****************************/

  procedure initialize is
  begin
    -- Implement variable initialization according to your system for:
    --   g_host, g_port, g_user, g_pwd, g_base
    null;

  end initialize;


  function convert_status(
    p_code in varchar2
  ) return varchar2 is
    l_status varchar2(20);
  begin
    if p_code is null then
      l_status := c_status_na;
    elsif p_code in (
      '514',
      '530',
      '546',
      '66050',
      '66066',
      '66082',
      '131586',
      '1049090'
    ) then
      l_status := c_status_disabled;
    else
      l_status := c_status_enabled;
    end if;

    return l_status;

  end convert_status;


  function get_value(
    p_ldap_values in dbms_ldap.string_collection
  ) return clob is
    l_value clob;
  begin
    if p_ldap_values.count > 0 then
      for i in p_ldap_values.first .. p_ldap_values.last loop
        if l_value is not null then
          l_value := l_value || chr(10);
        end if;
        l_value := l_value || p_ldap_values(i);
      end loop;

    end if;

    return l_value;

  end get_value;


  function get_value(
    p_ldap_values in dbms_ldap.binval_collection
  ) return clob is
    l_value clob;
  begin
    if p_ldap_values.count > 0 then
      for i in p_ldap_values.first .. p_ldap_values.last loop
        if l_value is not null then
          l_value := l_value || chr(10);
        end if;
        begin
          l_value := l_value || utl_i18n.raw_to_char(p_ldap_values(i), 'UTF8');
        exception when others then
          null; -- not a valid utf8 value
        end;
      end loop;
    end if;

    return l_value;

  end get_value;


  procedure print_clob(
    p_clob in clob
  ) is
    l_offset pls_integer := 1;
  begin
    -- prints without line feed, caller ends the line
    loop
      exit when l_offset > nvl(dbms_lob.getlength(p_clob), 0);
      dbms_output.put(dbms_lob.substr(p_clob, 255, l_offset));
      l_offset := l_offset + 255;
    end loop;

  end print_clob;


  procedure do_debug(
    p_text in varchar2
  ) is
  begin
    if g_debug then
      dbms_output.put_line('AD_PKG: ' || p_text);
    end if;

    -- Implement debugging according to your system
  end do_debug;


  procedure log_error(
    p_text in varchar2
  ) is
  begin
    dbms_output.put_line('AD_PKG ERROR: ' || p_text);

    -- Implement logging according to your system
  end log_error;

end ad_pkg;
/
