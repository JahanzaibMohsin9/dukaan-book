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
