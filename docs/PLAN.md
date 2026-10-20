# Implementation Plan — Retail Inventory Tracking

This is the working plan for the Hetal take-home assignment. Each **step** ends in a shippable
product: migrations run, the test suite is green, every page renders on the full dataset, and the
documented commands work. Each step has one **serial** task (anything that changes the schema or
renames shared code) followed by **parallel** tasks with disjoint file ownership, so several
agents can work at once.

---

## 1. The assignment at a glance

| | |
|---|---|
| **Objective 1** | Price tracking. Inventory checks and price checks are separate and either can happen without the other. |
| **Objective 2** | Alert the brand when a store has two "no inventory" events in a row for the same product, ordered by `event_time`. Basic index and show pages only. |
| **Objective 3** | Improve overall performance, either alongside 1 and 2 or after them. |
| **Evaluated on** | Code quality and organization · database design decisions · performance optimizations · ability to explain thinking and decisions. |
| **Time expectation** | **2–3 hours.** Shows the problem-solving approach; perfection isn't expected. AI is allowed. |
| **Submit** | Repo link · brief notes on key decisions (`NOTES.md`) · instructions to run it. |
| **Ambiguity rule** | "Make reasonable assumptions … document them in your code or a separate notes file." |

What this means for us: reviewers grade judgment and explanation as much as code. Every decision
below has a reason, and those reasons go into `NOTES.md`. Scope stays tight. Extras are deferred
(§9) until all three objectives ship.

---

## 2. Baseline (measured 2026-10-20, before any changes)

Environment: Apple Silicon, Ruby 3.2.9, PostgreSQL 15.17, Rails development mode. Pages were
warmed once and measured on the second request.

### 2.1 Import

| Metric | Value |
|---|---|
| `bin/rails tracking_events:import` (1,000,000 rows) | **24 min 07 s** |
| SQL per row | 5 (store lookup, product lookup, BEGIN, INSERT, COMMIT) ≈ **5M statements** |
| `log/development.log` growth | ~170 MB |

### 2.2 Pages (full dataset)

| Path | Time | Queries | HTML |
|---|---:|---:|---:|
| `/stores` | 108 ms | 102 | 17 KB |
| `/stores/1` | **3,238 ms** | **20,105** | **1.8 MB** |
| `/products` | 199 ms | 453 | 40 KB |
| `/products/1` | 497 ms | 4,414 | 577 KB |
| `/brands` | 14 ms | 46 | 8 KB |
| `/brands/1` | 7 ms | 8 | 3 KB |

### 2.3 Data profile of `tracking_events.csv`

- 1,000,000 rows. 101 distinct addresses and 226 distinct product names, all matching `db/seeds.rb`
  exactly. No blanks or stray whitespace.
- `Date` is **date-only** ISO (`2024-12-05` … `2025-12-05`, 366 distinct days). The existing importer
  stores it as midnight UTC in a `datetime` column.
- `Inventory Present` is only ever `True` (800,209) or `False` (199,791).
- 22,826 store/product pairs, with 15–71 events each (average 43.8).
- **55,308 store/product/date groups have 2–5 rows.** 39,489 of those rows are exact duplicates,
  and 18,062 groups mix `True` and `False` on the same day.
- The file is not sorted by date, so events arrive out of order relative to `event_time`.

### 2.4 Defects and gaps found in the existing code

1. **Importer:** two lookups plus a transaction per row. It reads the CSV in the process's default
   encoding and crashes with `CSV::InvalidEncodingError` when `LANG` is unset (reproduced).
   `cast_boolean` turns any unrecognized value into `false`, which would invent stockouts and
   therefore false alerts. Unknown stores and products are skipped silently. Re-running the import
   duplicates every row, and the import isn't atomic.
2. **Schema:** no `NOT NULL` on `inventory_present`, `event_time`, `stores.address`,
   `products.name` or `brands.name`. No uniqueness on the importer's lookup keys. No composite
   indexes for the `(store, product, event_time)` access paths.
