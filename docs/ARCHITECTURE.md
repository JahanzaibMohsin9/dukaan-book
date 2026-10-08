# Dukaan Book Architecture

## 1. Product Summary

Dukaan Book is an offline-first mobile ledger app for small EasyPaisa/JazzCash/mobile-wallet shop owners in Pakistan. The app helps a shopkeeper record every cash, wallet, bank, expense, and transfer movement during the day and then close the day with a reliable summary.

The main user is usually one shopkeeper using one Android phone with unreliable internet. The app must stay fast, simple, and trustworthy when offline.

## 2. Goals

- Record cash-in, cash-out, wallet load, withdrawal, bank, transfer, and expense activity quickly.
- Maintain balances for cash, EasyPaisa, JazzCash, NayaPay, bank, and custom accounts.
- Work fully offline and sync later without blocking the user.
- Generate daily closing reports with totals, balance by account, expenses, and PDF/share support.
- Keep the cloud stack free or very low-cost during MVP.
- Protect user data with authentication, row-level security, and local app lock.

## 3. Non-Goals for MVP

- No payment processing.
- No direct EasyPaisa/JazzCash API integration.
- No real-time multi-user collaboration.
- No backend push notifications.
- No web dashboard.
- No inventory management in the first release.

## 4. Technology Stack

| Layer | Choice | Reason |
| --- | --- | --- |
| Mobile app | Flutter | One codebase for Android first, iOS later. |
| State management | Riverpod | Predictable feature-level state, testable providers. |
| Navigation | GoRouter | Declarative routes and guarded auth flows. |
| Local database | SQLite via Drift | Relational data, transactions, migrations, strong queries, better fit than Hive for ledger data. |
| Remote backend | Supabase | Free tier, PostgreSQL, Auth, Storage, Row Level Security. |
| Sync | Custom outbox + pull sync | Required because Supabase does not provide built-in offline sync like Firestore. |
| IDs | UUID v7 or ULID | Client-generated sortable IDs, useful offline. |
| Money values | Integer paisa | Avoid floating point errors. PKR 100.50 is stored as `10050`. |
| Notifications | flutter_local_notifications | Local daily reminders without Firebase. |
| Reports | pdf, printing, share_plus | PDF export and WhatsApp sharing. |
| Charts | fl_chart | Weekly/monthly visual summaries. |
| App lock | local_auth + secure storage | PIN/biometric protection after MVP basics are stable. |

## 5. Architecture Style

Use feature-first clean architecture:

```text
lib/
  app/
    router/
    theme/
    bootstrap/
  core/
    config/
    database/
    errors/
    money/
    network/
    sync/
    time/
    widgets/
  features/
    auth/
    onboarding/
    accounts/
    ledger/
    expenses/
    dashboard/
    reports/
    settings/
```

Each feature should follow this internal structure when needed:

```text
features/<feature>/
  data/
    datasources/
    repositories/
    mappers/
  domain/
    entities/
    repositories/
    usecases/
  presentation/
    controllers/
    screens/
    widgets/
```

Small features may skip unnecessary layers, but the app should keep business rules out of widgets.

## 6. Core Domain Model

The app should be modeled as a ledger rather than as separate transaction and expense tables that directly mutate account balances. A ledger-line model keeps financial history auditable.

### Key Concepts

- **Account**: A cash box, wallet, bank account, expense bucket, or owner-equity account.
- **Ledger transaction**: A business event such as "cash deposit", "wallet load", "send money", "shop rent expense", or "transfer from cash to EasyPaisa".
- **Ledger line**: One signed movement inside a transaction. Positive lines increase an account balance; negative lines decrease it.
- **Daily closing**: A user-confirmed snapshot for a business date.
- **Sync outbox**: Local queue of changes waiting to be pushed to Supabase.

### Why Ledger Lines

The original idea stored one transaction row with `account_id`, optional `to_account_id`, and a running balance on accounts. That is simple, but it can drift when edits, deletes, retries, or partial sync failures happen.

The improved design stores every money movement as balanced ledger lines. Account balances can be computed from lines and optionally cached. This gives:

- Safer transfers between accounts.
- Clear audit trail.
- Easier reports.
- Better sync conflict handling.
- Cleaner support for expenses without a separate financial model.

## 7. Money Rules

