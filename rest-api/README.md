# REST_API_PKG

Wrapper package around `UTL_HTTP` for calling HTTP/HTTPS REST services with both `CLOB` and `VARCHAR2` (short) payloads/responses.

## Prerequisites

- Network ACL granting connect access to target servers.
- Execute privilege on `UTL_HTTP`.
- Oracle Wallet with server certificates for HTTPS endpoints.

## Setup

1. Configure `set_wallet` in `rest_api_pkg.sql` with your Oracle Wallet path and password (for HTTPS).
2. Optionally customize `do_debug` and `log_error` in `rest_api_pkg.sql` for your logging framework.
3. Compile `rest_api_pkg.sql`.

> **Note:** HTTP 4xx/5xx responses do not raise exceptions (`utl_http.set_response_error_check(false)`); inspect `l_status_code` on the returned response record.
