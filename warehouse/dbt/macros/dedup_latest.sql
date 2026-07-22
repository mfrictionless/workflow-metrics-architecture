{#
  Collapses an append-only Raw relation to exactly one row per business key,
  keeping the row with the highest order_by (default _cdc_source_lsn desc,
  _cdc_topic_offset desc) for each key. order_by must be a complete ORDER BY
  expression, direction included per column -- the macro does not append its
  own `desc`, since that only binds to the last column in a comma-separated
  list and silently leaves earlier columns at their ASC default. Defends
  against at-least-once Kafka redelivery (byte-for-byte duplicates) and
  multiple versions per key (a Raw INSERT then UPDATE landing as two rows,
  per M2.8) -- not against out-of-order arrival, which does not occur here
  since Debezium/Kafka preserve per-key ordering. See design/Milestones.md
  M3.2 and design/Decisions.md D017.
#}
{% macro dedup_latest(relation, partition_by, order_by='_cdc_source_lsn desc, _cdc_topic_offset desc') %}
select *
from (
    select
        *,
        row_number() over (
            partition by {{ partition_by }}
            order by {{ order_by }}
        ) as _dedup_rank
    from {{ relation }}
) _ranked
where _dedup_rank = 1
{% endmacro %}