3. **Views:** N+1 queries for counts and associations, unbounded lists (~10k rows on a store page),
   model calls inside views, and date-only data displayed as `00:00` times.
4. **Seeds:** `destroy_all` runs in an order that violates foreign keys (Brand before Product, and
   Store once events exist), so re-seeding fails after an import.
5. **Tests:** placeholder fixtures (`one: {}`) violate the `NOT NULL` foreign keys on
   `products.brand_id` and `tracking_events.*`, so the first test that loads fixtures errors.
   There are no tests.
6. **Ruby pin:** the Gemfile requires `ruby "3.2.9"` but the README tells reviewers to install
   3.2.2, so `bundle install` fails for anyone who follows the README.

---

## 3. Decisions

### 3.1 Decided with Bruce

| # | Topic | Decision |
|---|---|---|
| D1 | Price schema | **Rename `TrackingEvent` → `InventoryCheck`** and add a separate **`PriceCheck`** table. Each check type has its own non-nullable columns and indexes. |
| D2 | Price input | A **separate prices CSV** with its own importer and rake task, plus a deterministic sample-data generator. Shared importer code is extracted once there are two importers. |
| D3 | Money | **`price_cents` bigint, single currency (USD)**, `CHECK (price_cents >= 0)`. |
| D4 | Price UI | Product page: **current price at each store** plus paginated price history. Store page: **current price per product**. |
| D5 | Alert rule | **One alert per out-of-stock streak.** It is raised on the 2nd consecutive miss and closed when inventory is seen again. |
| D6 | Same-day ties | **Drop exact duplicates** with a unique index on `(store_id, product_id, event_time, inventory_present)`. Mixed same-day rows are kept and ordered by `id` (CSV order). This also makes re-imports idempotent. |
| D7 | Alert lifecycle | **Derived and reconciled.** Alerts are a projection of the checks. Each import recomputes the affected store/product pairs: it inserts new alerts, removes invalidated ones, and sets `resolved_at` when inventory returns. |
| D8 | Delivery | **Database record plus pages:** an alerts index (filterable) and show page, and open-alert counts on the brand pages. No outbound notifications. |
| D9 | Import speed | **Preloaded id maps plus batched `insert_all`** (~5k rows per batch, `ON CONFLICT DO NOTHING`). |
| D10 | Page speed | **Pagy pagination plus `GROUP BY` counts** (no counter caches). |
| D11 | Extras | **None for now.** They are listed in §9, and new ideas are logged during execution. |
| D12 | Git | **One branch per step and one worktree per parallel agent.** Small commits, and each step merges to `main` with `--no-ff`. |
| D13 | Ruby pin | Gemfile `ruby "~> 3.2.2"`. `.ruby-version` stays 3.2.9, and the README says either works. |
| D14 | Rake tasks | New `inventory_checks:import` and `price_checks:import`. **`tracking_events:import` still works and runs both.** It contains no import logic of its own: it just declares the two tasks as prerequisites, in order (`task import: %w[inventory_checks:import price_checks:import]`). **`inventory_checks:import` file lookup:** an explicit `[path]` argument wins; otherwise it uses `inventory_checks.csv` in the app root, and only if that file doesn't exist does it fall back to `tracking_events.csv` (backwards compatibility). It prints which file it chose. If neither exists, it exits 1 and names both files it looked for. *(Specified by Bruce.)* |
| D15 | Perf targets | **No hard numbers.** Before/after measurements go in `NOTES.md`. |
| D16 | This plan | Committed at `docs/PLAN.md` as the first commit of Step 0. |

### 3.2 Defaults I've chosen (veto any of these before Step 0 starts)

