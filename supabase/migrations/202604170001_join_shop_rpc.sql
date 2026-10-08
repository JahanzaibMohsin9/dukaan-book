create or replace function public.is_shop_member(target_shop_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.shop_members sm
    where sm.shop_id = target_shop_id
      and sm.user_id = auth.uid()
      and sm.deleted_at is null
  );
$$;

revoke all on function public.is_shop_member(uuid) from public;
grant execute on function public.is_shop_member(uuid) to authenticated;

create or replace function public.join_shop(
  p_shop_id uuid,
  p_full_name text default null,
  p_phone text default null,
  p_membership_id uuid default gen_random_uuid()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  joined_shop shops%rowtype;
  joined_member shop_members%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Sign in before joining a shop.';
  end if;

  select *
    into joined_shop
  from shops
  where id = p_shop_id
    and deleted_at is null;

  if not found then
    raise exception 'Shop not found. Check the shared shop ID.';
  end if;

  insert into profiles (
    id,
    full_name,
    phone,
    preferred_language
  )
  values (
    auth.uid(),
    nullif(btrim(p_full_name), ''),
    nullif(btrim(p_phone), ''),
    'en'
  )
  on conflict (id) do update set
    full_name = excluded.full_name,
    phone = excluded.phone,
    preferred_language = excluded.preferred_language;

  insert into shop_members (
    id,
    shop_id,
    user_id,
    role,
    client_updated_at
  )
  values (
    p_membership_id,
    joined_shop.id,
    auth.uid(),
    'staff',
    now()
  )
  on conflict (user_id, shop_id) where deleted_at is null do update set
    role = shop_members.role,
    updated_at = now(),
    client_updated_at = now()
  returning * into joined_member;

  return jsonb_build_object(
    'shop', to_jsonb(joined_shop),
    'membership', to_jsonb(joined_member),
    'accounts', coalesce(
      (
        select jsonb_agg(to_jsonb(a) order by a.sort_order, a.created_at)
        from accounts a
        where a.shop_id = joined_shop.id
          and a.deleted_at is null
      ),
      '[]'::jsonb
    ),
    'expense_categories', coalesce(
      (
        select jsonb_agg(to_jsonb(c) order by c.sort_order, c.created_at)
        from expense_categories c
        where c.shop_id = joined_shop.id
          and c.deleted_at is null
      ),
      '[]'::jsonb
    )
  );
end;
$$;

revoke all on function public.join_shop(uuid, text, text, uuid) from public;
grant execute on function public.join_shop(uuid, text, text, uuid) to authenticated;

drop policy if exists "Shop members can read memberships" on shop_members;
create policy "Shop members can read memberships" on shop_members
for select using (
  user_id = auth.uid()
  or public.is_shop_member(shop_members.shop_id)
);

drop policy if exists "Shop members can read shops" on shops;
create policy "Shop members can read shops" on shops
for select using (
  auth.uid() = user_id
  or public.is_shop_member(shops.id)
);

drop policy if exists "Shop members can read accounts" on accounts;
create policy "Shop members can read accounts" on accounts
for select using (
  public.is_shop_member(accounts.shop_id)
);

drop policy if exists "Shop members can insert accounts" on accounts;
create policy "Shop members can insert accounts" on accounts
for insert with check (
  user_id = auth.uid()
  and public.is_shop_member(accounts.shop_id)
);

drop policy if exists "Shop members can update accounts" on accounts;
create policy "Shop members can update accounts" on accounts
for update using (
  public.is_shop_member(accounts.shop_id)
) with check (
  public.is_shop_member(accounts.shop_id)
);

drop policy if exists "Shop members can read expense categories" on expense_categories;
create policy "Shop members can read expense categories" on expense_categories
for select using (
  public.is_shop_member(expense_categories.shop_id)
);

drop policy if exists "Shop members can insert expense categories" on expense_categories;
create policy "Shop members can insert expense categories" on expense_categories
for insert with check (
  user_id = auth.uid()
  and public.is_shop_member(expense_categories.shop_id)
);

drop policy if exists "Shop members can update expense categories" on expense_categories;
create policy "Shop members can update expense categories" on expense_categories
for update using (
  public.is_shop_member(expense_categories.shop_id)
) with check (
  public.is_shop_member(expense_categories.shop_id)
);

drop policy if exists "Shop members can read ledger transactions" on ledger_transactions;
create policy "Shop members can read ledger transactions" on ledger_transactions
for select using (
  public.is_shop_member(ledger_transactions.shop_id)
);

drop policy if exists "Shop members can insert ledger transactions" on ledger_transactions;
create policy "Shop members can insert ledger transactions" on ledger_transactions
for insert with check (
  user_id = auth.uid()
  and public.is_shop_member(ledger_transactions.shop_id)
);

drop policy if exists "Shop members can update ledger transactions" on ledger_transactions;
create policy "Shop members can update ledger transactions" on ledger_transactions
for update using (
  public.is_shop_member(ledger_transactions.shop_id)
) with check (
  public.is_shop_member(ledger_transactions.shop_id)
);

drop policy if exists "Shop members can read ledger lines" on ledger_lines;
create policy "Shop members can read ledger lines" on ledger_lines
for select using (
  public.is_shop_member(ledger_lines.shop_id)
);

drop policy if exists "Shop members can insert ledger lines" on ledger_lines;
create policy "Shop members can insert ledger lines" on ledger_lines
for insert with check (
  user_id = auth.uid()
  and public.is_shop_member(ledger_lines.shop_id)
);

drop policy if exists "Shop members can update ledger lines" on ledger_lines;
create policy "Shop members can update ledger lines" on ledger_lines
for update using (
  public.is_shop_member(ledger_lines.shop_id)
) with check (
  public.is_shop_member(ledger_lines.shop_id)
);

drop policy if exists "Shop members can read daily closings" on daily_closings;
create policy "Shop members can read daily closings" on daily_closings
for select using (
  public.is_shop_member(daily_closings.shop_id)
);

drop policy if exists "Shop members can insert daily closings" on daily_closings;
create policy "Shop members can insert daily closings" on daily_closings
for insert with check (
  user_id = auth.uid()
  and public.is_shop_member(daily_closings.shop_id)
);

drop policy if exists "Shop members can update daily closings" on daily_closings;
create policy "Shop members can update daily closings" on daily_closings
for update using (
  public.is_shop_member(daily_closings.shop_id)
) with check (
  public.is_shop_member(daily_closings.shop_id)
);
