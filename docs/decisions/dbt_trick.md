# ADR — The Mart Aggregation Trick

## Context

When building entity marts in dbt, a common challenge arises: how do you bring
data from a different-grained concept onto an entity without changing the
entity's grain?

For example, a `developers` mart needs game-level data (reviews, playtime)
aggregated onto it — but each developer is associated with many games. Joining
games directly onto developers would fan out the rows and break the one-row-per-
developer grain.

## The Pattern

dbt's own `customers.sql` example demonstrates the solution: **aggregate the
foreign-grained data to match the entity's grain in an internal CTE, then join
the aggregated result back onto the entity.**

```sql
-- The grain never changes because the aggregation happens BEFORE the join.

-- 1. Import the entity
developers as (
    select distinct developer from {{ ref('int_games_developers_exploded') }}
),

-- 2. Aggregate a different-grained concept to match the entity's grain
developer_game_metrics as (
    select
        developer,
        count(distinct app_id) as num_games,
        sum(positive) as total_positive
    from {{ ref('int_games_developers_exploded') }}
    group by 1
),

-- 3. Join the aggregated data back onto the entity
developers_with_game_metrics as (
    select
        developers.developer,
        developer_game_metrics.num_games,
        developer_game_metrics.total_positive
    from developers
    left join developer_game_metrics
        on developers.developer = developer_game_metrics.developer
)
```

The key insight is that `GROUP BY` inside a CTE is not the same as `GROUP BY`
as the mart's output. The CTE reshapes foreign data to fit the entity. The
mart's final grain stays fixed.

## When It Applies

This pattern is the answer to "should this be its own entity mart?" An entity
earns mart status not only when it has independent attributes, but also when
other concepts carry data about it that becomes meaningful when aggregated to
its grain. `developers` has no attributes beyond a name — but games carry
review data that, when aggregated per developer, produces `num_games`,
`total_reviews`, and `avg_approval_pct`. That aggregated view is valuable
enough to materialise as its own entity.

## Status

Accepted — 2026-04-16