| # | Default | Why |
|---|---|---|
| A1 | Minitest plus fixtures | The project already uses them, and switching frameworks isn't what's being graded. |
| A2 | `inventory_present` is `NOT NULL` **with no default** | This deliberately breaks the "booleans always get a default" convention. A default of `false` would silently record a stockout whenever a value is missing. |
| A3 | Strict boolean parsing (`True`/`False`, case-insensitive). Anything else is rejected and counted. | The old behavior fabricated stockouts, and therefore alerts. |
| A4 | The D6 dedupe policy also applies to prices: unique `(store_id, product_id, event_time, price_cents)`. Different prices on the same day are all kept, and the "current" price is the one with the higher `id` (the later CSV row). *(Confirmed by Bruce.)* | Keeps the two importers consistent, makes the price import idempotent, and keeps intraday price changes. |
| A5 | Each import runs in one transaction | All or nothing. 1M rows in one Postgres transaction is fine at this scale. |
| A6 | Unique and `NOT NULL` `stores.address`, `products.name`, `brands.name` | The CSV identifies records by these values, so they have to be unique. |
| A7 | Commit a generated ~100k-row `price_checks.csv` (~7 MB) alongside the generator task | `tracking_events:import` then works for reviewers with no extra step. |
| A8 | **Migrations never delete data.** Before adding the unique index, the migration counts exact duplicates. If there are any, it aborts and points to an explicit task: `bin/rails inventory_checks:remove_duplicates`, which keeps the lowest `id` per duplicate group and runs in one transaction. With `DRY_RUN=1` it only reports how many rows it would delete in how many groups. The logic is a model class method (`InventoryCheck.remove_exact_duplicates`), and the task is a thin wrapper around it. *(Changed by Bruce.)* | Deleting data is a deliberate, visible operator action, not a side effect of `db:migrate`. A fresh database has no duplicates, so the migration just passes. On existing databases (yours has 1M rows, 39,489 duplicates), keeping the lowest `id` keeps the first CSV occurrence, which matches the §4.3 oracle. |
| A9 | The model is `InventoryAlert`, with `brand_id` stored on the alert | The alert is addressed to the brand. Storing `brand_id` gives cheap per-brand queries. The risk (a product changing brand) is documented. |
| A10 | Show pages list newest first, 50 per page | Bounded HTML and an obvious order. |
| A11 | Event times displayed as dates | The data is date-granular. |
| A12 | Pagy pinned `~> 9.4` | Pagy 43.x requires Ruby ≥ 3.3. |
| A13 | `has_many … dependent: :restrict_with_error` | Check history must never disappear as a side effect. |
| A14 | Measurement scripts stay out of the repo, and the numbers go in `NOTES.md` | The `perf:report` task is a deferred extra (§9). |
| A15 | `.idea/` goes in `.git/info/exclude`, not `.gitignore` | It's a personal IDE folder and doesn't belong in the project. |

---

## 4. Target design

### 4.1 Schema

```
brands            name NOT NULL UNIQUE
products          name NOT NULL UNIQUE, brand_id NOT NULL FK
stores            address NOT NULL UNIQUE

inventory_checks  (renamed from tracking_events)
  store_id, product_id   NOT NULL FKs
  event_time             datetime NOT NULL
  inventory_present      boolean  NOT NULL            -- no default (A2)
  UNIQUE (store_id, product_id, event_time, inventory_present)   -- dedupe + alert timeline
  INDEX  (store_id, event_time)      -- store page, newest first
  INDEX  (product_id, event_time)    -- product page, newest first
  (drop the single-column store_id / product_id indexes: covered by the composites' leading columns)

price_checks
  store_id, product_id   NOT NULL FKs (explicitly named)
  event_time             datetime NOT NULL
  price_cents            bigint   NOT NULL, CHECK (price_cents >= 0)
  UNIQUE (store_id, product_id, event_time, price_cents)  -- dedupe + store page "latest per product"
  INDEX  (product_id, event_time)                          -- product page history + latest per store

inventory_alerts
  brand_id, store_id, product_id      NOT NULL FKs
  streak_start_check_id               NOT NULL FK → inventory_checks, UNIQUE   -- alert identity
  triggering_check_id                 NOT NULL FK → inventory_checks           -- the 2nd miss
  resolving_check_id                  FK → inventory_checks, nullable          -- first in-stock after
  started_at, triggered_at            datetime NOT NULL
  resolved_at                         datetime, nullable   (open ⇔ NULL)
  miss_count                          integer NOT NULL
  INDEX (brand_id, triggered_at) · INDEX (store_id, product_id)
```

