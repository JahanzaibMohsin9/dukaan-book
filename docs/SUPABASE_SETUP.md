# Supabase Setup

## Project

Create a Supabase project for Dukaan Book and copy the project URL and anon key into `.env`:

```bash
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

The app can boot without these values in development, but auth and sync require them.

## Auth Redirect URLs (Important)

If your confirmation email link shows `localhost`, Supabase Auth URL config is not set for mobile deep links.

In Supabase dashboard, go to **Authentication -> URL Configuration** and set:

- Site URL: your real app/web URL (do not keep `http://localhost:3000` in production).
- Additional Redirect URLs: `dukaanbook://auth-callback/`

This app sends `emailRedirectTo` as `dukaanbook://auth-callback/` on sign-up, and both Android/iOS are configured to handle that deep link.

## Migration

Apply the SQL migration in:

```text
supabase/migrations/202604130001_initial_schema.sql
```

The migration creates:

- User-owned business tables from `docs/DATABASE_SCHEMA.md`.
- PostgreSQL enums for account type, ledger kind, and ledger status.
- Indexes for sync, account balances, and daily reports.
- Row Level Security policies scoped to `auth.uid()`.
- `updated_at` triggers for mutable tables.

## Seed Defaults

Default accounts and expense categories are created per shop during onboarding so they carry the correct `user_id` and `shop_id`.

Accounts:

- Cash
- EasyPaisa
- JazzCash
- NayaPay
- Bank
- Owner Equity

Expense categories:

- Rent
- Electricity
- Internet
- Supplies
- Staff
- Other

## RLS Check

After applying the migration, test with two authenticated users before shipping:

1. User A creates a shop and account.
2. User B queries `shops` and `accounts`.
3. User B must not see User A rows.
4. User B must not be able to insert or update rows with User A's `user_id`.
