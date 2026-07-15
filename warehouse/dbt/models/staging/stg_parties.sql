-- One current row per party_id: raw_parties is insert-only in this system
-- (no party mutation, M2.8), so this dedup only ever defends against
-- at-least-once redelivery, not multiple versions. See design/Milestones.md
-- M3.2.
with deduped as (
    {{ dedup_latest(source('raw', 'parties'), partition_by='party_id') }}
)

select
    party_id,
    file_id,
    role,
    user_id
from deduped