Index choices are confirmed with `EXPLAIN ANALYZE` on the full dataset during each step. The plans
go in `NOTES.md`.

### 4.2 Code layout

```
app/models/        inventory_check.rb · price_check.rb · inventory_alert.rb (+ scopes: open, resolved, for_brand)
app/services/
  inventory_checks/csv_importer.rb     # returns an ImportResult (Data.define)
  price_checks/csv_importer.rb
  <shared CSV check-import base>       # extracted in Step 2 when the second importer arrives
  inventory_alerts/reconciler.rb       # set-based SQL (window functions), scoped to pairs
lib/tasks/         inventory_checks.rake · price_checks.rake (import, generate_sample) ·
                   inventory_alerts.rake (reconcile) · tracking_events.rake (alias → both imports)
app/controllers/   stores · products · brands · inventory_alerts (index, show)
```

Method names describe behavior (`import`, `reconcile`), not `call`. Every agent loads the
`rails-conventions` skill before writing code.

### 4.3 Alert algorithm (validated)

For each store/product timeline ordered by `(event_time, id)`:

1. Mark a row as starting a new run when `inventory_present IS DISTINCT FROM LAG(inventory_present)`.
2. Number the runs with a running `SUM` of those start markers.
3. An out-of-stock run with ≥ 2 checks is one alert:
   - **start** is the run's 1st check and **triggering** is its 2nd, both taken with
     `(ARRAY_AGG(id ORDER BY event_time, id))[1:2]`. Not `MIN(id)`: out-of-order arrival means ids
     aren't in time order.
   - **resolving** is the first check of run `n + 1`, if there is one.
4. Upsert alerts `ON CONFLICT (streak_start_check_id)`, then delete alerts in the scoped pairs whose
   start is no longer in the desired set. Run both in one transaction.
5. Scope by pair with bound arrays: `WHERE (store_id, product_id) IN (SELECT * FROM unnest(:store_ids::bigint[], :product_ids::bigint[]))`.
   No scope means rebuild everything.

**Validation already done:** this query on the current 1M-row table (with the D6 dedupe emulated)
returns **29,978 alerts, 849 open**, in **1.2 s with no supporting indexes**. An independent Ruby
oracle over the raw CSV gets the same numbers. These are the acceptance numbers for Step 3.

Reference counts for `NOTES.md` (why D5 and D6 matter):

| Duplicate policy | Rows | One alert per pair | One alert per streak |
|---|---:|---:|---:|
| Keep all, ties by CSV order | 1,000,000 | 39,114 | 31,447 |
| **Drop exact duplicates (chosen)** | **960,511** | 36,868 | **29,978** |
| Collapse to one per day (any miss counts) | 942,449 | 40,520 | 32,231 |

---

## 5. Execution model

**Roles.** The *lead* (the main Claude session) runs every serial task, creates the worktrees,
dispatches the parallel agents, merges, runs acceptance checks, takes measurements, and keeps this
plan and `NOTES.md` up to date. *Agents* run the parallel tasks.

**Branches and worktrees.**

```
main
 └─ step-N                          # lead: serial task N.A committed here
     ├─ step-N-<task>   worktree: ../RetailTestProject-wt/<task>   # one per parallel agent
     └─ ...
lead: git merge --no-ff step-N-<task> → step-N (tests + acceptance) → git merge --no-ff step-N → main
      git worktree remove …
```