- Store all money as signed integer paisa in database columns named `amount_paisa`.
- Display money as PKR with separators, for example `PKR 12,500`.
- Never use `double` for stored balances or calculations.
- Prevent zero-amount ledger lines.
- Prevent user-facing transaction save when required lines do not balance according to transaction kind.
- Use Pakistan local business date by default, with app timezone set to `Asia/Karachi`.

## 8. Local Database

Use Drift tables mirroring the remote schema closely:

- `profiles`
- `shops`
- `accounts`
- `ledger_transactions`
- `ledger_lines`
- `expense_categories`
- `daily_closings`
- `sync_outbox`
- `sync_state`
- `app_settings`

Local writes happen inside SQLite transactions:

1. Insert or update domain rows.
2. Insert an outbox item in the same database transaction.
3. Update local projections/cache if used.
4. Return success to UI immediately.

## 9. Remote Backend

Supabase contains the same business tables with Row Level Security. Every business table has:

- `id`
- `user_id`
- `shop_id`
- `created_at`
- `updated_at`
- `deleted_at`
- `client_updated_at`

Use soft deletes for syncable entities. Avoid physical deletion except for local cache cleanup.

## 10. Sync Strategy

### Push

1. User creates/updates/deletes data locally.
2. Local database writes the data and an outbox operation atomically.
3. When online, sync service reads pending outbox records ordered by creation time.
4. Sync service upserts each change to Supabase.
5. On success, mark outbox record as synced.
6. On failure, record retry count and last error.

### Pull

1. Store last successful pull timestamp in `sync_state`.
2. Pull remote rows where `updated_at > last_pull_at`.
3. Apply remote changes locally inside a transaction.
4. Advance `last_pull_at` only after all pulled rows are applied.

### Conflict Policy

For MVP, use last-write-wins by `client_updated_at` for simple profile/account/settings fields.

Ledger transactions should be append-mostly:

- Created ledger transactions can sync normally.
- Editing a synced financial transaction should create a reversal plus replacement, not mutate history.
- Unsynced local transactions can be edited before push.

## 11. Authentication and Onboarding

Use Supabase Auth with email/password for MVP.

Flow:

1. Splash checks local session.
2. If no session, user lands on sign in/sign up.
3. New user creates shop profile.
4. App creates default accounts:
   - Cash
   - EasyPaisa
   - JazzCash
   - NayaPay
   - Bank
5. User enters opening balances.
6. Dashboard opens.

Phone OTP can be evaluated later if Supabase availability and local Pakistan UX justify it.

## 12. Main Screens

### Dashboard

- Today net movement.
- Current total balance.
- Account cards with balances.
- Quick actions: Cash In, Cash Out, Transfer, Expense.
- Unsynced indicator.
- Today activity list.

### Accounts

- Account list.
- Add/edit/deactivate account.
- Account detail with balance and history.
- Opening balance adjustment flow.

### Ledger Entry

- Fast entry form for common shop actions.
- Transaction kind selector.
- Account selector.
- Amount keypad.
- Optional note/customer reference.
- Save offline-first.

### Expenses

- Expense category list.
- Add expense.
- Expense history.
- Expense totals by day/week/month.

### Reports

- Day-end summary.
- Account closing balances.
- Cash-in/cash-out totals.
- Expenses by category.
- Export PDF.
- Share PDF.

### Settings

- Shop profile.
- Default accounts.
- Notification time.
- Backup/sync status.
- App lock.
- Language.

## 13. Reporting Rules

Daily reports use `business_date`, not raw UTC dates. The default day boundary is midnight in `Asia/Karachi`, with an optional future setting for custom shop closing time.

Reports should include:

- Opening balance by account.
- Closing balance by account.
- Total inflow.
- Total outflow.
- Expenses by category.
- Transfers count and total.
- Net change.
- Unsynced warning if report includes local-only records.

## 14. Notifications

All notifications are local:

- Daily closing reminder at user-selected time, default 9:00 PM.
- Unsynced data reminder if offline/pending for more than 24 hours.
- Optional low-balance alert after account save.
- Optional large transaction alert after entry save.

## 15. Testing Strategy

Prioritize deterministic business logic tests:

- Money formatting and parsing.
- Ledger-line balance calculations.
- Transfer creation.
- Expense posting.
- Daily report aggregation.
- Sync outbox lifecycle.
- Conflict handling.

Add widget tests for:

- Dashboard totals.
- Entry form validation.
- Day-end report rendering.

Add integration tests for:

- Onboarding to dashboard.
- Add transaction while offline.
- Sync pending transaction.
- Export report.
