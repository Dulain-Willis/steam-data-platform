# ADR — dbt Layer Architecture

## Context

The dbt style guide structures models into three layers: staging, intermediate,
and marts. This ADR records how those layers map to traditional dimensional
modelling concepts (facts and dimensions) and the conventions this project
follows.

## Decisions

### 1. Marts are wide, denormalized entity tables

A mart represents one business entity at its natural grain. It joins,
denormalises, casts, and computes row-level derived fields. Aggregation is
allowed inside internal CTEs to bring foreign-grained data onto the entity, as
long as the final output grain stays fixed (see `docs/decisions/dbt_trick.md`).

In Kimball terms, marts are pre-joined fact tables with all relevant dimension
attributes already baked in. Storage is cheap, so there is no reason to force
downstream consumers to join a dimension table — embed the data directly on the
entity.

### 2. A table earns mart status when it represents a meaningful entity

An entity mart is justified in two cases:

- The entity carries its own independent attributes (e.g. a developer with
  founding year, headquarters, employee count).
- Other concepts carry data about the entity that becomes meaningful when
  aggregated to its grain (e.g. games carry review data that, when aggregated
  per developer, produces `num_games`, `total_reviews`, `avg_approval_pct`).

The second case follows the same pattern as dbt's own `customers.sql` example,
where orders are aggregated to customer grain and joined back onto the customer
entity.

### 3. Intermediates are layer-agnostic plumbing

Intermediates exist to simplify marts. They can play any role:

- **Dimension-like**: exploding comma-separated fields into rows so they can be
  aggregated and joined back into an entity mart.
- **Re-graining**: fanning out or collapsing rows to the correct grain.
- **Isolating complex logic**: extracting difficult transformations so they can
  be tested in isolation.

### 4. Metrics layer for aggregations and reports

Any model that changes the grain through `GROUP BY`, filters to a subset with
`LIMIT`, or applies window functions like `row_number()` to produce a ranked
or filtered output is a metric, not a mart. Metrics always consume from marts.

### 5. Layer flow

Data flows forward through layers:

```
staging → intermediate → marts → metrics
```

## Status

Accepted — 2026-04-16
