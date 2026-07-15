-- One current row per file_action_id: collapses raw_file_actions
-- (append-only; a sent-only insert then a received update land as two rows,
-- M2.8) to its latest _cdc_ts version, dropping Raw's CDC/sink metadata
-- columns. See design/Milestones.md M3.2.
with deduped as (
    {{ dedup_latest(source('raw', 'file_actions'), partition_by='file_action_id') }}
)

select
    file_action_id,
    file_id,
    action_code,
    action_type,
    sent_at,
    received_at,
    sent_user_id,
    received_user_id,
    live_flag
from deduped
