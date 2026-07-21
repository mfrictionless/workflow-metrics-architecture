-- One current row per user_id: collapses raw_users
-- to its latest _cdc_ts
-- version, dropping Raw's CDC/sink metadata columns. See
-- design/Milestones.md M3.2.
with deduped as (
    {{ dedup_latest(source('raw', 'users'), partition_by='user_id') }}
)

select
    user_id,
    person_id,
    team_name,
    is_external_vendor_flag
from deduped