**Rules for every agent.**

1. Load the `rails-conventions` skill first.
2. Touch only the files in your ownership list. If you need anything else, stop and report to the
   lead.
3. **No migrations.** Schema changes happen only in serial `N.A` tasks, so `db/schema.rb` never
   conflicts.
4. Use your own test database:
   `RAILS_ENV=test DATABASE_URL=postgres:///retail_test_<task> bin/rails db:test:prepare test`
   **`RAILS_ENV=test` is required.** Without it, rake runs in development, `DATABASE_URL` only
   overrides the development config, and `db:test:prepare` purges the shared
   `retail_test_project_test` database (verified in 0.B). Parallel workers use
   `retail_test_<task>-0…N`, created automatically. When a worktree is removed, drop its databases.
5. Never run a full import against the shared development database. For full-data work, clone it
   (`createdb -T retail_test_project_development retail_<task>`; this needs no open connections to
   the template).
6. Make small, single-purpose commits in Chris Beams style, ending with the
   `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` trailer. Tests must be green before
   you report.
7. Report back with: a summary, your commits, test output, anything you deliberately left out, and
   **suggestions for §10**.
8. **Every code change has test coverage.** This covers models, services, rake tasks, controllers,
   views, seeds and migrations (for example, the A8 abort check). If code is changed without a test
   that would fail had the change not been made, the task isn't done. *(Required by Bruce.)*

**Bruce reviews every step before it merges.** Once all of a step's tasks are merged into `step-N`
and the lead's acceptance checks pass, the lead stops and gives Bruce a review summary: the diff
(`git diff main...step-N`), test results, the coverage map (each changed file → the tests that
cover it), acceptance numbers, and open questions. `step-N` is merged into `main` only after Bruce
approves, and the next step starts only after that merge. *(Required by Bruce.)*

**A step is done when:** migrations run on both a fresh and an existing database · `bin/rails test`
passes · every code change is covered by tests (rule 8) · every page returns 200 on the full
dataset · the documented commands work · `NOTES.md` has this step's decisions and numbers · Bruce
has reviewed and approved it · `step-N` is merged to `main`.

**Time budget:** S0 15 min · S1 50 min · S2 35 min · S3 45 min · S4 20 min ≈ **2 h 45 min**.
Parallel agents shorten the wall-clock time, not the total work.

---

## 6. Steps

### Step 0 — Foundation · branch `step-0`

What ships: the same app, but reviewers can bundle it, tests can run, and seeding is repeatable.

| Task | Mode | Owns | Work |
|---|---|---|---|
| **0.A** | serial (lead) | `docs/PLAN.md`, `NOTES.md`, `Gemfile`, `Gemfile.lock`, `.git/info/exclude` | Commit this plan. Ruby pin per D13 (`bundle install` to refresh the lock). Create a `NOTES.md` skeleton (decisions, assumptions, data findings, baseline numbers from §2). Exclude `.idea/`. |
| **0.B** | parallel | `test/**` | Replace placeholder fixtures with valid ones (brands, products, stores, a few tracking events). Add model smoke tests. Get `bin/rails test` green. Check the per-worktree `DATABASE_URL` test-database recipe with parallel workers, and update rule 4 if it needs changing. |
| **0.C** | parallel | `db/seeds.rb` | Make seeds idempotent (`find_or_create_by!`/`upsert_all` keyed on name/address, no `destroy_all`). Seeds must re-run safely after an import. |

### Step 1 — Rename, schema hardening, fast importer, fast pages (Objective 3) · branch `step-1`

This step comes first because the 24-minute import blocks every later iteration, and because doing
the rename now means the importer only gets rewritten once.

What ships: the same features under clearer names. The import finishes in about a minute and is
idempotent and atomic, and every page runs a small, fixed number of queries.

