create table email_queue (
  id            number generated always as identity primary key,
  created       timestamp,
  from_address  varchar2(4000),
  from_name     varchar2(4000),
  to_addresses  email_addresses_type,
  cc_addresses  email_addresses_type,
  bcc_addresses email_addresses_type,
  subject       varchar2(4000),
  message       clob,
  content_type  varchar2(4000),
  attachments   email_attachments_type
)
nested table to_addresses  store as email_queue_to_tab,
nested table cc_addresses  store as email_queue_cc_tab,
nested table bcc_addresses store as email_queue_bcc_tab,
nested table attachments   store as email_queue_attachments_tab
/
