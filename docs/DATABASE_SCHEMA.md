# Dukaan Book Database Schema

This schema is the recommended source of truth for both Supabase PostgreSQL and the local Drift/SQLite database. Names can be adapted to framework conventions, but the relationships and money rules should remain stable.

## 1. Design Principles

- Store money as integer paisa, never floating point values.
- Use client-generated IDs so records can be created offline.
- Use append-mostly financial history.
- Use soft deletes for synced records.
- Keep account balances derivable from ledger lines.
- Use Row Level Security on every Supabase table that contains user data.

## 2. Entity Relationship Overview

```text
auth.users
  └── profiles
        └── shops
              ├── accounts
              ├── ledger_transactions
              │     └── ledger_lines
              ├── expense_categories
              └── daily_closings
```

## 3. Enumerations

Use PostgreSQL enums remotely or check constraints if easier to migrate.

```sql
account_type:
  cash, easypaisa, jazzcash, nayapay, bank, expense, owner_equity, custom

ledger_transaction_kind:
  opening_balance, cash_in, cash_out, wallet_load, withdrawal, transfer,
  expense, adjustment, reversal

ledger_status:
  draft, posted, reversed

sync_operation:
  insert, update, delete
```

## 4. Tables

### profiles

Stores one profile per authenticated user.

| Column | Type | Notes |
| --- | --- | --- |
| id | uuid | Primary key, references `auth.users.id`. |
| full_name | text | Nullable. |
| phone | text | Nullable. |
| preferred_language | text | Default `en`, later `ur`. |
| created_at | timestamptz | Default `now()`. |
| updated_at | timestamptz | Default `now()`. |

### shops

Stores the shop/business context. MVP can support one shop per user while keeping schema ready for more.

| Column | Type | Notes |
| --- | --- | --- |
| id | uuid | Primary key. |
| user_id | uuid | References `auth.users.id`. |
| name | text | Required. |
| city | text | Nullable. |
| phone | text | Nullable. |
| timezone | text | Default `Asia/Karachi`. |
| day_close_time | time | Default `21:00`. |
| created_at | timestamptz | Default `now()`. |
| updated_at | timestamptz | Default `now()`. |
| deleted_at | timestamptz | Nullable. |

### accounts

Represents cash boxes, wallets, banks, expense buckets, and balancing accounts.

| Column | Type | Notes |
| --- | --- | --- |
| id | uuid | Primary key. |
| user_id | uuid | References `auth.users.id`. |
| shop_id | uuid | References `shops.id`. |
| name | text | Required. |
| type | account_type | Required. |
| color_hex | text | UI hint. |
| sort_order | integer | Default `0`. |
| is_active | boolean | Default `true`. |
| is_system | boolean | Default `false`; protects required accounts. |
| low_balance_threshold_paisa | bigint | Nullable. |
| created_at | timestamptz | Default `now()`. |
| updated_at | timestamptz | Default `now()`. |
| deleted_at | timestamptz | Nullable. |
| client_updated_at | timestamptz | Set by app for conflict handling. |

Do not store authoritative running balance here. If a cache is needed, use a projection table locally and rebuild it from `ledger_lines`.

### ledger_transactions

Represents a financial event.

| Column | Type | Notes |
| --- | --- | --- |
| id | uuid | Primary key. |
| user_id | uuid | References `auth.users.id`. |
| shop_id | uuid | References `shops.id`. |
| kind | ledger_transaction_kind | Required. |
| status | ledger_status | Default `posted`. |
| business_date | date | Date in shop timezone. |
| note | text | Nullable. |
| external_ref | text | Optional customer/reference number. |
| reversed_transaction_id | uuid | Nullable self-reference. |
| created_at | timestamptz | Default `now()`. |
| updated_at | timestamptz | Default `now()`. |
| deleted_at | timestamptz | Nullable only for unsynced/local cleanup; avoid deleting posted remote rows. |
| client_updated_at | timestamptz | Set by app. |

### ledger_lines

Represents signed account movements. Sum by account gives balance.

| Column | Type | Notes |
| --- | --- | --- |
| id | uuid | Primary key. |
| user_id | uuid | References `auth.users.id`. |
| shop_id | uuid | References `shops.id`. |
| transaction_id | uuid | References `ledger_transactions.id`. |
| account_id | uuid | References `accounts.id`. |
| amount_paisa | bigint | Signed. Positive increases account; negative decreases account. |
| memo | text | Nullable. |
| created_at | timestamptz | Default `now()`. |
| updated_at | timestamptz | Default `now()`. |
| deleted_at | timestamptz | Nullable. |
| client_updated_at | timestamptz | Set by app. |

Recommended constraints:

- `amount_paisa <> 0`
- `transaction_id` must belong to same `user_id` and `shop_id`
- `account_id` must belong to same `user_id` and `shop_id`

### expense_categories

Stores user-editable categories.

