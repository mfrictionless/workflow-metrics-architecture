-- One current row per person_id: collapses raw_persons to its latest _cdc_ts
-- version, dropping Raw's CDC/sink metadata columns. See
-- design/Milestones.md M3.2.
with deduped as (
    {{ dedup_latest(source('raw', 'persons'), partition_by='person_id') }}
)

select
    person_id,
    display_name,
    email,
    ssn_last4
from deduped
