create or replace type email_attachment_type as object (
  l_type   varchar2(6), -- TEXT / BINARY
  l_name   varchar2(200),
  l_mime   varchar2(80),
  l_text   clob,
  l_binary blob
);
/
