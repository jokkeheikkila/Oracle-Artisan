create or replace package rest_api_pkg as
/*****************************************************************
* Package Name: REST_API_PKG
*
* Description:  Wrapper package for HTTP REST services
*
*   Needs:
*   - network ACL to the called servers
*   - wallet with the server certificates, for https addresses
*
*   HTTP errors (4xx/5xx) do not raise. Check l_status_code.
*
*   Debug: ALTER PACKAGE rest_api_pkg COMPILE PLSQL_CCFLAGS='DebugMode:TRUE'
*
* Ver    Author                  Date             Comments
* 1.0    Jokke Heikkilä       20.10.2015        First version
******************************************************************/

  g_debug     boolean := nvl($$debugmode, false); -- prints to dbms_output
  g_error_log boolean := true;                    -- prints errors to dbms_output

  type message_type is record(
    l_content_type varchar2(80),
    l_content      clob
  );

  type short_message_type is record(
    l_content_type varchar2(80),
    l_content      varchar2(32767)
  );

  type response_type is record(
    l_status_code   pls_integer,
    l_reason_phrase varchar2(256),
    l_content       clob
  );

  type short_response_type is record(
    l_status_code   pls_integer,
    l_reason_phrase varchar2(256),
    l_content       varchar2(32767)
  );

  type http_header_type is record(
    l_value varchar2(600),
    l_name  varchar2(200)
  );

  type http_headers_type is table of http_header_type;

  type value_name_type is record(
    l_value varchar2(2000),
    l_name  varchar2(2000)
  );

  type value_names_type is table of value_name_type;

  -- returns p_url/p_service/?name=value&... (values are URL escaped)
  function generate_url(
    p_url     in varchar2,
    p_service in varchar2,
    p_params  in value_names_type default null
  ) return varchar2;

  -- adds Authorization header, e.g. p_value => 'Bearer ' || l_token
  procedure add_authorization_header(
    p_headers in out nocopy http_headers_type,
    p_value   in varchar2
  );

  -- CLOB version: any size. Short version: max 32767 bytes.
  function call_service(
    p_http_method in varchar2,
    p_url         in varchar2,
    p_headers     in http_headers_type default null,
    p_message     in message_type      default null,
    p_username    in varchar2          default null,
    p_password    in varchar2          default null,
    p_timeout     in pls_integer       default 60
  ) return response_type;

  function call_service(
    p_http_method in varchar2,
    p_url         in varchar2,
    p_headers     in http_headers_type  default null,
    p_message     in short_message_type default null,
    p_username    in varchar2           default null,
    p_password    in varchar2           default null,
    p_timeout     in pls_integer        default 60
  ) return short_response_type;

  -- content type values for message l_content_type
  function default_http_content_type
  return varchar2;

  function json_http_content_type
  return varchar2;

end rest_api_pkg;
/


