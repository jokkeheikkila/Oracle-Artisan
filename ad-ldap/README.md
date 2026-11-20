# AD_PKG (Active Directory / LDAP)

PL/SQL package for querying Active Directory over LDAP using `DBMS_LDAP`.

## Prerequisites

- Network ACL granting connect access to the LDAP server.
- Execute privilege on `DBMS_LDAP`.

## Setup

1. Implement the `initialize` procedure in `ad_pkg.sql` to populate `g_host`, `g_port`, `g_user`, `g_pwd`, and `g_base` according to your environment.
2. Optionally customize `do_debug` and `log_error` in `ad_pkg.sql` for your logging framework.
3. Compile `ad_pkg.sql`.
