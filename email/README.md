# EMAIL_PKG

Utilities for sending and validating emails via `UTL_SMTP`, supporting queued (asynchronous) and synchronous sending, STARTTLS, SMTP authentication, and text/binary attachments.

## Prerequisites

- Network ACL granting connect access to the SMTP server.
- Oracle Wallet with the SMTP server certificate (if `g_use_tls = true`).
- Execute privileges on `UTL_SMTP`, `UTL_TCP`, and `DBMS_LOCK`.
- `CREATE JOB` privilege for `EMAIL_QUEUE_JOB`.

## Installation

1. Configure `g_helo_client` and the SMTP/wallet settings in `packages/email_pkg.sql` (`do_send`).
2. Optionally customize `log_info`, `log_error`, and `do_debug` in `packages/email_pkg.sql`.
3. Run `install.sql` in SQL*Plus or SQLcl:
   ```sql
   @install.sql
   ```

## Usage

```sql
begin
  email_pkg.send_mail(
    p_from    => null, -- uses default sender
    p_to      => 'user@example.com',
    p_subject => 'Hello',
    p_message => 'Test message'
  );
end;
/
```
