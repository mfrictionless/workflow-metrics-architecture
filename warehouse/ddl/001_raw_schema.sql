-- Raw schema — append-only landing for the JDBC sink connector (M2.5).
-- Mirrors the ODS business columns (see ods/ddl/001_schema.sql) plus 3
-- metadata columns that never come from the Kafka message itself, so they
-- can't be inferred by the sink connector's schema evolution: _cdc_op and
-- _cdc_ts are stamped onto the message by an SMT before it reaches the
-- sink (see cdc/debezium-jdbc-sink.json); _sink_ts is a Postgres-side
-- DEFAULT, since "when this row was written" is meaningless as a value
-- carried on the message itself. Hand-written rather than left to the
-- connector's schema.evolution -- see design/Decisions.md D011.
--
-- Deliberately no constraints (no FKs, no NOT NULL, no CHECK): Raw is a
-- faithful, append-only landing of whatever the source produced, per-topic,
-- independently ordered. The staging layer (M3.2) is where correctness
-- constraints and deduplication belong.

CREATE TABLE raw_files (
    file_id       bigint,
    file_number   varchar,
    status        varchar,
    opened_at     timestamptz,
    closed_at     timestamptz,
    county_fips   varchar,
    product_type  varchar,
    _cdc_op       varchar,
    _cdc_ts       bigint,
    _sink_ts      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE raw_file_actions (
    file_action_id    bigint,
    file_id           bigint,
    action_code       varchar,
    action_type       varchar,
    sent_at           timestamptz,
    received_at       timestamptz,
    sent_user_id      bigint,
    received_user_id  bigint,
    live_flag         boolean,
    _cdc_op           varchar,
    _cdc_ts           bigint,
    _sink_ts          timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE raw_parties (
    party_id  bigint,
    file_id   bigint,
    role      varchar,
    user_id   bigint,
    _cdc_op   varchar,
    _cdc_ts   bigint,
    _sink_ts  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE raw_audit_events (
    audit_event_id  bigint,
    file_id         bigint,
    user_id         bigint,
    event_type      varchar,
    description     text,
    created_at      timestamptz,
    _cdc_op         varchar,
    _cdc_ts         bigint,
    _sink_ts        timestamptz NOT NULL DEFAULT now()
);