| Task | Mode | Owns | Work |
|---|---|---|---|
| **1.A** | serial (lead) | `db/**`, models, and the rename across `app/**`, `lib/**`, `test/**` | Migrations: (1) `rename_table :tracking_events, :inventory_checks`. (2) Catalog `NOT NULL` + unique (A6). (3) Check for duplicates and abort with instructions if any are found (A8; the check is raw SQL, with no app model inside the migration) → `NOT NULL` on `inventory_present`/`event_time` → unique + composite indexes, and drop the redundant single-column indexes (§4.1). Add `InventoryCheck.remove_exact_duplicates` (with a dry-run mode) plus model tests, and `lib/tasks/inventory_checks_maintenance.rake` (`remove_duplicates`, `DRY_RUN=1`). 1.B builds on this file and must not change it. Rename the model, associations (`dependent:` A13), validations matching the constraints, views, controllers, and the importer module (`TrackingEvents` → `InventoryChecks`). Tests stay green. |
| **1.B** | parallel | `app/services/**`, `lib/tasks/**`, `test/services/**`, `test/fixtures/files/**` | Rewrite the importer (D9): UTF-8 explicitly (`encoding: "bom\|utf-8"`), preloaded id maps, strict `Date.iso8601` and boolean parsing (A3), `insert_all` in 5k batches against the unique index, one transaction (A5), returns an `ImportResult` (rows read / inserted / duplicates / rejected), and rejections logged with samples. Rake (D14): `inventory_checks:import[path]` resolves the file as path argument → `inventory_checks.csv` → `tracking_events.csv`, and prints the file it chose. `tracking_events:import` becomes a task with prerequisites only (`inventory_checks:import` for now; 2.B adds `price_checks:import`), with no duplicated code. The file-resolution rule lives in one small method that's tested directly (each file present or missing, plus an explicit path). Tests: happy path, unknown store/product, bad date, bad boolean, duplicates, idempotent re-run, UTF-8 names (`’`), empty file, missing file. |
| **1.C** | parallel | `app/controllers/**`, `app/views/**`, `app/helpers/**`, `config/routes.rb`, `Gemfile*` (Pagy only), `config/initializers/pagy.rb`, `app/assets/stylesheets/**`, `test/controllers/**`, `test/integration/**`, `test/support/**`, `test/test_helper.rb` | Pagy `~> 9.4` (A12). Index pages use one grouped count (D10) plus `includes`. Show pages are paginated newest first (A10) with `includes`. No model calls in views. A shared nav partial in the layout. Dates rendered as dates (A11). Add an `assert_max_queries` test helper (Rails 7.1 has no public `assert_queries_count`). Integration tests for every page: 200, content, query bound, pagination, 404. |

**Lead acceptance (existing database):** on a clone of your current 1M-row database, `db:migrate`
aborts with the instructions → `DRY_RUN=1 … remove_duplicates` reports **39,489** rows → running it
for real deletes them → `db:migrate` completes → **960,511** rows remain.

**Lead acceptance (fresh database):** fresh database → seed → import. Record the import time, row count
(**960,511**), and duplicates skipped (**39,489**). Re-run the import and confirm 0 rows are
inserted. Re-measure §2.2 and record it in `NOTES.md` with `EXPLAIN ANALYZE` for the show-page
queries.

### Step 2 — Price tracking (Objective 1) · branch `step-2`

What ships: prices imported from their own CSV, current prices and price history on the product
page, and current prices on the store page. `tracking_events:import` loads both kinds of check.