create or replace package body rest_api_pkg as

  /* Types ********************************************/
  subtype max_chunk is varchar2(32767);

  type chunk_array is table of max_chunk;


  /* Forward declarations *****************************/
  function is_https_address(
    p_address in varchar2
  ) return boolean;

  procedure set_wallet;

  function begin_request(
    p_http_method in varchar2,
    p_url         in varchar2,
    p_timeout     in pls_integer
  ) return utl_http.req;


  procedure set_headers(
    p_http_request    in out nocopy utl_http.req,
    p_http_headers    in http_headers_type,
    p_content_type    in varchar2,
    p_message_lengthb in pls_integer
  );

  procedure authenticate(
    p_http_request in out nocopy utl_http.req,
    p_username     in varchar2,
    p_password     in varchar2
  );

  procedure generate_message_chunks(
    p_message in message_type,
    p_chunks  out chunk_array,
    p_lenthb  out pls_integer
  );

  procedure write_body(
    p_http_request   in out nocopy utl_http.req,
    p_message_chunks in out nocopy chunk_array
  );

  procedure write_body(
    p_http_request in out nocopy utl_http.req,
    p_message      in max_chunk
  );

  function get_response(
    p_http_request in out nocopy utl_http.req
  ) return response_type;

  function get_short_response(
    p_http_request in out nocopy utl_http.req
  ) return short_response_type;

  procedure do_debug(
    p_data in clob
  );

  procedure log_error(
    p_text in varchar2
  );


  /* Constant variables *******************************/
  c_charset                   constant varchar2(5)              := 'UTF-8';
  c_default_http_content_type constant varchar2(30)             := 'text/xml;charset='||c_charset;
  c_json_http_content_type    constant varchar2(40)             := 'application/json;charset='||c_charset;
  c_http_version              constant varchar2(3)              := '1.1';
  c_http_version_str          constant varchar2(8)              := 'HTTP/'||c_http_version;
  c_http_chunk_length         constant pls_integer              := 32767;
  c_authorization_key         constant varchar2(14)             := 'Authorization';


  /* Public subprograms *******************************/

  function generate_url(
    p_url     in varchar2,
    p_service in varchar2,
    p_params  in value_names_type default null
  ) return varchar2 is
    l_url varchar2(800);
  begin
    l_url := p_url || '/' || p_service || '/';

    if p_params is not empty then

      for i in 1 .. p_params.last loop

        if i = 1 then
          l_url := l_url || '?';
        else
          l_url := l_url || '&';
        end if;

        l_url := l_url || p_params(i).l_name || '=' || utl_url.escape(p_params(i).l_value, true);

      end loop;

    end if;

    return l_url;
  end generate_url;


  procedure add_authorization_header(
    p_headers in out nocopy http_headers_type,
    p_value   in varchar2
  ) is
  begin
    p_headers.extend;
    p_headers(p_headers.last).l_name  := c_authorization_key;
    p_headers(p_headers.last).l_value := p_value;
  end add_authorization_header;


  function call_service(
    p_http_method in varchar2,
    p_url         in varchar2,
    p_headers     in http_headers_type default null,
    p_message     in message_type      default null,
    p_username    in varchar2          default null,
    p_password    in varchar2          default null,
    p_timeout     in pls_integer       default 60
  ) return response_type is
    l_request         utl_http.req;
    l_response        response_type;
    l_message_lengthb pls_integer;
    l_message_chunks  chunk_array;
  begin
    if is_https_address(p_url) then
      set_wallet;
    end if;

    l_request := begin_request(p_http_method, p_url, p_timeout);

    generate_message_chunks(p_message, l_message_chunks, l_message_lengthb);

    set_headers(l_request, p_headers, p_message.l_content_type, l_message_lengthb);

    authenticate(l_request, p_username, p_password);

    write_body(l_request, l_message_chunks);

    l_response := get_response(l_request);

    return l_response;

  exception when others then
    log_error(p_http_method || ': ' || p_url || ': ' || sqlerrm);
    raise;
  end call_service;


  function call_service(
    p_http_method in varchar2,
    p_url         in varchar2,
    p_headers     in http_headers_type  default null,
    p_message     in short_message_type default null,
    p_username    in varchar2           default null,
    p_password    in varchar2           default null,
    p_timeout     in pls_integer        default 60
  ) return short_response_type is
    l_request        utl_http.req;
    l_response       short_response_type;
  begin
    if is_https_address(p_url) then
      set_wallet;
    end if;

    l_request := begin_request(p_http_method, p_url, p_timeout);

    set_headers(l_request, p_headers, p_message.l_content_type, lengthb(p_message.l_content));

    authenticate(l_request, p_username, p_password);

    write_body(l_request, p_message.l_content);

    l_response := get_short_response(l_request);

    return l_response;

  exception when others then
    log_error(p_http_method || ': ' || p_url || ': ' || sqlerrm);
    raise;
  end call_service;


  function default_http_content_type
  return varchar2 is
  begin
    return c_default_http_content_type;
  end default_http_content_type;


  function json_http_content_type
  return varchar2 is
  begin
    return c_json_http_content_type;
  end json_http_content_type;


  /* Private subprograms  *****************************/

  function is_https_address(
    p_address in varchar2
  ) return boolean is
  begin
    return upper(p_address) like 'HTTPS://%';

  end is_https_address;


  procedure set_wallet is
    l_path varchar2(200);
    l_pwd  varchar2(40);
  begin
    -- Implement wallet configuration according to your system:
    --   l_path := '/path/to/wallet';
    --   l_pwd  := 'wallet_password';
    if l_path is not null then
      utl_http.set_wallet('file:'||l_path, l_pwd);
    end if;

  end set_wallet;


  function begin_request(
    p_http_method in varchar2,
    p_url         in varchar2,
    p_timeout     in pls_integer
  ) return utl_http.req is
  begin
    utl_http.set_response_error_check(false); -- so HTTP 4xx/5xx do not raise, caller checks l_status_code

    utl_http.set_transfer_timeout(p_timeout);

    do_debug(p_http_method || ' - ' || p_url);

    return utl_http.begin_request(p_url, p_http_method, c_http_version_str);

  end begin_request;


  procedure set_headers(
    p_http_request    in out nocopy utl_http.req,
    p_http_headers    in http_headers_type,
    p_content_type    in varchar2,
    p_message_lengthb in pls_integer
  ) is
  begin
    utl_http.set_body_charset(p_http_request, c_charset);

    utl_http.set_header(p_http_request, 'Content-Type', nvl(p_content_type, default_http_content_type()));
    utl_http.set_header(p_http_request, 'Content-Length', to_char(nvl(p_message_lengthb,0)));

    if p_http_headers is not empty then

      for i in 1 .. p_http_headers.last loop
        do_debug('Header: '||p_http_headers(i).l_name || '/' || p_http_headers(i).l_value);
        utl_http.set_header(p_http_request, p_http_headers(i).l_name, p_http_headers(i).l_value);
      end loop;

    end if;

  end set_headers;

  procedure authenticate(
    p_http_request in out nocopy utl_http.req,
    p_username     in varchar2,
    p_password     in varchar2
  ) is
  begin
    if p_username is not null and p_password is not null then
      do_debug('Authentication: '||p_username);
      utl_http.set_authentication(p_http_request, p_username, p_password);
    end if;

  end authenticate;


  procedure generate_message_chunks(
    p_message in message_type,
    p_chunks  out chunk_array,
    p_lenthb  out pls_integer
  ) is
    l_buffer max_chunk;
    l_amount pls_integer := 16000;
    l_index  pls_integer := 1;
  begin
    p_chunks := chunk_array();
    p_lenthb := 0;

    do_debug('Message: '||p_message.l_content);

    if not p_message.l_content = empty_clob() then
      loop

        begin
          dbms_lob.read(p_message.l_content, l_amount, l_index, l_buffer);
        exception when no_data_found then
          exit;
        end;

        p_chunks.extend;
        p_chunks(p_chunks.last) := l_buffer;

        p_lenthb := p_lenthb + lengthb(l_buffer);

        l_index := l_index + l_amount;

      end loop;

    end if;

  end generate_message_chunks;


  procedure write_body(
    p_http_request   in out nocopy utl_http.req,
    p_message_chunks in out nocopy chunk_array
  ) is
  begin
    if p_message_chunks is not empty then

      for i in 1 .. p_message_chunks.last loop
        utl_http.write_text(p_http_request, p_message_chunks(i));
      end loop;

    end if;

  end write_body;


  procedure write_body(
    p_http_request in out nocopy utl_http.req,
    p_message      in max_chunk
  ) is
  begin
    do_debug('Message: '||p_message);

    utl_http.write_text(p_http_request, p_message);

  end write_body;


  function get_response(
    p_http_request in out nocopy utl_http.req
  ) return response_type is
    l_http_response utl_http.resp;
    l_response      response_type;
    l_buffer        max_chunk;
  begin
    l_http_response := utl_http.get_response(p_http_request);

    l_response.l_status_code   := l_http_response.status_code;
    l_response.l_reason_phrase := l_http_response.reason_phrase;

    dbms_lob.createtemporary(l_response.l_content, cache => false);
    dbms_lob.open(l_response.l_content, dbms_lob.lob_readwrite);
    begin

      loop
        utl_http.read_text(l_http_response, l_buffer, c_http_chunk_length);
        dbms_lob.writeappend(l_response.l_content, length(l_buffer), l_buffer);
      end loop;

    exception when utl_http.end_of_body then
      null;
    end;
    dbms_lob.close(l_response.l_content);

    utl_http.end_response(l_http_response);

    do_debug('Response: '||l_response.l_content);

    return l_response;

  end get_response;


  function get_short_response(
    p_http_request in out nocopy utl_http.req
  ) return short_response_type is
    l_http_response utl_http.resp;
    l_response      short_response_type;
  begin
    l_http_response := utl_http.get_response(p_http_request);

    l_response.l_status_code   := l_http_response.status_code;
    l_response.l_reason_phrase := l_http_response.reason_phrase;

    begin
      utl_http.read_text(l_http_response, l_response.l_content, c_http_chunk_length);
    exception when utl_http.end_of_body then
      null;
    end;

    utl_http.end_response(l_http_response);

    do_debug('Response: '||l_response.l_content);

    return l_response;

  end get_short_response;


  procedure do_debug(p_data in clob) is
    l_offset pls_integer := 1;
  begin
    if g_debug then
      loop
        exit when l_offset > nvl(dbms_lob.getlength(p_data), 0);
        dbms_output.put(dbms_lob.substr(p_data, 255, l_offset));
        l_offset := l_offset + 255;
      end loop;
      dbms_output.new_line;
    end if;

    -- Implement debugging according to your system
  end do_debug;


  procedure log_error(p_text in varchar2) is
  begin
    if g_error_log then
      dbms_output.put_line('REST_API_PKG: ' || p_text);
    end if;

    -- Implement logging according to your system
  end log_error;


end rest_api_pkg;
/
