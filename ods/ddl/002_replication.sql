-- Enables Debezium CDC capture on the ODS (M2.1). wal_level=logical is set
-- via a command-line override on the ods-postgres service in
-- docker-compose.yml -- it's a postmaster-context setting, only applied at
-- server start, so it can't be set from SQL here.
--
-- This creates the publication and logical replication slot Debezium's
-- Postgres connector (M2.3) will consume. Named after their consumer, per
-- common Debezium convention.

CREATE PUBLICATION dbz_publication FOR TABLE files, file_actions, persons, users, parties, audit_events;
 
SELECT pg_create_logical_replication_slot('dbz_slot', 'pgoutput');