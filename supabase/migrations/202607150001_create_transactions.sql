create table if not exists public.transactions (
  id text primary key,
  kind text not null default 'Expense' check (kind in ('Expense', 'Income')),
  transaction_date date not null,
  category text not null,
  payment_method text not null,
  paid_by text not null,
  amount numeric(14, 2) not null check (amount >= 0),
  description text not null,
  proof_url text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.transactions enable row level security;

-- The current app retains its existing shared-login behavior. These policies let
-- the browser client perform CRUD with the publishable key. Move to Supabase Auth
-- and authenticated-only policies before making the application publicly known.
drop policy if exists "Shared ledger can read transactions" on public.transactions;
create policy "Shared ledger can read transactions" on public.transactions for select to anon using (true);
drop policy if exists "Shared ledger can add transactions" on public.transactions;
create policy "Shared ledger can add transactions" on public.transactions for insert to anon with check (true);
drop policy if exists "Shared ledger can update transactions" on public.transactions;
create policy "Shared ledger can update transactions" on public.transactions for update to anon using (true) with check (true);
drop policy if exists "Shared ledger can delete transactions" on public.transactions;
create policy "Shared ledger can delete transactions" on public.transactions for delete to anon using (true);

-- Idempotent import of the current monthly JSON source of truth. Existing rows
-- are never overwritten, so this is safe to run again after the app is live.
insert into public.transactions
  (id, kind, transaction_date, category, payment_method, paid_by, amount, description, proof_url)
values
  ('EXP-001', 'Expense', '2026-06-05', 'Domain', 'Virtual', 'Pasindu', 12000, 'Domain registration for platform', ''),
  ('EXP-002', 'Expense', '2026-06-06', 'NFC Reader', 'Physical', 'Pradeep', 18500, 'NFC card reader for gate ticket validation', ''),
  ('EXP-003', 'Expense', '2026-06-06', 'Travel', 'Physical', 'Pasindu', 3500, 'Travel cost for business meeting', '')
on conflict (id) do nothing;
