-- One current row per file_id: collapses raw_files (append-only; a WIP
-- insert then a CLOSED update land as two rows, M2.8) to its latest _cdc_ts
-- version, dropping Raw's CDC/sink metadata columns. See
-- design/Milestones.md M3.2.
with deduped as (
    {{ dedup_latest(source('raw', 'files'), partition_by='file_id') }}
)

select
    file_id,
    file_number,
    status,
    opened_at,
    closed_at,
    county_fips,
    product_type
from deduped
