create table if not exists shop_members (
  id uuid primary key,
  shop_id uuid not null references shops (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'staff',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  client_updated_at timestamptz not null default now()
);

create unique index if not exists shop_members_user_shop_idx
on shop_members (user_id, shop_id)
where deleted_at is null;

create index if not exists shop_members_shop_idx
on shop_members (shop_id, user_id)
where deleted_at is null;

create trigger shop_members_set_updated_at before update on shop_members
for each row execute function set_updated_at();

insert into shop_members (
  id,
  shop_id,
  user_id,
  role,
  created_at,
  updated_at,
  client_updated_at
)
select
  gen_random_uuid(),
  id,
  user_id,
  'owner',
  created_at,
  updated_at,
  updated_at
from shops
where deleted_at is null
on conflict do nothing;

alter table shop_members enable row level security;

drop policy if exists "Shop members can read memberships" on shop_members;
create policy "Shop members can read memberships" on shop_members
for select using (
  user_id = auth.uid()
  or exists (
    select 1
    from shop_members sm
    where sm.shop_id = shop_members.shop_id
      and sm.user_id = auth.uid()
      and sm.deleted_at is null
  )
);

drop policy if exists "Users can insert own membership" on shop_members;
create policy "Users can insert own membership" on shop_members
for insert with check (user_id = auth.uid());

drop policy if exists "Members can update own membership" on shop_members;
create policy "Members can update own membership" on shop_members
for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Shop members can read shops" on shops;
create policy "Shop members can read shops" on shops
for select using (
  auth.uid() = user_id
  or exists (
    select 1
    from shop_members sm
    where sm.shop_id = shops.id
      and sm.user_id = auth.uid()
      and sm.deleted_at is null
  )
);

drop policy if exists "Shop members can read accounts" on accounts;
create policy "Shop members can read accounts" on accounts
for select using (
  exists (
    select 1
    from shop_members sm
    where sm.shop_id = accounts.shop_id
      and sm.user_id = auth.uid()
      and sm.deleted_at is null
  )
);

drop policy if exists "Shop members can insert accounts" on accounts;
create policy "Shop members can insert accounts" on accounts
for insert with check (
  user_id = auth.uid()
  and exists (
    select 1
    from shop_members sm
    where sm.shop_id = accounts.shop_id
      and sm.user_id = auth.uid()
      and sm.deleted_at is null
  )
);

drop policy if exists "Shop members can update accounts" on accounts;
create policy "Shop members can update accounts" on accounts
for update using (
  exists (
    select 1
    from shop_members sm
    where sm.shop_id = accounts.shop_id
      and sm.user_id = auth.uid()
      and sm.deleted_at is null
  )
) with check (
  exists (
    select 1
    from shop_members sm
    where sm.shop_id = accounts.shop_id
      and sm.user_id = auth.uid()
      and sm.deleted_at is null
  )
);

drop policy if exists "Shop members can read expense categories" on expense_categories;
create policy "Shop members can read expense categories" on expense_categories
for select using (
  exists (
    select 1
    from shop_members sm
    where sm.shop_id = expense_categories.shop_id
      and sm.user_id = auth.uid()
      and sm.deleted_at is null
  )
);

drop policy if exists "Shop members can insert expense categories" on expense_categories;
create policy "Shop members can insert expense categories" on expense_categories
for insert with check (
  user_id = auth.uid()
  and exists (
    select 1
    from shop_members sm
    where sm.shop_id = expense_categories.shop_id
      and sm.user_id = auth.uid()
      and sm.deleted_at is null
  )
);

drop policy if exists "Shop members can update expense categories" on expense_categories;
create policy "Shop members can update expense categories" on expense_categories
for update using (
  exists (
    select 1
    from shop_members sm
    where sm.shop_id = expense_categories.shop_id
      and sm.user_id = auth.uid()
      and sm.deleted_at is null
  )
) with check (
  exists (
    select 1
    from shop_members sm
    where sm.shop_id = expense_categories.shop_id
      and sm.user_id = auth.uid()
      and sm.deleted_at is null
  )
);

drop policy if exists "Shop members can read ledger transactions" on ledger_transactions;
create policy "Shop members can read ledger transactions" on ledger_transactions
for select using (
  exists (
    select 1
    from shop_members sm
    where sm.shop_id = ledger_transactions.shop_id
      and sm.user_id = auth.uid()
      and sm.deleted_at is null
  )
);

drop policy if exists "Shop members can insert ledger transactions" on ledger_transactions;
create policy "Shop members can insert ledger transactions" on ledger_transactions
for insert with check (
  user_id = auth.uid()
  and exists (
    select 1
    from shop_members sm
    where sm.shop_id = ledger_transactions.shop_id
      and sm.user_id = auth.uid()
      and sm.deleted_at is null
  )
);

drop policy if exists "Shop members can update ledger transactions" on ledger_transactions;
create policy "Shop members can update ledger transactions" on ledger_transactions
for update using (
  exists (
    select 1
    from shop_members sm
    where sm.shop_id = ledger_transactions.shop_id
      and sm.user_id = auth.uid()
      and sm.deleted_at is null
  )
) with check (
  exists (
    select 1
    from shop_members sm
    where sm.shop_id = ledger_transactions.shop_id
      and sm.user_id = auth.uid()
      and sm.deleted_at is null
  )
);

drop policy if exists "Shop members can read ledger lines" on ledger_lines;
create policy "Shop members can read ledger lines" on ledger_lines
for select using (
  exists (
    select 1
    from shop_members sm
    where sm.shop_id = ledger_lines.shop_id
      and sm.user_id = auth.uid()
      and sm.deleted_at is null
  )
);

drop policy if exists "Shop members can insert ledger lines" on ledger_lines;
create policy "Shop members can insert ledger lines" on ledger_lines
for insert with check (
  user_id = auth.uid()
  and exists (
    select 1
    from shop_members sm
    where sm.shop_id = ledger_lines.shop_id
      and sm.user_id = auth.uid()
      and sm.deleted_at is null
  )
);

drop policy if exists "Shop members can update ledger lines" on ledger_lines;
create policy "Shop members can update ledger lines" on ledger_lines
for update using (
  exists (
    select 1
    from shop_members sm
    where sm.shop_id = ledger_lines.shop_id
      and sm.user_id = auth.uid()
      and sm.deleted_at is null
  )
) with check (
  exists (
    select 1
    from shop_members sm
    where sm.shop_id = ledger_lines.shop_id
      and sm.user_id = auth.uid()
      and sm.deleted_at is null
  )
);
