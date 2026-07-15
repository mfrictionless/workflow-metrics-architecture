{#
  Collapses an append-only Raw relation to exactly one row per business key,
  keeping the highest-order_by row (default _cdc_ts) for each key. Defends
  against at-least-once Kafka redelivery (byte-for-byte duplicates) and
  multiple versions per key (a Raw INSERT then UPDATE landing as two rows,
  per M2.8) -- not against out-of-order arrival, which does not occur here
  since Debezium/Kafka preserve per-key ordering. See design/Milestones.md
  M3.2 and design/Decisions.md D017.
#}
{% macro dedup_latest(relation, partition_by, order_by='_cdc_ts') %}
select *
from (
    select
        *,
        row_number() over (
            partition by {{ partition_by }}
            order by {{ order_by }} desc
        ) as _dedup_rank
    from {{ relation }}
) _ranked
where _dedup_rank = 1
{% endmacro %}
