# Retail Inventory Tracking System

My solution to the take-home brief below. Price tracking is a separate kind of check
(`PriceCheck`, alongside the renamed `InventoryCheck`), because either can happen without the
other. A store/product that misses inventory twice in a row raises one alert to the brand per
out-of-stock streak; alerts are derived from the checks and reconciled on every import. The
million-row import went from 24 minutes to about 36 seconds, prices and alerts included, and pages that ran thousands of
queries now run a handful.

- **[NOTES.md](NOTES.md)**: key decisions, assumptions, and before/after measurements. Start here
  for the why.
- **[docs/PLAN.md](docs/PLAN.md)**: how the work was planned and split into shippable steps.

## Running it

### Prerequisites

- **Ruby 3.2.x, 3.2.2 or later.** The Gemfile accepts `~> 3.2.2`. `.ruby-version` names 3.2.9, so
  rbenv and asdf users can `rbenv install 3.2.9` (or `asdf install ruby 3.2.9`). If you already
  have another 3.2.x, change `.ruby-version` locally instead.
- **PostgreSQL 13+** (developed on 15), reachable through the default local socket, or set
  `DATABASE_URL`.

### Setup

```bash
bundle install
```

```bash
bin/rails db:create db:migrate db:seed
```

Seeds are idempotent, so `db:seed` is safe to re-run, including after an import.

### Import the data

```bash
bin/rails tracking_events:import
```

This runs `inventory_checks:import` and then `price_checks:import`:

- Inventory checks come from `inventory_checks.csv` (the brief's `tracking_events.csv`, renamed),
  falling back to `tracking_events.csv` if that's what you have. Alerts for the store/product
  pairs it touches are reconciled in the same transaction.
- Price checks come from `price_checks.csv`, a generated sample committed to the repository
  (there is no real price data).

On a fresh database both files, alerts included, take about 40 seconds and print:

```
Inventory checks: rows read=1000000 inserted=960511 duplicates=39489 rejected=0; alerts created=29978 updated=0 deleted=0
Price checks: rows read=100000 inserted=98022 duplicates=1978 rejected=0
```

Exact duplicate rows are skipped, so re-running the import is safe: it inserts nothing and
changes no alerts. Each task also takes an explicit path. Quote the task name in zsh, which
otherwise treats the brackets as a glob:

```bash
bin/rails "inventory_checks:import[path/to/checks.csv]"
```

```bash
bin/rails "price_checks:import[path/to/prices.csv]"
```

### Other tasks

| Command | What it does |
|---|---|
| `bin/rails inventory_alerts:reconcile` | Rebuilds every alert from the checks (about 2.5 s). Imports already keep the pairs they touch up to date; running it twice changes nothing. |
| `bin/rails "price_checks:generate_sample[path,rows]"` | Writes a reproducible price sample for the seeded catalog. Defaults: `price_checks.csv`, 100,000 rows. |
| `DRY_RUN=1 bin/rails inventory_checks:remove_duplicates` | Reports exact duplicate inventory checks; without `DRY_RUN` it deletes them, keeping the earliest copy. Only needed for a database imported with the original importer (see below). |

### Run the app

```bash
bin/rails server
```

Then open <http://localhost:3000>:

- **Stores** and **Products**: index pages with inventory-check counts, and show pages with the
  current price per product or store and paginated inventory checks (newest first).
- **Price history**: on each product page, loaded lazily (`/products/:id/price_checks`).
- **Brands**: product and open-alert counts, linking to that brand's alerts.
- **Alerts** (`/inventory_alerts`): newest first, filterable by brand and status (open or
  resolved). Each alert's page lists the checks in its streak.

### Tests

```bash
bin/rails test
```

285 tests (803 assertions). They include query-count caps on every page, so an N+1 regression
fails the build.

### Upgrading an existing database

If you imported with the original code, `bin/rails db:migrate` stops before adding the unique
index on inventory checks, because the original importer stored duplicates (39,489 on the full
CSV). Migrations never delete data, so the error tells you what to run:

```bash
DRY_RUN=1 bin/rails inventory_checks:remove_duplicates
```

```bash
bin/rails inventory_checks:remove_duplicates
```

```bash
bin/rails db:migrate
```

Then create alerts for the checks that were already imported:

```bash
bin/rails inventory_alerts:reconcile
```

## Original assignment brief

Kept verbatim. Its setup steps predate this solution; follow [Running it](#running-it) instead.

### Project Overview

This project simulates a simplified retail inventory-tracking system. You are provided with:

- A set of **Stores**
- A set of **Brands**
- A set of **Products**
- A large CSV file containing **1,000,000 tracking events**
- A basic importer that reads the CSV and creates `TrackingEvent` records

Your goal is to improve the system, modify one of its key features, and then add a new feature.

You are encouraged to:
- Refactor existing code
- Introduce new endpoints or views
- Improve performance, clarity, and maintainability

There is no single "correct" solution — but there are many poor ones. We want to see how **you** design and implement a real-world improvement inside a Rails application.

### Setup

This app is a standard Rails 7.1 / Ruby 3.2 project backed by PostgreSQL.

#### Prerequisites

- **Ruby**: `3.2.2`
- **Rails**: `~> 7.1.6`
- **PostgreSQL**: 13+ recommended

You can use **rbenv**, **rvm**, or **asdf** to install the correct Ruby version.

##### Installing Ruby with rbenv
```bash
# Install Ruby 3.2.2
rbenv install 3.2.2

# Set it locally for this project
rbenv local 3.2.2
```

#### Installation
```bash
# Install dependencies
bundle install

# Set up the database
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed
```

#### Importing Tracking Events

To import the million-row CSV file:
```bash
bin/rails tracking_events:import
```

### Objectives

#### First Objective: Price Tracking

Currently, the system only tracks if inventory is present via `TrackingEvent`. We want to add a way to track price. An inventory check and price check are separate and can occur without the other happening.

#### Second Objective: Alert System

Build an alert system that creates an alert to the brand if a store has two "no inventory" events in a row for the same product based on event_time. There doesn't need to be a big UI for this—just a basic index and show page like the rest of the app.

#### Third Objective: Performance Improvements

Improve the app's overall performance. This can be done as you work on the first and second objectives or after completing them.

### Technology Stack

- **Ruby**: 3.2.2
- **Rails**: 7.1.6
- **Database**: PostgreSQL 13+

### Evaluation Criteria

You will be evaluated on:
- Code quality and organization
- Database design decisions
- Performance optimizations
- Ability to explain your thinking and decision making

Feel free to make reasonable assumptions where requirements are ambiguous—just document them in your code or a separate notes file.

### Time Expectation

This project should take approximately [2-3 hours] to complete. Focus on demonstrating your problem-solving approach rather than achieving perfection. AI is allowed on this project. 

### Submission

Please submit:
- A link or invite to your Git repository (GitHub, GitLab, etc.)
- A brief README or notes document explaining your key decisions
- Any instructions needed to run your solution
