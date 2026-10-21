# Notes — Key Decisions

This document explains the decisions behind the solution: what changed, why, and what it cost or
gained. The full working plan, including how the work was split into shippable steps, is in
[docs/PLAN.md](docs/PLAN.md).

## Running it

Setup and every command are in the [README](README.md#running-it). In short:

```bash
bundle install
bin/rails db:create db:migrate db:seed
bin/rails tracking_events:import   # inventory, then prices; alerts are reconciled along the way
bin/rails server
```

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
the original `tracking_events.csv` can still import it unchanged. `tracking_events:import` contains
no logic of its own; it just runs the per-type import tasks.

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
  then order and preload it freely. About 1.5 ms per page on the data. The pages sort these rows by
  store address or product name, so `includes` joins the store or product rather than preloading
  it separately. That's one query instead of two, and Rails chooses it because the order
  references the joined table.
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

### Alert system (Objective 2)

"Two no-inventory events in a row" has a few readings, so I pinned it down against the data:

| Reading | Alerts on the CSV |
|---|---:|
| One alert per consecutive pair of misses (3 misses → 2 alerts) | 36,868 |
| **One alert per out-of-stock streak (chosen)** | **29,978** |

- **One alert per streak.** A brand needs one actionable alert per stockout, not one per extra
  missed check. The alert is raised by the 2nd consecutive miss, its miss count grows while the
  streak continues, and it resolves at the first in-stock check after the streak.
- **Order is `(event_time, id)`.** Events are date-only and arrive out of order, so ids aren't in
  time order. 15,384 of the 29,978 alerts have a first miss with a *higher* id than the second.
  Same-day checks fall back to CSV order.
- **Alerts are derived, then reconciled.** A late check can start, extend, resolve, split, or move
  the start of a streak anywhere in its timeline, so patching alerts check by check would be
  fragile. `InventoryAlerts::Reconciler` recomputes the alerts the checks imply and makes the table
  match: it inserts new alerts, updates changed ones, and deletes ones the checks no longer
  support. It writes only what differs, so running it twice changes nothing.
  - **Built from ActiveRecord relations.** Each step of finding streaks is a small relation:
    1. the timeline, where `LAG` marks run starts
    2. numbered checks, where a running count numbers the runs
    3. runs, where `ARRAY_AGG(... ORDER BY event_time, id)` picks each run's first two checks
    4. runs with their successor, where `LEAD` finds the restock
    5. streaks

    Each is nested in the next with `from(relation, :inventory_checks)`. Keeping the model's table
    name as the alias lets `group`, `where(in_stock: false, check_count: 2..)` and
    `joins(:product)` work as usual. The only SQL left is the expressions ActiveRecord can't build:
    window functions, `FILTER` and ordered `ARRAY_AGG`. The reconciler compares the streaks with
    the stored alerts in Ruby and writes the difference with `insert_all`, `upsert_all` and a
    scoped `delete_all`. The created, updated and deleted counts are simply the sizes of those
    sets.
  - **Scoped to the file.** The inventory import reconciles every store/product pair the file
    names, inside the import's transaction, so a failed import leaves alerts as they were too.
    After any import, alerts match the checks for those pairs. That includes a re-run where every
    row is a duplicate, so re-importing a file also repairs alerts that are missing or out of date
    for checks already stored. Pairs the file doesn't name are left alone.
    `bin/rails inventory_alerts:reconcile` rebuilds every pair. Alerts stay accurate across
    separate imports of partial data: a miss in one file and the next day's miss in another raise
    one alert, and a later file can resolve it or move its start.
  - **Memory: kept simple, with a known remedy.** The set of pairs a file names is small, because
    it's capped by stores × products rather than by rows: 22,826 pairs, about 1.8 MB, for the
    1M-row file. What costs memory is the reconcile. It holds the desired and stored alerts for
    those pairs in Ruby to compare them (about 23 MB each for 30k alerts, about 770 bytes per
    alert). A re-import of the full file therefore peaks at about 220 MB, against about 125 MB
    when only new pairs were reconciled. That matches what a first import already used, so the
    worst case doesn't rise. I kept it this way for simplicity. If memory became a constraint, the
    remedy is to reconcile one store's pairs at a time inside the same transaction. That holds
    roughly 300 alerts at once instead of 30,000, gives identical results, and costs about 100
    smaller queries instead of a few large ones.
  - **A planner pitfall found by `EXPLAIN`.** An early version wrote the scope as one bound
    `every_pair OR pair IN (...)` condition, which stopped Postgres from using the index: a
    one-pair reconcile scanned all 960k checks (90 ms against 0.5 ms). Now a full rebuild starts
    from `InventoryCheck.all`, and a scoped one joins the checks to the unnested list of pairs. A
    test asserts that the index plan is used.

**How much of the reconciler can be ActiveRecord?** I first wrote it as one SQL statement (a
multi-CTE query that also did the upsert and delete). I then moved it to ActiveRecord in two
passes, measuring each design on the full data. Every design produced identical alerts:

| Design | Full no-op | Import path (22,826 pairs) | One pair |
|---|---:|---:|---:|
| One SQL statement (detect + upsert + delete) | 1.5 s | 1.4 s | 3–6 ms |
| SQL detection query + ActiveRecord writes | 2.0 s | 2.1 s | 5–6 ms |
| **ActiveRecord relations for detection + ActiveRecord writes (chosen)** | **2.0 s** | **2.1 s** | **7 ms** |
| Detection scoped with a tuple `where` | 2.1 s | 83–91 s | 2–3 ms |
| Plain ActiveRecord reads, streaks found in Ruby | 6.2 s | 86–97 s | 1 ms |

- **Each query step is a relation; SQL is limited to single expressions.** ActiveRecord has no API
  for window functions, `FILTER` or ordered aggregates, so those stay as `select` fragments. Arel
  has `.over`, but it's semi-internal and harder to read than the SQL it would build.
  Everything around them (`FROM`, `GROUP BY`, `WHERE`, the join to products, `pluck`) is
  ActiveRecord.
- **Rails 7.1's tuple `where([:store_id, :product_id] => pairs)` expands to one `OR` term per
  pair.** Postgres can't serve that from an index, so an import's 22,826 pairs took over 80 s.
  The scope is a join to an unnested array of pairs instead. Stored alerts are read by store and
  narrowed to the listed pairs in Ruby.
- **The writes are ActiveRecord.** That removed the hand-written upsert, its nine-column change
  check, timestamps set by hand, and counting through `RETURNING xmax = 0`, a Postgres
  implementation detail.
- **The cost of the ActiveRecord version:**
  - about 0.6 s per full reconcile (2% of an import)
  - three statements in one transaction instead of one statement
  - loading the affected alerts into Ruby, up to 30k small rows on a full rebuild

- **Each alert is addressed to the brand.** `brand_id` is stored on the alert, so per-brand
  listings and counts read one table. The reconciler re-derives it, so a product that changes
  brand is followed on the next reconcile of its pairs.
- **Database rules.** A streak's first check is unique (one alert per streak). `CHECK (miss_count
  >= 2)` holds, and a resolution time and resolving check must be set together. The foreign keys
  to the triggering and resolving checks, and to the product, have no indexes of their own. Checks
  and products are never deleted (deletes are restricted), and alerts are rebuildable, so those
  indexes would only slow the writes.
- **Pages.**
  - An alerts index, newest first, with brand and status filters.
  - An alert page that lists the streak's checks, so a reader can see why the alert exists.
  - Open-alert counts on the brand pages, linking to the filtered index.
  - No notifications: the brief asks only for basic index and show pages, and brands have no
    contact details.

**Verification.**
- An independent Ruby script, sharing no code with the reconciler, derives every alert from the
  raw CSV. Its output is identical alert by alert to the database's, down to the dates and miss
  counts: 29,978 alerts, 849 open.
- The reconciler's tests caught every deliberate mutation tried. Twenty were made to the original SQL,
  for example `MIN(id)` instead of timeline order, dropping the `id` tie-break, or partitioning by
  store only. After the move to ActiveRecord, I mutated the new code again: 4 changes to the write
  path and 10 to the relations (for example `MIN(id)`, no `id` tie-break, `LEAD` across pairs, a
  3-miss threshold, scope ignored). One write-path mutation survived at first, stored alerts not
  narrowed to the listed pairs, so I added a test for it.
- On the full data, importing a single late in-stock check dated between an alert's two misses
  deleted exactly that alert. Removing the check and rebuilding restored it.

## Assumptions

- `event_time` is date-granular. Checks are stored at midnight UTC and displayed as dates.
- Rows that are identical in every column (store, product, date and result) are duplicate
  submissions.
- Same-day rows with different results are ordered by CSV order (`id`). The later row is the newer
  check.
- A product name is unique across brands, because the CSV identifies products by name alone.
- Prices are in a single currency (USD) and, like inventory, recorded per day.
- "Two no-inventory events in a row" means two consecutive checks in a store/product timeline
  ordered by `event_time` (then CSV order for the same day). Alerts are raised per streak and stay
  in the system once resolved, as history.
- Imports aren't expected to run concurrently. Two imports touching the same pairs at once would
  each reconcile correctly, but the last writer wins on derived values. A per-pair advisory lock
  would close that.

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

**With alerts (Step 3).** Fresh database, `tracking_events:import`, the same method as above:

| Operation | Result |
|---|---|
| `tracking_events:import` | 36–41 s, including the alert reconcile: 960,511 + 98,022 checks, **29,978 alerts (849 open)** |
| Re-run | 29 s · 0 inserted · every pair in the file re-checked · alerts created=0 updated=0 deleted=0 |
| `inventory_alerts:reconcile` (full rebuild, nothing to change) | 2.5 s |
| One-pair reconcile | ~5 ms (index scans on both tables) |
| `/inventory_alerts` | 21 ms · 6 queries · 30 KB |
| `/inventory_alerts?brand_id=…&status=open` | 9 ms · 6 queries |
| `/inventory_alerts/:id` | 6–15 ms · 5 queries |
| `/brands` (with open-alert counts) | 10–26 ms · 3 queries |


## How it was tested

- **Minitest and fixtures**, the project's own stack. The suite covers models, database constraints
  (asserted directly, because `insert_all` skips validations), importers, rake tasks, the
  reconciler, helpers, and every page.
- **Page tests cap the SQL queries per request.** Each limit was checked by putting the N+1 back and
  watching the test fail.
- **Mutation checks.** Key tests were confirmed to fail when the code under them is broken on
  purpose (see the alert system's Verification).
- **Full-data acceptance at each step.** On a fresh database with the real CSV, the expected counts
  were checked (960,511 checks, 39,489 duplicates, 29,978 alerts with 849 open), along with
  idempotent re-imports and page timings.
- **An independent oracle.** A separate script derives every alert from the raw CSV and is compared
  with the database alert by alert.
- **An independent code review before submission.** It found edge cases, each now fixed with a test
  that fails without the fix:
  - dates in other ISO 8601 forms being accepted
  - storage that depended on the app's time zone
  - repeated or string pairs passed to the reconciler
  - `?page[]=2` returning a 500
  - a malformed CSV ending in a backtrace

## How I worked

I planned before building: [docs/PLAN.md](docs/PLAN.md) records the baseline, the data profile, the
decisions with their alternatives, and the questions I settled up front. The work shipped in four
reviewed steps: foundation; rename, integrity and performance; price tracking; alerts. Each ended
with tests green and the app working on the full data. I used Claude Code (AI is allowed for this
assignment) to implement parts in parallel. I reviewed every change, measured it on the full
dataset, and sent work back when it fell short. One example: the reconciler went from a single SQL
statement to ActiveRecord relations after a review.

## Trade-offs and what I'd do next

**Trade-offs I chose deliberately**

- **Exact-duplicate rows are dropped.** This assumes a repeated, identical row for the same day is a
  duplicate submission. If the source could legitimately record two identical checks on one day,
  the unique index would need a time or a source row number instead. The data has 372
  store/product/days where a result returns after changing (for example miss, restock, miss). The
  later repeat is dropped, which can move where a streak resolves.
- **`insert_all` over `COPY`.** It's idiomatic and reports rejections per row, at about 2x the import
  time `COPY` would likely take.
- **Grouped counts over counter caches.** There's no denormalized state to keep correct after bulk
  inserts, at roughly 30–40 ms for index pages over 960k rows.
- **`brand_id` stored on alerts.** Per-brand listings and counts read one table. The reconciler
  re-derives it, so a product that changes brand is corrected on the next reconcile of its pairs.
- **Derived, reconciled alerts.** They're always consistent with the checks, including late and
  out-of-order data, at the cost of recomputing each touched timeline (about 2 s for every pair).
  Resolved alerts are kept as history; there's no acknowledge workflow.
- **ActiveRecord over one SQL statement for the reconciler.** It's clearer and uses the
  framework's writes, for about 0.6 s more per full reconcile.
- **OFFSET pagination.** It's simple and fast at this size (deep pages take about 10–40 ms).

**What I'd do next**

- **Run imports as background jobs** with a per-pair advisory lock in the reconciler, so concurrent
  imports can't race on derived alerts.
- **Notify brands** with one digest per brand per import rather than one email per alert. A backfill
  would otherwise send 30k emails.
- **Keyset pagination** if per-store histories grow far beyond 10k checks.
- **Targeted indexes as data grows:**
  - `(product_id, store_id, event_time DESC, id DESC) INCLUDE (price_cents)` for current prices
  - a partial index on open alerts
  - `(store_id, product_id, event_time, id) INCLUDE (inventory_present)` for scoped reconciles
- **A `COPY`-based path in `CsvCheckImporter`**, which would speed up both importers at once.
- **Tooling.** CI with Postgres, RuboCop (`rubocop-rails-omakase`), Bullet in test, and a
  `perf:report` task that reproduces the tables above.
