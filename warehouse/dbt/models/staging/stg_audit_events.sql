WITH deduped AS (
    {{ dedup_latest(source('raw', 'audit_events'), partition_by='audit_event_id') }}
)

SELECT
    audit_event_id,
    file_id,
    user_id,
    event_type,
    description,
    created_at
FROM deduped