| Task | Mode | Owns | Work |
|---|---|---|---|
| **2.A** | serial (lead) | `db/**`, `app/models/**`, `test/models/**`, `test/fixtures/**` | `create_price_checks` (§4.1, D3, A4). `PriceCheck` model with validations matching the constraints, associations on `Store`/`Product` (A13), and a latest-price scope (`DISTINCT ON (store_id, product_id) … ORDER BY …, event_time DESC, id DESC`; a SQL fragment is justified because AR can't express it). Fixtures and model tests. |
| **2.B** | parallel | `app/services/**`, `lib/tasks/**`, `test/services/**`, `test/fixtures/files/**`, `price_checks.csv` | Extract the shared CSV check-import base from the inventory importer (lookups, batching, transaction, result, rejection logging), then build `PriceChecks::CsvImporter` on it. Price format: `Address,Product Name,Date,Price`, where Price matches `\A\d+(\.\d{1,2})?\z` → `BigDecimal` → cents (no floats). Tasks: `price_checks:import[path]`, and `price_checks:generate_sample` (seeded `Random`, ~100k rows over the same date range, realistic base price per product with variance per store) used to generate and commit `price_checks.csv` (A7). Add `price_checks:import` as the second prerequisite of `tracking_events:import` (D14). No import code goes in that task. `price_checks:import` exits 1 if its file is missing, just like the inventory task. Because `price_checks.csv` is committed (A7), the combined task always has both files. Tests mirror 1.B's, plus price-format edge cases (0, 0.5, 1.234, negative, blank, `$`). |
| **2.C** | parallel | `app/controllers/**`, `app/views/**`, `app/helpers/**`, `test/controllers/**`, `test/integration/**` | Product page: "Current price by store" table (latest-price scope) plus paginated price history. It uses its own Pagy `page_param` so it doesn't clash with the inventory list. Store page: "Current prices" table. Price helper via `number_to_currency` on `BigDecimal(cents) / 100`. Tests including query bounds. |

**Lead acceptance:** full import. Price row count = generated rows − duplicates. Spot-check the
current prices on the page against SQL. Re-measure the product and store pages. Record the EXPLAIN
plans for the latest-price queries.

### Step 3 — Alert system (Objective 2) · branch `step-3`

What ships: alerts created and kept consistent on every inventory import, alerts index and show
pages, and open-alert counts on the brand pages.

| Task | Mode | Owns | Work |
|---|---|---|---|
| **3.A** | serial (lead) | `db/**`, `app/models/**`, `test/models/**`, `test/fixtures/**` | `create_inventory_alerts` (§4.1). `InventoryAlert` model: associations (including `belongs_to :streak_start_check, class_name: "InventoryCheck"`), `open?`/`resolved?`, scopes `open`, `resolved`, `for_brand`. `has_many :inventory_alerts` on Brand/Store/Product. Fixtures (open and resolved) and model tests. Write down the reconciler contract for 3.B and 3.C: `InventoryAlerts::Reconciler.new(pairs: nil).reconcile → Result(created:, updated:, deleted:)`. |
| **3.B** | parallel | `app/services/**`, `lib/tasks/**`, `test/services/**` | The reconciler per §4.3 (raw SQL is justified for window functions; parameters bound, never interpolated). Import integration: the inventory importer collects the pairs it actually inserted (`returning: %w[store_id product_id]`) and reconciles them inside the import transaction. Rake `inventory_alerts:reconcile` for a full rebuild. Tests: one miss → none · two → one open · 3+ → still one, with the `miss_count` · miss, miss, hit → resolved, with `resolving_check` · a late miss arriving first creates a streak · a late hit inserted mid-streak removes the alert · a late earlier miss moves the streak start (old alert gone, new one created) · same-day `True`/`False` ordered by id · scoping leaves other pairs untouched · reconciling twice changes nothing. |
| **3.C** | parallel | `app/controllers/**`, `app/views/**`, `app/helpers/**`, `config/routes.rb`, `test/controllers/**`, `test/integration/**` | `resources :inventory_alerts, only: %i[index show]`. Index: newest triggered first, Pagy, filters `brand_id` and `status` (open/resolved) through model scopes, and `includes`. Show: brand, store, product, started/triggered/resolved, miss count, links. Brand index and show pages: open-alert counts (grouped) linking to the filtered index. Nav link. Tests use fixture alerts, independent of the reconciler. |

**Lead acceptance (the key correctness check):** fresh database → seed → `tracking_events:import`
must produce exactly **29,978 alerts with 849 open**, matching the independent oracle in §4.3.
Re-running the import must leave the alerts unchanged. Record the time of a full reconcile and the
alert page measurements.

### Step 4 — Submission · branch `step-4`

What ships: the submission itself.

| Task | Mode | Owns | Work |
|---|---|---|---|
| **4.A** | parallel | `NOTES.md` | Finalize: the decisions and their reasons (§3), assumptions, data findings, before/after tables (§2 compared with the final numbers), EXPLAIN highlights, trade-offs (`GROUP BY` vs counter caches, `insert_all` vs COPY, the denormalized `brand_id`, derived alerts), and what's next (§9/§10). |
| **4.B** | parallel | `README.md` | Setup (Ruby `~> 3.2.2`, Postgres), commands (seed, `tracking_events:import` and the two tasks it runs, the `inventory_checks.csv` → `tracking_events.csv` fallback, `price_checks:generate_sample`, `inventory_alerts:reconcile`, tests), and links to `NOTES.md` and `docs/PLAN.md`. Keep the original brief above the new sections. |
| **4.C** | parallel | code fixes only | Review the full `main..step-4` diff (with `/code-review` or `rails-review`) and fix confirmed findings in small commits. |
| **4.D** | serial (lead, last) | — | Clean clone into a temp directory → `bundle` → `db:create db:migrate db:seed` → `tracking_events:import` → `bin/rails test` → smoke-test every page. Then hand off to Bruce to push. |

---

## 7. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Parallel agents collide on `db/schema.rb`, routes, or the layout | Migrations happen only in serial tasks. Each shared file has exactly one owner per step. |
| Shared development and test databases across worktrees | A test database per worktree (rule 4) and cloned databases for full-data work (rule 5). |
| `insert_all` skips validations and callbacks | Database constraints are the source of truth, and the parsers reject bad values before insert. |
| Alert ids aren't time-ordered (out-of-order arrival) | Order by `(event_time, id)` everywhere, and use `ARRAY_AGG … ORDER BY`, never `MIN(id)`. |
| Running over the 2–3 h budget | Extras are deferred (D11). If we're over budget, trim 2.C's price history first and keep the current-price tables. |
| Reviewers on Ruby 3.2.2 | D13, checked in 4.D. |

---

## 8. Progress

- [x] Step 0 — Foundation
- [ ] Step 1 — Rename, schema, importer, pages
- [ ] Step 2 — Price tracking
- [ ] Step 3 — Alert system
- [ ] Step 4 — Submission

---

## 9. Deferred extras (to reconsider once Steps 0–3 ship, if time allows)

1. `perf:report` rake task that prints import time and per-page timings and query counts (turns
   A14's scripts into a repeatable tool).
2. Bullet in development and test, so N+1 regressions fail tests.
3. RuboCop (`rubocop-rails-omakase`) with a clean run.
4. GitHub Actions CI with a Postgres service running tests (and RuboCop).

## 10. Suggestions log (added to during execution)

- Keyset pagination for the show pages if the tables grow well beyond 1M rows (Pagy keyset).
- A "current stock status" table per store/product, kept up to date by the reconciler, for instant
  "what's out of stock now" queries.
- Brand notification digests (one email per brand per import) if delivery is ever needed. Sending
  one email per alert would mean 30k emails on a backfill.
- `CREATE INDEX CONCURRENTLY` / `disable_ddl_transaction!` for the index migrations in a
  zero-downtime production setting. Not needed locally.
- Once Step 1 adds unique indexes on the catalog keys, seeds could use `insert_all` with
  `unique_by` (insert-only, never upsert, so an existing product's brand is never rewritten). *(0.C)*
- The test suite runs in one process until it has 50+ tests; parallel workers start after that. *(0.B)*
