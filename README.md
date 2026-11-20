# Oracle-Artisan

A collection of standalone, production-tested Oracle PL/SQL utilities and solutions. Each folder is self-contained so you can pick and install only what you need.

## Solutions

| Solution | Description |
| --- | --- |
| [ad-ldap](ad-ldap/) | Active Directory (LDAP) lookup utilities (`AD_PKG`). |
| [audit-ddl](audit-ddl/) | Database-wide DDL audit logging with tamper protection (`AUDIT_DDL`, `AUDIT_DDL_TRG`). |
| [db-data-sync](db-data-sync/) | Table-driven data synchronization from remote databases over DB links (`DB_DATA_SYNC_PKG`). |
| [db-instances](db-instances/) | Query sessions and run dynamic SQL across multiple databases via DB links (`DB_INSTANCES_PKG`). |
| [email](email/) | Queued and synchronous SMTP email sending with TLS, auth, and attachments (`EMAIL_PKG`). |
| [os-programs](os-programs/) | Execute Linux host scripts from PL/SQL via `DBMS_SCHEDULER` and capture output (`OS_PROGRAMS_PKG`). |
| [refcursor-utils](refcursor-utils/) | Utilities for wrapping `SYS_REFCURSOR` procedures and loading cursor rows into tables (`REFCURSOR_UTILS_PKG`). |
| [rest-api](rest-api/) | HTTP/HTTPS REST client wrapper around `UTL_HTTP` (`REST_API_PKG`). |
| [synchronized](synchronized/) | PL/SQL block-level locking using `DBMS_LOCK` (`SYNCHRONIZED_PKG`). |
| [time-utils](time-utils/) | Time formatting, date range overlap checks, and time zone conversion (`TIME_UTILS_PKG`). |

## Customization & Conventions

- **System-specific settings**: Search for `according to your system` in any solution to find configuration points (SMTP server, Oracle Wallet path, LDAP host, schema names, time zones, or host paths).
- **Logging & debugging**: Packages default to `DBMS_OUTPUT` with clearly marked `-- Implement logging/debugging according to your system` hooks so you can wire in your own logging framework (e.g. Logger, custom log table).
- **Oracle version**: Most packages work on Oracle 11g+, while `email` and `db-data-sync` use `GENERATED ALWAYS AS IDENTITY` columns (Oracle 12c+).

## License

[MIT](LICENSE)
