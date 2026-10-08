create extension if not exists pgcrypto;

create type account_type as enum (
  'cash',
  'easypaisa',
  'jazzcash',
  'nayapay',
  'bank',
  'expense',
  'owner_equity',
  'custom'
);

create type ledger_transaction_kind as enum (
  'opening_balance',
  'cash_in',
  'cash_out',
  'wallet_load',
  'withdrawal',
  'transfer',
  'expense',
  'adjustment',
  'reversal'
);

create type ledger_status as enum ('draft', 'posted', 'reversed');

create table profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  phone text,
  preferred_language text not null default 'en',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table shops (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  city text,
  phone text,
  timezone text not null default 'Asia/Karachi',
  day_close_time time not null default '21:00',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table accounts (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  shop_id uuid not null references shops (id) on delete cascade,
  name text not null,
  type account_type not null,
  color_hex text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  is_system boolean not null default false,
  low_balance_threshold_paisa bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  client_updated_at timestamptz not null default now()
);

create table expense_categories (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  shop_id uuid not null references shops (id) on delete cascade,
  name text not null,
  icon text,
  sort_order integer not null default 0,
  is_system boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  client_updated_at timestamptz not null default now()
);

create table ledger_transactions (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  shop_id uuid not null references shops (id) on delete cascade,
  kind ledger_transaction_kind not null,
  status ledger_status not null default 'posted',
  business_date date not null,
  note text,
  external_ref text,
  reversed_transaction_id uuid references ledger_transactions (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  client_updated_at timestamptz not null default now()
);

create table ledger_lines (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  shop_id uuid not null references shops (id) on delete cascade,
  transaction_id uuid not null references ledger_transactions (id) on delete cascade,
  account_id uuid not null references accounts (id),
  amount_paisa bigint not null check (amount_paisa <> 0),
  memo text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  client_updated_at timestamptz not null default now()
);

create table daily_closings (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  shop_id uuid not null references shops (id) on delete cascade,
  business_date date not null,
  total_in_paisa bigint not null,
  total_out_paisa bigint not null,
  total_expense_paisa bigint not null,
  net_change_paisa bigint not null,
  closing_snapshot_json jsonb not null,
  closed_at timestamptz not null,
  reopened_at timestamptz,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  client_updated_at timestamptz not null default now()
);

create index accounts_user_shop_idx on accounts (user_id, shop_id) where deleted_at is null;
create index expense_categories_user_shop_idx on expense_categories (user_id, shop_id) where deleted_at is null;
create index ledger_transactions_user_shop_date_idx on ledger_transactions (user_id, shop_id, business_date);
create index ledger_transactions_updated_idx on ledger_transactions (user_id, updated_at);
create index ledger_lines_account_idx on ledger_lines (user_id, shop_id, account_id);
create index ledger_lines_transaction_idx on ledger_lines (transaction_id);
create index ledger_lines_updated_idx on ledger_lines (user_id, updated_at);
create unique index daily_closings_unique_day_idx on daily_closings (shop_id, business_date) where deleted_at is null;

create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at before update on profiles
for each row execute function set_updated_at();
create trigger shops_set_updated_at before update on shops
for each row execute function set_updated_at();
create trigger accounts_set_updated_at before update on accounts
for each row execute function set_updated_at();
create trigger expense_categories_set_updated_at before update on expense_categories
for each row execute function set_updated_at();
create trigger ledger_transactions_set_updated_at before update on ledger_transactions
for each row execute function set_updated_at();
create trigger ledger_lines_set_updated_at before update on ledger_lines
for each row execute function set_updated_at();
create trigger daily_closings_set_updated_at before update on daily_closings
for each row execute function set_updated_at();

alter table profiles enable row level security;
alter table shops enable row level security;
alter table accounts enable row level security;
alter table expense_categories enable row level security;
alter table ledger_transactions enable row level security;
alter table ledger_lines enable row level security;
alter table daily_closings enable row level security;

create policy "Users can read own profile" on profiles
for select using (auth.uid() = id);
create policy "Users can insert own profile" on profiles
for insert with check (auth.uid() = id);
create policy "Users can update own profile" on profiles
for update using (auth.uid() = id) with check (auth.uid() = id);

create policy "Users can read own shops" on shops
for select using (auth.uid() = user_id);
create policy "Users can insert own shops" on shops
for insert with check (auth.uid() = user_id);
create policy "Users can update own shops" on shops
for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Users can read own accounts" on accounts
for select using (auth.uid() = user_id);
create policy "Users can insert own accounts" on accounts
for insert with check (auth.uid() = user_id);
create policy "Users can update own accounts" on accounts
for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Users can read own expense categories" on expense_categories
for select using (auth.uid() = user_id);
create policy "Users can insert own expense categories" on expense_categories
for insert with check (auth.uid() = user_id);
create policy "Users can update own expense categories" on expense_categories
for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Users can read own ledger transactions" on ledger_transactions
for select using (auth.uid() = user_id);
create policy "Users can insert own ledger transactions" on ledger_transactions
for insert with check (auth.uid() = user_id);
create policy "Users can update own ledger transactions" on ledger_transactions
for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Users can read own ledger lines" on ledger_lines
for select using (auth.uid() = user_id);
create policy "Users can insert own ledger lines" on ledger_lines
for insert with check (auth.uid() = user_id);
create policy "Users can update own ledger lines" on ledger_lines
for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Users can read own daily closings" on daily_closings
for select using (auth.uid() = user_id);
create policy "Users can insert own daily closings" on daily_closings
for insert with check (auth.uid() = user_id);
create policy "Users can update own daily closings" on daily_closings
for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
