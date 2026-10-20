# Notes — Key Decisions

This document explains the decisions behind the solution: what changed, why, and what it cost or
gained. The full working plan, including how the work was split into shippable steps, is in
[docs/PLAN.md](docs/PLAN.md).

## Running it

_To be completed in the final step._

## What I found in the starting point

### Data (delivered as `tracking_events.csv`, now `inventory_checks.csv`)

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

The full list, with alternatives considered, is in [docs/PLAN.md §3](docs/PLAN.md).

### Naming: `TrackingEvent` → `InventoryCheck`

Price checks are a second, independent kind of check. The existing model only ever recorded whether
inventory was present, so I renamed it to say so. Each kind of check then gets its own table with
non-nullable columns, rather than one table with nullable, type-dependent ones. The documented
`bin/rails tracking_events:import` command still works.

### Data integrity lives in the database

- **Required and unique catalog keys.** `stores.address`, `products.name` and `brands.name` are
  `NOT NULL` and unique. The CSV identifies records by these values, so a lookup has to be
  unambiguous.
- **`inventory_present` is `NOT NULL` with no default.** Booleans usually get a default; here a
  default of `false` would silently turn a missing value into a stockout.
- **Exact duplicates are rejected by a unique index** on
  `(store_id, product_id, event_time, inventory_present)`. With date-only data, a repeated row is a
  duplicate submission, not a second check. Counting it twice would create false "two misses in a
  row" alerts. The index also makes re-imports idempotent. Rows for the same day with different
  results are both kept, ordered by `id` (CSV order).
- **Migrations never delete data.** On a database that already contains duplicates, the migration
  stops and points to `bin/rails inventory_checks:remove_duplicates`. That task can be previewed with
  `DRY_RUN=1` and keeps the earliest copy of each check. Deleting data is a deliberate operator
  step, not a side effect of `db:migrate`.
- **Models validate what the database enforces**, so form-style callers get errors instead of
  exceptions. `has_many` associations use `restrict_with_error`, so check history can't be deleted
  as a side effect.

### Indexes follow the access paths

- `(store_id, event_time)` and `(product_id, event_time)` serve the newest-first, paginated show
  pages. They are read as an index scan backward, about 0.1 ms per page.
- The unique `(store_id, product_id, event_time, inventory_present)` index serves each
  store/product timeline (the alert system) and duplicate rejection.
- The single-column `store_id` and `product_id` indexes were dropped. The composites' leading columns
  cover them, and every extra index slows the bulk insert.

### Import: preloaded lookups and batched `insert_all`

The old importer ran 5 SQL statements per row, about 5M in total. The new one:

1. Loads the 101 store and 226 product ids once.
2. Streams the CSV with explicit UTF-8.
3. Parses strictly. Only `True`/`False` are accepted, in any letter case. Unknown values are rejected
   and counted, never guessed as `false`.
4. Inserts in batches of 5,000 with `ON CONFLICT DO NOTHING` on the unique index.
5. Runs everything in one transaction, so a bad file leaves the table as it was.

The result reports rows read, inserted, duplicates and rejected, with sample rejection reasons.

**Considered and not chosen:** Postgres `COPY` into a staging table. It would probably be about 2x
faster, but it's mostly raw SQL and makes per-row rejection reporting harder. At 33 s for 1M rows,
`insert_all` is fast enough and stays idiomatic.

`inventory_checks:import` reads `inventory_checks.csv`, and falls back to `tracking_events.csv` if
that file doesn't exist. The repository's data file is now named `inventory_checks.csv`; anyone with
the original `tracking_events.csv` can still import it unchanged. `tracking_events:import` contains no logic of its own; it just runs the
per-type import tasks.

### Pages: paginate, eager-load, count with one grouped query

- **Show pages** list checks 50 per page, newest first (Pagy 9; Pagy 43 needs Ruby 3.3). They use
  `includes` for every association rendered.
- **Index pages** use one `GROUP BY` count instead of a `COUNT` per row.
- **Counter caches considered and not chosen.** `insert_all` bypasses the callbacks that maintain
  them, so the importer would have to recompute them. The grouped count is an index-only scan of
  about 30–40 ms over 960k rows.
- **Tests cap queries per page**, so an N+1 regression fails the build.

### Price tracking (Objective 1)

- **Its own table.** A price check is independent of an inventory check (either can happen without
  the other), so `price_checks` stands alone with non-nullable columns: store, product, date and
  `price_cents`.
