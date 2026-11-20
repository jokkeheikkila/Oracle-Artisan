create or replace package email_pkg as
/*****************************************************************
* Package Name: EMAIL_PKG
*
* Description:  Utilities for sending and validating emails
*
*   Needs:
*   - types EMAIL_ADDRESSES_TYPE, EMAIL_ATTACHMENT_TYPE, EMAIL_ATTACHMENTS_TYPE (types/)
*   - table EMAIL_QUEUE (tables/email_queue.sql)
*   - scheduler job EMAIL_QUEUE_JOB (scheduler/email_queue_job.sql)
*   - network ACL to the SMTP server
*
* Ver    Author                  Date             Comments
* 1.0    Jokke Heikkilä       10.04.2014        First version
******************************************************************/

  g_charset          varchar2(20)  := 'utf-8';
  g_helo_client      varchar2(255) := 'localhost'; -- host name (FQDN) of the DB server, sent in SMTP EHLO; configure according to your system
  g_queue_send_delay pls_integer   := 1;     -- seconds between queued sends, avoids spam filtering
  g_use_tls          boolean       := true;  -- STARTTLS, needs a wallet with the SMTP server certificate
  g_use_auth         boolean       := true;  -- SMTP authentication with username and password
  g_debug            boolean       := false; -- prints recipients to dbms_output


  -- Sends the email. By default it is added to EMAIL_QUEUE and sent by EMAIL_QUEUE_JOB.
  procedure send_mail(
    p_from         in varchar2,                           -- empty = default sender
    p_from_name    in varchar2 default null,
    p_to           in varchar2,                           -- addresses separated with ;
    p_cc           in varchar2 default null,              -- addresses separated with ;
    p_bcc          in varchar2 default null,              -- addresses separated with ;
    p_subject      in varchar2,
    p_message      in clob,
    p_content_type in varchar2 default 'text/plain',      -- text/html
    p_attachments  in email_attachments_type default null,
    p_synchronous  in boolean default false               -- sends the email right away without using queue
  );


  -- Sends the email. By default it is added to EMAIL_QUEUE and sent by EMAIL_QUEUE_JOB.
  procedure send_mail(
    p_from         in varchar2,                           -- empty = default sender
    p_from_name    in varchar2 default null,
    p_to           in email_addresses_type,
    p_cc           in email_addresses_type default null,
    p_bcc          in email_addresses_type default null,
    p_subject      in varchar2,
    p_message      in clob,
    p_content_type in varchar2 default 'text/plain',      -- text/html
    p_attachments  in email_attachments_type default null,
    p_synchronous  in boolean default false               -- sends the email right away without using queue
  );


  -- Attachments: call initialize_attachments, add_*_attachment, then pass get_attachments to send_mail
  procedure initialize_attachments;
  procedure add_text_attachment(
    p_name in varchar2,
    p_data in clob,
    p_mime in varchar2 default 'text/html'
  );
  procedure add_binary_attachment(
    p_name in varchar2,
    p_data in blob,
    p_mime in varchar2 default 'application/octet-stream'
  );
  function get_attachments return email_attachments_type;
  --

  procedure process_queue; -- sends all queued emails, run by EMAIL_QUEUE_JOB

  procedure notify_queue;  -- starts EMAIL_QUEUE_JOB now, does not wait

  function validate_email_address(p_email_address in varchar2)
  return varchar2; -- 'TRUE' / 'FALSE'. Empty address returns 'TRUE'

end email_pkg;
/