| Column | Type | Notes |
| --- | --- | --- |
| id | uuid | Primary key. |
| user_id | uuid | References `auth.users.id`. |
| shop_id | uuid | References `shops.id`. |
| name | text | Required. |
| icon | text | Nullable. |
| sort_order | integer | Default `0`. |
| is_system | boolean | Default `false`. |
| created_at | timestamptz | Default `now()`. |
| updated_at | timestamptz | Default `now()`. |
| deleted_at | timestamptz | Nullable. |
| client_updated_at | timestamptz | Set by app. |

Expense entries are still posted through `ledger_transactions` and `ledger_lines`; this table only names categories.

### daily_closings

Stores confirmed end-of-day snapshots.

| Column | Type | Notes |
| --- | --- | --- |
| id | uuid | Primary key. |
| user_id | uuid | References `auth.users.id`. |
| shop_id | uuid | References `shops.id`. |
| business_date | date | Unique per shop. |
| total_in_paisa | bigint | Derived and saved at closing time. |
| total_out_paisa | bigint | Derived and saved at closing time. |
| total_expense_paisa | bigint | Derived and saved at closing time. |
| net_change_paisa | bigint | Derived and saved at closing time. |
| closing_snapshot_json | jsonb | Account balances and category totals. |
| closed_at | timestamptz | Required. |
| reopened_at | timestamptz | Nullable. |
| note | text | Nullable. |
| created_at | timestamptz | Default `now()`. |
| updated_at | timestamptz | Default `now()`. |
| deleted_at | timestamptz | Nullable. |
| client_updated_at | timestamptz | Set by app. |

### sync_outbox

Local-only table. Do not create this in Supabase unless debugging requires it.

| Column | Type | Notes |
| --- | --- | --- |
| id | text | Primary key. |
| table_name | text | Target table. |
| record_id | text | Target record ID. |
| operation | sync_operation | Insert, update, or delete. |
| payload_json | text | Serialized row/change. |
| created_at | datetime | Local time. |
| attempt_count | integer | Default `0`. |
| last_attempt_at | datetime | Nullable. |
| last_error | text | Nullable. |
| synced_at | datetime | Nullable. |

### sync_state

Local-only table.

| Column | Type | Notes |
| --- | --- | --- |
| key | text | Primary key. |
| value | text | Timestamp or serialized state. |
| updated_at | datetime | Local time. |

### app_settings

Local-first settings, optionally synced later.

| Column | Type | Notes |
| --- | --- | --- |
| key | text | Primary key. |
| value | text | Serialized value. |
| updated_at | datetime | Local time. |

## 5. Common Ledger Postings

### Opening Balance

Set initial cash balance of PKR 10,000:

| Account | Amount |
| --- | ---: |
| Cash | +1,000,000 |
| Owner Equity | -1,000,000 |

### Transfer Cash to EasyPaisa

Move PKR 5,000 from Cash to EasyPaisa:

| Account | Amount |
| --- | ---: |
| Cash | -500,000 |
| EasyPaisa | +500,000 |

### Expense Paid from Cash

Pay PKR 1,200 electricity from Cash:

| Account | Amount |
| --- | ---: |
| Cash | -120,000 |
| Electricity Expense | +120,000 |

### Cash In

Customer gives PKR 2,000 cash for wallet service:

| Account | Amount |
| --- | ---: |
| Cash | +200,000 |
| Owner Equity or Service Clearing | -200,000 |

MVP can use a system balancing account for simple inflow/outflow categories. Later, this can evolve into commission/revenue tracking.

## 6. Indexes

Recommended Supabase indexes:

```sql
create index accounts_user_shop_idx on accounts (user_id, shop_id) where deleted_at is null;
create index ledger_transactions_user_shop_date_idx on ledger_transactions (user_id, shop_id, business_date);
create index ledger_transactions_updated_idx on ledger_transactions (user_id, updated_at);
create index ledger_lines_account_idx on ledger_lines (user_id, shop_id, account_id);
create index ledger_lines_transaction_idx on ledger_lines (transaction_id);
create index ledger_lines_updated_idx on ledger_lines (user_id, updated_at);
create unique index daily_closings_unique_day_idx on daily_closings (shop_id, business_date) where deleted_at is null;
```

## 7. Row Level Security Policy Pattern

Every user-owned table should enable RLS and use policies like:

```sql
alter table accounts enable row level security;

create policy "Users can read own accounts"
on accounts for select
using (auth.uid() = user_id);

create policy "Users can insert own accounts"
on accounts for insert
with check (auth.uid() = user_id);

create policy "Users can update own accounts"
on accounts for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);
```

Apply the same pattern to `shops`, `ledger_transactions`, `ledger_lines`, `expense_categories`, and `daily_closings`.

## 8. Migration Order

1. Enums.
2. `profiles`.
3. `shops`.
4. `accounts`.
5. `expense_categories`.
6. `ledger_transactions`.
7. `ledger_lines`.
8. `daily_closings`.
9. Indexes.
10. RLS policies.
11. Triggers for `updated_at`.