- **Money as integer cents.** One currency (USD). A `CHECK (price_cents >= 0)` constraint keeps
  prices from going negative; zero is allowed. CSV prices like `4.99` are parsed through
  `BigDecimal`, never `Float`. Anything else (`$5`, `5,00`, `1.234`, `-1`, blank) is rejected with
  a reason.
- **Same duplicate rule as inventory.** Exact repeats are skipped by a unique index, so re-imports
  are idempotent. Different prices on the same day are all kept, and the later row is the current
  price. `4.9` and `4.90` are the same number of cents, so they count as a repeat.
- **One shared importer.** `CsvCheckImporter` holds the streaming, header check, batching,
  `insert_all`, transaction, counting and reporting. Each kind of check is a single declaration:
  model, row parser, unique index and file names. Adding a third kind of check is a few lines.
- **Current price per store and product** uses `DISTINCT ON (store_id, product_id) … ORDER BY
  event_time DESC, id DESC`. It's wrapped as a subquery so a page can scope it through its owner,
  then order and eager-load it freely. About 1.5 ms per page on the data.
- **Pages.**
  - The product page shows the current price at each store.
  - The store page shows the current price of each product. It isn't paginated, because the
    catalog bounds it at one row per product.
  - The price history is a nested resource (`/products/:id/price_checks`). The product page loads
    it lazily in a Turbo Frame, so the product page stays light and paging the history only
    reloads that frame. The history page also works on its own.
- **Sample data.** There's no real price data, so `price_checks:generate_sample` writes a
  reproducible `price_checks.csv` (fixed seed) from the seeded catalog. It has 100,000 rows and is
  8.2 MB:
  - a list price per product that changes 0–3 times over the year
  - a few percent of variation from store to store
  - 5% promotional prices
  - 2% exact duplicate rows and 1% same-day repricings, so duplicate skipping and the same-day
    tie-break are exercised

  It's committed so the documented import works with no extra step.

## Assumptions

- `event_time` is date-granular. Checks are stored at midnight UTC and displayed as dates.
- Rows that are identical in every column (store, product, date and result) are duplicate
  submissions.
- Same-day rows with different results are ordered by CSV order (`id`). The later row is the newer
  check.
- A product name is unique across brands, because the CSV identifies products by name alone.
- Prices are in a single currency (USD) and, like inventory, recorded per day.

## Results

Same machine and method as the baseline. The data is a freshly imported database (960,511 checks),
pages are the warm steady state, and the database is autovacuumed.

| Operation | Before | After |
|---|---:|---:|
| Import 1M rows | 24 min 07 s · ~5M queries | **33 s** · 134 MB peak memory |
| Re-run the import | duplicated every row | 28 s · 0 inserted |
| `/stores` | 108 ms · 102 queries · 17 KB | 39 ms · 2 queries · 14 KB |
| `/stores/1` | 3,238 ms · 20,105 queries · 1.8 MB | **11 ms · 5 queries · 16 KB** |
| `/products` | 199 ms · 453 queries · 40 KB | 44 ms · 3 queries · 39 KB |
| `/products/1` | 497 ms · 4,414 queries · 577 KB | 8 ms · 5 queries · 14 KB |
| `/brands` | 14 ms · 46 queries · 8 KB | 5 ms · 2 queries · 7 KB |
| `/brands/1` | 7 ms · 8 queries · 3 KB | 6 ms · 3 queries · 3 KB |

**Vacuum after the import.** Grouped counts and Pagy's totals become index-only scans once the
table's visibility map is up to date. Autovacuum takes care of this by itself: PostgreSQL 13+
triggers on inserts, and it ran 2 seconds after the 960k-row import. No explicit `VACUUM` step is
needed. A database cloned with `createdb -T` doesn't get this until it's vacuumed, which is why
early measurements on a clone were slower.

**With price tracking (Step 2).** Fresh database, both CSVs, the same method as above:

| Operation | Result |
|---|---|
| `tracking_events:import` (1M inventory rows + 100k price rows) | 38.6 s: 960,511 + 98,022 inserted · 39,489 + 1,978 duplicates · 0 rejected |
| Re-run | 32.5 s · 0 inserted |
| `/products/1` (current price by store, inventory checks) | 17 ms · 6 queries · 31 KB |
| `/products/1/price_checks` (lazy price history frame) | 9 ms · 4 queries · 12 KB |
| `/stores/1` (current price of every product, inventory checks) | 38 ms · 6 queries · 64 KB; database time ~2 ms, the rest is rendering ~220 rows |


## Trade-offs and what I'd do next

_To be completed in the final step._
