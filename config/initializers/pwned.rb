# Bound the HIBP range request (#674): Net::HTTP's defaults are 60s open +
# 60s read, and anywhere the check runs inside a write transaction that
# becomes an app-wide write stall on SQLite's database-wide lock. The check
# fails open on Pwned::Error, so tight timeouts cost nothing but the check.
Pwned.default_request_options = { open_timeout: 1, read_timeout: 2 }
