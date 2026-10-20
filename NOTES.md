# Notes — Key Decisions

This document explains the decisions behind the solution: what changed, why, and what it cost or
gained. The full working plan, including how the work was split into shippable steps, is in
[docs/PLAN.md](docs/PLAN.md).

## Running it

_To be completed in the final step._

## What I found in the starting point

### Data (`tracking_events.csv`)

- 1,000,000 rows, 101 stores and 226 products, all matching `db/seeds.rb` exactly.
- Dates are **date-only** (2024-12-05 to 2025-12-05), stored as midnight UTC.
- `Inventory Present` is only ever `True` (800,209) or `False` (199,791).
- **39,489 rows are exact duplicates** of an earlier row (same store, product, date and value), and
  18,062 store/product/days contain both `True` and `False`.
- Rows are not sorted by date, so events arrive out of `event_time` order.

### Code

- The importer did two lookups and a separate transaction for every row. It read the CSV in the
  process's default encoding (and crashed when `LANG` was unset), treated any unrecognized boolean
  as `false` (which would invent stockouts), skipped unknown rows silently, and duplicated all
  data on a re-run.
- The schema had no `NOT NULL` on core columns, no uniqueness on the importer's lookup keys, and
  no composite indexes for the store/product/time access paths.
- The pages had N+1 queries and unbounded lists.
- Seeds couldn't be re-run once products or events existed.
- The test fixtures were placeholders that violated `NOT NULL` foreign keys.
- The Gemfile required Ruby 3.2.9 while the README said 3.2.2. The Gemfile now accepts
  `~> 3.2.2`.

## Baseline performance

Measured before any changes: Apple Silicon, Ruby 3.2.9, PostgreSQL 15.17, development mode,
second (warm) request.

| Operation | Time | Queries | HTML |
|---|---:|---:|---:|
| Import 1M rows | 24 min 07 s | ~5M | — |
| `/stores` | 108 ms | 102 | 17 KB |
| `/stores/1` | 3,238 ms | 20,105 | 1.8 MB |
| `/products` | 199 ms | 453 | 40 KB |
| `/products/1` | 497 ms | 4,414 | 577 KB |
| `/brands` | 14 ms | 46 | 8 KB |
| `/brands/1` | 7 ms | 8 | 3 KB |

## Decisions

_Filled in step by step as each part ships. See [docs/PLAN.md §3](docs/PLAN.md) for the full list._

## Assumptions

_Filled in step by step._

## Results

_After-measurements are added at the end of each step._

## Trade-offs and what I'd do next

_To be completed in the final step._
