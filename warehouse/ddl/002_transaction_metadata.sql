-- Adds _cdc_txn_id to every Raw table (M2.6), so rows landed from the same
-- ODS transaction can be correlated across tables. This is this project's
-- real schema-evolution mechanism: docker-entrypoint-initdb.d runs each
-- numbered file once, in order, only on a fresh (empty) volume -- it never
-- re-runs 001_raw_schema.sql, so a real change is a new, additive file, not
-- an edit to 001. Mirrors the ods/ddl 001_schema.sql/002_replication.sql
-- precedent from M2.1. See design/Milestones.md M2.6 and
-- design/Decisions.md D012.
--
-- Two columns, not one -- confirmed empirically that they answer different
-- questions and neither alone is sufficient:
--   _cdc_txn_id        Debezium's transaction.id ("<txId>:<lsn>", a string).
--                       Demonstrates the transaction-metadata feature itself
--                       (ties to the BEGIN/END events on the ods.transaction
--                       topic), but the LSN suffix advances per WAL record,
--                       so it is NOT equal across rows in the same
--                       transaction -- only its leading txId segment is
--                       stable. Not directly comparable with `=`.
--   _cdc_source_txn_id  Debezium's source.txId, a plain integer. Present on
--                       every message regardless of provide.transaction.
--                       metadata; this is the actually-stable, directly
--                       `=`-comparable value for correlating rows across
--                       tables to one ODS transaction.
-- Neither comes from the ODS itself, so neither carries a FK/constraint
-- here, same as the other _cdc_* columns.

ALTER TABLE raw_files ADD COLUMN _cdc_txn_id varchar;
ALTER TABLE raw_files ADD COLUMN _cdc_source_txn_id bigint;

ALTER TABLE raw_file_actions ADD COLUMN _cdc_txn_id varchar;
ALTER TABLE raw_file_actions ADD COLUMN _cdc_source_txn_id bigint;

ALTER TABLE raw_parties ADD COLUMN _cdc_txn_id varchar;
ALTER TABLE raw_parties ADD COLUMN _cdc_source_txn_id bigint;

ALTER TABLE raw_audit_events ADD COLUMN _cdc_txn_id varchar;
ALTER TABLE raw_audit_events ADD COLUMN _cdc_source_txn_id bigint;
