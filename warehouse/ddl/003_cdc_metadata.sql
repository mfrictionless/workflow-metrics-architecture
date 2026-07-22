ALTER TABLE raw_files ADD COLUMN _cdc_source_lsn bigint;
ALTER TABLE raw_files ADD COLUMN _cdc_topic_offset bigint;

ALTER TABLE raw_persons ADD COLUMN _cdc_source_lsn bigint;
ALTER TABLE raw_persons ADD COLUMN _cdc_topic_offset bigint;

ALTER TABLE raw_users ADD COLUMN _cdc_source_lsn bigint;
ALTER TABLE raw_users ADD COLUMN _cdc_topic_offset bigint;

ALTER TABLE raw_file_actions ADD COLUMN _cdc_source_lsn bigint;
ALTER TABLE raw_file_actions ADD COLUMN _cdc_topic_offset bigint;

ALTER TABLE raw_parties ADD COLUMN _cdc_source_lsn bigint;
ALTER TABLE raw_parties ADD COLUMN _cdc_topic_offset bigint;

ALTER TABLE raw_audit_events ADD COLUMN _cdc_source_lsn bigint;
ALTER TABLE raw_audit_events ADD COLUMN _cdc_topic_offset bigint;