create or replace package body email_pkg as

  /* Forward declarations *****************************/

  procedure add_to_queue(
    p_from         in varchar2,
    p_from_name    in varchar2,
    p_to           in email_addresses_type,
    p_cc           in email_addresses_type,
    p_bcc          in email_addresses_type,
    p_subject      in varchar2,
    p_message      in clob,
    p_content_type in varchar2,
    p_attachments  in email_attachments_type
  );

  procedure do_send(
    p_from         in varchar2,
    p_from_name    in varchar2,
    p_to           in email_addresses_type,
    p_cc           in email_addresses_type,
    p_bcc          in email_addresses_type,
    p_subject      in varchar2,
    p_message      in clob,
    p_content_type in varchar2,
    p_attachments  in email_attachments_type
  );

  procedure write_text_data  (
    p_connection in out nocopy utl_smtp.connection,
    p_data       in clob
  );

  procedure write_binary_data(
    p_connection in out nocopy utl_smtp.connection,
    p_data       in blob
  );

  function encode_header_text(p_text in varchar2) return varchar2;

  function request_lock(p_lock_name in varchar2) return varchar2;

  procedure release_lock(p_lock_handle in varchar2);

  procedure log_info(p_text in varchar2);

  procedure log_error(p_text in varchar2);

  procedure do_debug(p_text in varchar2);


  /* Global variables *********************************/

  g_attachments email_attachments_type;


  /* Public subprograms *******************************/

  function format_text(p_text in varchar2) return raw is
  begin
    return utl_raw.cast_to_raw(p_text);
  end format_text;


  procedure send_mail(
    p_from         in varchar2,
    p_from_name    in varchar2 default null,
    p_to           in varchar2,
    p_cc           in varchar2 default null,
    p_bcc          in varchar2 default null,
    p_subject      in varchar2,
    p_message      in clob,
    p_content_type in varchar2 default 'text/plain',
    p_attachments  in email_attachments_type default null,
    p_synchronous  in boolean default false
  ) is
    cursor split_cursor(p_recipients in varchar2) is
    select regexp_substr(p_recipients, '[^;]+', 1, level) email_address
      from dual
    connect by regexp_substr(p_recipients, '[^;]+', 1, level) is not null;

    l_to  email_addresses_type := email_addresses_type();
    l_cc  email_addresses_type := email_addresses_type();
    l_bcc email_addresses_type := email_addresses_type();
  begin

    for i in split_cursor(p_to) loop
      l_to.extend;
      l_to(l_to.last) := i.email_address;
    end loop;

    if p_cc is not null then
      for i in split_cursor(p_cc) loop
        l_cc.extend;
        l_cc(l_cc.last) := i.email_address;
      end loop;
    end if;

    if p_bcc is not null then
      for i in split_cursor(p_bcc) loop
        l_bcc.extend;
        l_bcc(l_bcc.last) := i.email_address;
      end loop;
    end if;

    send_mail(
      p_from         => p_from,
      p_from_name    => p_from_name,
      p_to           => l_to,
      p_cc           => l_cc,
      p_bcc          => l_bcc,
      p_subject      => p_subject,
      p_message      => p_message,
      p_content_type => p_content_type,
      p_attachments  => p_attachments,
      p_synchronous  => p_synchronous
    );

  end send_mail;


  procedure send_mail(
    p_from         in varchar2,
    p_from_name    in varchar2 default null,
    p_to           in email_addresses_type,
    p_cc           in email_addresses_type default null,
    p_bcc          in email_addresses_type default null,
    p_subject      in varchar2,
    p_message      in clob,
    p_content_type in varchar2 default 'text/plain',
    p_attachments  in email_attachments_type default null,
    p_synchronous  in boolean default false
  ) is
  begin
    if p_synchronous then
      do_send(p_from, p_from_name, p_to, p_cc, p_bcc, p_subject, p_message, p_content_type, p_attachments);
    else
      add_to_queue(p_from, p_from_name, p_to, p_cc, p_bcc, p_subject, p_message, p_content_type, p_attachments);
    end if;

  end send_mail;


  procedure initialize_attachments is
  begin
    g_attachments := email_attachments_type();
  end initialize_attachments;


  procedure add_text_attachment(
    p_name in varchar2,
    p_data in clob,
    p_mime in varchar2 default 'text/html'
  ) is
    l_attachment email_attachment_type;
  begin
    g_attachments.extend;

    l_attachment := email_attachment_type('TEXT', p_name, p_mime, p_data, null);

    g_attachments(g_attachments.last) := l_attachment;

  end add_text_attachment;


  procedure add_binary_attachment(
    p_name in varchar2,
    p_data in blob,
    p_mime in varchar2 default 'application/octet-stream'
  ) is
    l_attachment email_attachment_type;
  begin
    g_attachments.extend;

    l_attachment := email_attachment_type('BINARY', p_name, p_mime, null, p_data);

    g_attachments(g_attachments.last) := l_attachment;

  end add_binary_attachment;


  function get_attachments return email_attachments_type is
  begin
    return g_attachments;
  end get_attachments;


  procedure process_queue is
    type t_ids is table of email_queue.id%type;

    l_lock_handle varchar2(128);
    l_queue_ids   t_ids;
    l_email_rec   email_queue%rowtype;
    l_count       pls_integer := 0;
  begin
    log_info('Starts');

    l_lock_handle := request_lock($$plsql_unit_owner || '.' || $$plsql_unit || '.PROCESS_QUEUE');

    select id
      bulk collect
      into l_queue_ids
      from email_queue
     order by id;

    if l_queue_ids is not empty then
      for i in 1..l_queue_ids.count loop
        select *
          into l_email_rec
          from email_queue
         where id = l_queue_ids(i)
           for update nowait;

        delete
          from email_queue
         where id = l_email_rec.id;

        do_send(
          p_from         => l_email_rec.from_address,
          p_from_name    => l_email_rec.from_name,
          p_to           => l_email_rec.to_addresses,
          p_cc           => l_email_rec.cc_addresses,
          p_bcc          => l_email_rec.bcc_addresses,
          p_subject      => l_email_rec.subject,
          p_message      => l_email_rec.message,
          p_content_type => l_email_rec.content_type,
          p_attachments  => l_email_rec.attachments
        );

        l_count := l_count + 1;

        commit;

        if i < l_queue_ids.count then
          dbms_lock.sleep(g_queue_send_delay);
        end if;

      end loop;
    end if;

    release_lock(l_lock_handle);

    if l_count > 0 then
      log_info('Sent '||l_count||' email(s)');
    end if;

    log_info('Stops');

  exception when others then
    rollback;
    if l_count > 0 then
      log_info('Sent '||l_count||' email(s)');
    end if;
    log_error(sqlerrm);
    release_lock(l_lock_handle);
    raise;
  end process_queue;


  procedure notify_queue is
  begin
    dbms_scheduler.run_job('EMAIL_QUEUE_JOB', false);
  exception when others then
    null;
  end notify_queue;


  function validate_email_address(p_email_address in varchar2)
  return varchar2 is -- TRUE / FALSE
  begin
    if p_email_address is null
    or (regexp_like(p_email_address, '^[a-zA-Z0-9._%-]+@[a-zA-Z0-9._%-]+\.[a-zA-Z]{2,8}$')
    and instr(p_email_address,'..') = 0 )
    then
      return 'TRUE';
    else
      return 'FALSE';
    end if;

  end validate_email_address;


  /* Private subprograms  *****************************/

  procedure add_to_queue(
    p_from         in varchar2,
    p_from_name    in varchar2,
    p_to           in email_addresses_type,
    p_cc           in email_addresses_type,
    p_bcc          in email_addresses_type,
    p_subject      in varchar2,
    p_message      in clob,
    p_content_type in varchar2,
    p_attachments  in email_attachments_type
  ) is
    pragma autonomous_transaction;
  begin
    insert into email_queue (
      created,
      from_address,
      from_name,
      to_addresses,
      cc_addresses,
      bcc_addresses,
      subject,
      message,
      content_type,
      attachments
    ) values (
      systimestamp,
      p_from,
      p_from_name,
      p_to,
      p_cc,
      p_bcc,
      p_subject,
      p_message,
      p_content_type,
      p_attachments
    );

    commit;

  exception when others then
    rollback;
    raise;
  end add_to_queue;


  procedure do_send(
    p_from         in varchar2,
    p_from_name    in varchar2,
    p_to           in email_addresses_type,
    p_cc           in email_addresses_type,
    p_bcc          in email_addresses_type,
    p_subject      in varchar2,
    p_message      in clob,
    p_content_type in varchar2,
    p_attachments  in email_attachments_type
  ) is
    l_mail_conn        utl_smtp.connection;
    l_boundary         varchar2(50) := '----=*#abc1234321cba#*=';
    l_mail_server      varchar2(60);
    l_mail_server_port varchar2(5);
    l_wallet_path      varchar2(200);
    l_wallet_pwd       varchar2(40);
    l_username         varchar2(40);
    l_password         varchar2(40);
    l_from_address     varchar2(80);  -- default sender from config
    l_from             varchar2(400); -- p_from or the default sender
    l_to_given         boolean := false;
  begin
    if p_to is not empty then
      for i in 1..p_to.last loop
        if p_to(i) is not null then
          l_to_given := true;
          exit;
        end if;
      end loop;
    end if;

    if not l_to_given then
      if p_cc is not empty then
        for i in 1..p_cc.last loop
          if p_cc(i) is not null then
            l_to_given := true;
            exit;
          end if;
        end loop;
      end if;

      if not l_to_given then
        if p_bcc is not empty then
          for i in 1..p_bcc.last loop
            if p_bcc(i) is not null then
              l_to_given := true;
              exit;
            end if;
          end loop;
        end if;
      end if;
    end if;

    if not l_to_given then
      return;
    end if;

    -- Implement SMTP and TLS wallet configuration according to your system:
    --   l_mail_server      := 'smtp.example.com';
    --   l_mail_server_port := '587';
    --   l_username         := 'smtp_user';
    --   l_password         := 'smtp_password';
    --   l_from_address     := 'noreply@example.com';
    --   l_wallet_path      := '/path/to/wallet';
    --   l_wallet_pwd       := 'wallet_password';

    l_mail_conn := utl_smtp.open_connection(
      host                          => l_mail_server,
      port                          => l_mail_server_port,
      wallet_path                   => case when g_use_tls and l_wallet_path is not null then 'file:'||l_wallet_path end,
      wallet_password               => case when g_use_tls then l_wallet_pwd end,
      secure_connection_before_smtp => false
    );

    utl_smtp.ehlo(l_mail_conn, g_helo_client);

    if g_use_tls then
      utl_smtp.starttls(l_mail_conn);
      utl_smtp.ehlo(l_mail_conn, g_helo_client); -- greet again after STARTTLS
    end if;

    if g_use_auth then
      utl_smtp.auth(
        c        => l_mail_conn,
        username => l_username,
        password => l_password,
        schemes  => utl_smtp.all_schemes
      );
    end if;

    -- NOTE: many SMTP servers accept only the address of the authenticated account as sender
    l_from := nvl(p_from, l_from_address);

    utl_smtp.mail(l_mail_conn, l_from);

    if p_to is not empty then
      for i in 1 .. p_to.last loop
        utl_smtp.rcpt(l_mail_conn, p_to(i));
        do_debug('Sending to '||p_to(i)||': '||p_subject);
      end loop;
    end if;

    if p_cc is not empty then
      for i in 1 .. p_cc.last loop
        utl_smtp.rcpt(l_mail_conn, p_cc(i));
        do_debug('Sending to '||p_cc(i)||': '||p_subject);
      end loop;
    end if;

    if p_bcc is not empty then
      for i in 1 .. p_bcc.last loop
        utl_smtp.rcpt(l_mail_conn, p_bcc(i));
        do_debug('Sending to '||p_bcc(i)||': '||p_subject);
      end loop;
    end if;

    utl_smtp.open_data(l_mail_conn);

    if p_to is not empty then
      for i in 1 .. p_to.last loop
        utl_smtp.write_data(l_mail_conn, 'To: ' || p_to(i) || utl_tcp.crlf);
      end loop;
    end if;

    if p_cc is not empty then
      for i in 1 .. p_cc.last loop
        utl_smtp.write_data(l_mail_conn, 'CC: ' || p_cc(i) || utl_tcp.crlf);
      end loop;
    end if;

    if p_from_name is not null then
      utl_smtp.write_raw_data(l_mail_conn, format_text('From: =?UTF-8?B?' || encode_header_text(p_from_name) || '?= <' || l_from || '>' || utl_tcp.crlf));
    else
      utl_smtp.write_data(l_mail_conn, 'From: ' || l_from || utl_tcp.crlf);
    end if;

    utl_smtp.write_raw_data(l_mail_conn, format_text('Subject: =?UTF-8?B?' || encode_header_text(p_subject) || '?=' || utl_tcp.crlf));
    utl_smtp.write_data(l_mail_conn, 'Reply-To: ' || l_from || utl_tcp.crlf);
    utl_smtp.write_data(l_mail_conn, 'MIME-Version: 1.0' || utl_tcp.crlf);
    utl_smtp.write_data(l_mail_conn, 'Content-Type: multipart/mixed; boundary="' || l_boundary || '"' || utl_tcp.crlf || utl_tcp.crlf);
    utl_smtp.write_data(l_mail_conn, '--' || l_boundary || utl_tcp.crlf);
    utl_smtp.write_data(l_mail_conn, 'Content-Type: '||nvl(p_content_type, 'text/plain')||'; charset="'||g_charset||'"' || utl_tcp.crlf || utl_tcp.crlf);

    -- message body
    write_text_data(l_mail_conn, p_message);

    -- attachments
    if p_attachments is not empty then
      for i in 1 .. p_attachments.last loop
        utl_smtp.write_data(l_mail_conn, '--' || l_boundary || utl_tcp.crlf);

        if p_attachments(i).l_type = 'TEXT' then
          utl_smtp.write_data(l_mail_conn, 'Content-Type: ' || p_attachments(i).l_mime || '; name="' || p_attachments(i).l_name || '"' || utl_tcp.crlf);
          utl_smtp.write_data(l_mail_conn, 'Content-Disposition: attachment; filename="' || p_attachments(i).l_name || '"' || utl_tcp.crlf || utl_tcp.crlf);

          write_text_data(l_mail_conn, p_attachments(i).l_text);

        elsif p_attachments(i).l_type = 'BINARY' then

          utl_smtp.write_data(l_mail_conn, 'Content-Type: ' || p_attachments(i).l_mime || utl_tcp.crlf);
          utl_smtp.write_data(l_mail_conn, 'Content-Disposition: attachment; filename="' || p_attachments(i).l_name || '"' || utl_tcp.crlf);
          utl_smtp.write_data(l_mail_conn, 'Content-Transfer-Encoding: base64' || utl_tcp.crlf);
          utl_smtp.write_data(l_mail_conn, utl_tcp.crlf);

          write_binary_data(l_mail_conn, p_attachments(i).l_binary);

        else
          raise program_error;

        end if;
      end loop;
    end if;

    utl_smtp.write_data(l_mail_conn, '--' || l_boundary || '--' || utl_tcp.crlf);
    utl_smtp.close_data(l_mail_conn);
    utl_smtp.quit(l_mail_conn);

  exception
    when others then
      log_error(sqlerrm);
      begin
        utl_smtp.quit(l_mail_conn);
      exception when others then
        null; -- connection was not open, keep the original error
      end;
      raise;
  end do_send;


  procedure write_text_data(
    p_connection in out nocopy utl_smtp.connection,
    p_data       in clob
  ) is
    l_raw_data  raw(2000);
    l_buff_size pls_integer;
    l_index     pls_integer;
  begin

    -- chunck clob up into 1000 character pieces convert to raw
    l_index     := 0;
    l_buff_size := 1000;

    loop
      l_raw_data := format_text(dbms_lob.substr(p_data, l_buff_size, 1 + (l_index * l_buff_size)));
      exit when l_raw_data is null;
      utl_smtp.write_raw_data(p_connection, l_raw_data);
      l_index := l_index + 1;
    end loop;

    utl_smtp.write_data(p_connection, utl_tcp.crlf || utl_tcp.crlf);

  end write_text_data;


  procedure write_binary_data(
    p_connection in out nocopy utl_smtp.connection,
    p_data       in blob
  ) is
    l_raw_data  raw(2000);
    l_buff_size pls_integer;
    l_index     pls_integer;
    l_len       pls_integer;
  begin

    -- chunck blob up into 57-byte pieces and base64 encode
    l_index     := 1;
    l_buff_size := 57;
    l_len       := dbms_lob.getlength(p_data);

    while l_index < l_len loop
      dbms_lob.read(p_data, l_buff_size, l_index, l_raw_data);
      utl_smtp.write_raw_data(p_connection, utl_encode.base64_encode(l_raw_data));
      utl_smtp.write_data(p_connection, utl_tcp.crlf);
      l_index := l_index + l_buff_size;
    end loop;

    utl_smtp.write_data(p_connection, utl_tcp.crlf);

  end write_binary_data;


  function encode_header_text(
    p_text in varchar2
  ) return varchar2 is
  begin
    -- utf-8 Base64 without line breaks, for MIME encoded header values
    if p_text is null then
      return null;
    end if;

    return replace(replace(utl_encode.text_encode(p_text, 'UTF8', utl_encode.base64), chr(10)), chr(13));

  end encode_header_text;


  function request_lock(
    p_lock_name in varchar2
  ) return varchar2 is
    l_lock_handle varchar2(128);
    l_status      pls_integer;
  begin
    -- NOTE: allocate_unique does commit
    dbms_lock.allocate_unique(p_lock_name, l_lock_handle);

    l_status := dbms_lock.request(l_lock_handle, dbms_lock.x_mode);

    -- 0 = success, 4 = already own the lock
    if l_status not in (0, 4) then
      raise program_error;
    end if;

    return l_lock_handle;

  end request_lock;


  procedure release_lock(
    p_lock_handle in varchar2
  ) is
    l_status pls_integer;
  begin
    if p_lock_handle is null then
      return;
    end if;

    l_status := dbms_lock.release(p_lock_handle);

    -- 0 = success, 4 = do not own the lock
    if l_status not in (0, 4) then
      raise program_error;
    end if;

  end release_lock;


  procedure log_info(
    p_text in varchar2
  ) is
  begin
    dbms_output.put_line('EMAIL_PKG: ' || p_text);

    -- Implement logging according to your system
  end log_info;


  procedure log_error(
    p_text in varchar2
  ) is
  begin
    dbms_output.put_line('EMAIL_PKG ERROR: ' || p_text);

    -- Implement logging according to your system
  end log_error;


  procedure do_debug(
    p_text in varchar2
  ) is
  begin
    if g_debug then
      dbms_output.put_line('EMAIL_PKG: ' || p_text);
    end if;

    -- Implement debugging according to your system
  end do_debug;


end email_pkg;
/
