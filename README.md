# Russian Government Procurement Automation

An n8n-based automation pipeline for monitoring and analyzing Russian government tenders under **44-FZ**, **223-FZ**, and **PP RF 615**.

Built for procurement intermediaries: automatically collects contract history, finds low-competition niches, detects dumping, discovers active suppliers, monitors new tenders in real time, and provides an AI analyst accessible via Telegram.

---

## Pipeline Overview

```
GosPlan API v2
      │
      ▼
┌─────────────────────────────────┐
│  Stage 1 · Contract Collector   │  Pulls historical 44-FZ contracts
│  Scheduled monthly              │  into PostgreSQL (all 99 regions,
│                                 │  split by region + month to bypass
│                                 │  API pagination limits)
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│  Stage 2 · Stats Refresh        │  Aggregates win-rates, avg prices,
│  Triggered after Stage 1        │  competition counts per KTRU/OKPD2
│                                 │  → exports to Google Sheets
└────────┬────────┬───────────────┘
         │        │
    ┌────┘    ┌───┘
    ▼         ▼
┌──────────┐ ┌─────────────┐ ┌──────────────┐
│ Stage 3a │ │  Stage 3b   │ │  Stage 3c    │
│  Niche   │ │  Toxicity   │ │  Supplier    │
│  Finder  │ │  Check      │ │  Finder      │
└──────────┘ └─────────────┘ └──────────────┘
  Low-comp.   Dumping risk    Active suppliers
  niches by   score per       by niche with
  price range KTRU code       win history

         │
         ▼
┌─────────────────────────────────┐
│  Stage 4 · Monitor              │  Polls GosPlan every N minutes
│  Runs continuously              │  for new notices matching target
│                                 │  niches → deduplicates via DB →
│                                 │  sends Telegram alert + logs to
│                                 │  Google Sheets
└─────────────────────────────────┘

┌─────────────────────────────────┐
│  Stage 5 · AI Agent             │  Claude-powered analyst:
│  Always on (Telegram + Chat)    │  · answers questions about the DB
│                                 │  · explains tender documents
│                                 │  · uses PostgreSQL tool + GosPlan
│                                 │    API tool for live lookups
└─────────────────────────────────┘
```

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| Workflow automation | [n8n](https://n8n.io) (self-hosted) |
| Database | PostgreSQL |
| Procurement data | [GosPlan API v2](https://swagger.gosplan.info) |
| AI backbone | DeepSeek (via OpenRouter-compatible endpoint) |
| Notifications | Telegram Bot API |
| Reporting | Google Sheets (OAuth2 Service Account) |

---

## Stages in Detail

### Stage 1 — Contract Collector
- Fetches all 44-FZ contracts from GosPlan API with price filters (configurable range)
- Pagination strategy: iterates region × month combinations to stay under the `skip ≤ 1000` real-world API limit
- Respects rate limits with `Wait` nodes (6 s / request on test server, 0.1 s on prod)
- Uses `ON CONFLICT DO NOTHING` — safe to re-run on existing data
- Auto-refreshes monthly via schedule trigger

### Stage 2 — Stats Refresh
- Runs SQL aggregate functions over `contracts` table
- Computes per-KTRU/OKPD2: contract count, avg/min/max price, unique customers, win-rate by supplier
- Pushes results to Google Sheets for human-readable dashboards

### Stage 3a — Niche Finder
- Queries aggregated stats to surface niches with low supplier count and stable pricing
- Filters out highly contested or price-volatile categories

### Stage 3b — Toxicity Check
- Flags KTRU codes where known "dumpers" win repeatedly below cost
- Outputs a risk score used by the Monitor to deprioritize noisy categories

### Stage 3c — Supplier Finder
- For a given niche, finds all INN numbers of suppliers who have won contracts
- Enriches with win count, average margin vs. initial price

### Stage 4 — Monitor
- Polls GosPlan `/fz44/purchases` (and 223-FZ / PP615 endpoints) for new notices
- Deduplicates via `alerted_notices` table — each notice triggers at most one alert
- Formats a Telegram message with: title, price, customer, deadline, direct EIS link
- Logs every alert to Google Sheets (timestamp, reg_num, price, sheet row)

### Stage 5 — AI Agent
- Dual interface: Telegram bot + n8n Chat widget
- Tools available to the agent:
  - **PostgreSQL** — run arbitrary read-only SQL against the contracts DB
  - **GosPlan API** — live lookup of notices, contracts, supplier history
- System prompt: procurement domain expert with knowledge of 44-FZ/223-FZ rules
- Conversation memory stored in `n8n_chat_histories` (Postgres Chat Memory node)

---

## Database Schema

```
db/
├── 001_init_contracts.sql      — contracts table + GIN indexes (ktru, okpd2, suppliers)
├── 002_collection_tasks.sql    — pagination task queue for Stage 1
├── 003_contract_stats.sql      — aggregated stats materialized table
├── 004_target_niches.sql       — curated niche list with thresholds
├── 005_dumping_checks.sql      — toxicity scores per KTRU
├── 006_refresh_suppliers.sql   — supplier win history
└── 007_chat_memory.sql         — AI agent conversation history
```

Key design decisions:
- `contracts.suppliers` and `contracts.ktru` are `TEXT[]` — queried with GIN indexes via `@>` operator
- `contracts.source` stores the full raw API JSON as `JSONB` for future field additions without schema changes
- All inserts use `ON CONFLICT DO NOTHING` — idempotent re-runs

---

## GosPlan API — Key Constraints

| Constraint | Value |
|-----------|-------|
| Rate limit (prod) | 600 req/min |
| Rate limit (test) | 10 req/min |
| Max `limit` per request | 100 |
| Effective `skip` ceiling | ~1 000 (documented 50 000, actual limit) |
| Max classifiers per query | 5 (KTRU/OKPD2) |
| Bypass for skip limit | Split by region + month |

Response format: flat JSON array `[{...}]` — no wrapper object.

---

## Workflow Files

```
workflows/
├── stage1_contracts_collector.json   — Stage 1
├── stage2_stats_refresh.json         — Stage 2
├── stage3_niche_finder.json          — Stage 3a
├── stage3_toxicity_check.json        — Stage 3b
├── stage3_suppliers.json             — Stage 3c
├── stage4_monitor.json               — Stage 4 (Monitor + Telegram alerts)
├── stage6_ai_agent.json              — Stage 5 (AI Agent)
└── helper_sql_tool.json              — Shared SQL sub-workflow used by AI Agent
```

All credential IDs in the JSON files reference your local n8n instance — replace them after import.

---

## Setup

### Prerequisites
- n8n (self-hosted, tested on v1.x)
- PostgreSQL 14+
- GosPlan API key ([register at gosplan.info](https://gosplan.info))
- Telegram Bot token
- Google Service Account with Sheets API access

### Database
Run migrations in order:
```sql
psql -d your_db -f db/001_init_contracts.sql
psql -d your_db -f db/002_collection_tasks.sql
-- ... repeat for 003–007
```

### n8n
1. Import workflow JSONs via n8n UI or API
2. Create credentials:
   - **PostgreSQL** — connect to your DB
   - **Google Sheets OAuth2** (Service Account mode) — use type `googleSheetsOAuth2Api`
   - **Telegram** — bot token
   - **HTTP Header Auth** — GosPlan API key as header value
3. Update `Set Config` node in Stage 1 with your API base URL and price filters
4. Activate workflows

---

## Screenshots

### n8n Workflows Overview
![Workflows](Screen%20workflows.jpg)

### Database (PostgreSQL)
![Database](Screen%20DB.jpg)

### Execution History
![Execution](Screen%20Execution.jpg)

### AI Agent (Stage 5)
![AI Agent](Screen%20stage%206.jpg)

---

## Project Status

| Stage | Status |
|-------|--------|
| 1 — Contract Collector | Active |
| 2 — Stats Refresh | Active |
| 3 — Niche / Toxicity / Supplier | Active |
| 4 — Monitor | Active |
| 5 — AI Agent | Active |
| 6 — RFQ drafting (КП) | Planned |
