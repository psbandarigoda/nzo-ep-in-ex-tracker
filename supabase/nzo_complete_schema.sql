-- nZO Innovations complete database schema
-- Generated 2026-07-15. This is the only authoritative database setup file.
-- Safe for a new Supabase project. Existing live projects should back up before rerunning.
-- Prerequisite: create and confirm the two authorized Auth users.

begin;

-- ===== BASE LEDGER AND CURRENT MIGRATED DATA =====
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

-- One ID format for every transaction: TXN-YYYYMMDD-XXXXXXXX.
create or replace function public.generate_transaction_id(p_date date)
returns text language sql volatile set search_path=public as $$
  select 'TXN-' || to_char(coalesce(p_date,current_date),'YYYYMMDD') || '-' ||
         upper(substr(replace(gen_random_uuid()::text,'-',''),1,8))
$$;

create or replace function public.assign_transaction_id() returns trigger
language plpgsql set search_path=public as $$
begin
  if new.id is null or btrim(new.id)='' then
    new.id := public.generate_transaction_id(new.transaction_date);
  end if;
  return new;
end $$;
drop trigger if exists transactions_assign_id on public.transactions;
create trigger transactions_assign_id before insert on public.transactions
for each row execute function public.assign_transaction_id();

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

-- Idempotent import of the three retained records. Description checks prevent
-- duplicate rows when upgrading a database that still has legacy IDs.
insert into public.transactions
  (id, kind, transaction_date, category, payment_method, paid_by, amount, description, proof_url)
select v.* from (values
  ('TXN-20260617-4DFF5901', 'Expense', '2026-06-17'::date, 'Domain', 'Debit Card', 'Pasindu', 6500::numeric, 'Buy a Domain', ''),
  ('TXN-20260620-325FB267', 'Expense', '2026-06-20'::date, 'NFC Reader', 'Cash', 'Pasindu', 1530::numeric, 'Testing Reader - 01', ''),
  ('TXN-20260620-77B7F4EF', 'Expense', '2026-06-20'::date, 'NFC Cards', 'Cash', 'Pasindu', 250::numeric, 'NFC Testing - 5 Cards', '')
) as v(id,kind,transaction_date,category,payment_method,paid_by,amount,description,proof_url)
where not exists (select 1 from public.transactions t where t.description=v.description)
on conflict (id) do nothing;


-- ===== BUSINESS ACCOUNTING, FOUNDERS, REPORTING AND AUDIT =====
-- nZO complete business accounting upgrade
-- Includes the internal ledger, founders, reporting and auditing.
-- Prerequisite: create and confirm both authorized Supabase Auth users first.

-- ===== BUSINESS ACCOUNTING FOUNDATION =====
-- nZO Internal Business Administration & Accounting Platform (Phase 1)
-- IMPORTANT: create at least one Supabase Auth user before applying this file.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role text not null default 'finance' check (role in ('super_admin', 'finance', 'marketing', 'viewer')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.chart_of_accounts (
  code text primary key,
  name text not null,
  account_type text not null check (account_type in ('Asset', 'Liability', 'Equity', 'Income', 'Expense')),
  parent_code text references public.chart_of_accounts(code),
  description text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.cash_accounts (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  account_type text not null check (account_type in ('Cash', 'Bank', 'Payment Gateway', 'Founder', 'Other')),
  currency text not null default 'LKR' check (currency = 'LKR'),
  opening_balance numeric(14,2) not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.counterparties (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  counterparty_type text not null check (counterparty_type in ('Organizer', 'Venue', 'Supplier', 'Customer', 'Partner', 'Employee', 'Government', 'Other')),
  email text not null default '',
  phone text not null default '',
  tax_id text not null default '',
  notes text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.chart_of_accounts (code, name, account_type, description) values
  ('1000','Cash and cash equivalents','Asset','Company cash, banks and gateway balances'),
  ('1100','Accounts receivable','Asset','Amounts receivable by nZO'),
  ('1500','NFC hardware and equipment','Asset','Capitalised readers, printers and equipment'),
  ('2000','Organizer payables','Liability','Net funds held for organizer settlement'),
  ('2100','Refunds and chargebacks payable','Liability','Approved or pending customer refunds'),
  ('2200','Withholding tax payable','Liability','Optional WHT retained for remittance'),
  ('2300','Deferred card orders and shipping','Liability','Unfulfilled EP card orders'),
  ('3000','Owner equity','Equity','Founder capital and retained earnings'),
  ('4000','Ticket commission','Income','nZO commission on organizer ticket gross'),
  ('4010','Buyer service fees','Income','Checkout service fees paid by buyers'),
  ('4020','Organizer platform fees','Income','Optional organizer/platform fee'),
  ('4030','Reservation service fees','Income','Places to Go table booking fees'),
  ('4040','Reservation cancellation retain','Income','Cancellation amount retained by nZO'),
  ('4050','NFC Passport card sales','Income','Physical Entertain Passport card sales'),
  ('4060','Gate-staff seat fees','Income','Extra gate staff access fees'),
  ('4070','B2B Verification API','Income','PAYG and subscription verification revenue'),
  ('4990','Other income','Income','Miscellaneous operating income'),
  ('5000','Domain, DNS and brand web','Expense','Domains, DNS and corporate web costs'),
  ('5010','Cloud and SaaS','Expense','Vercel, Supabase, CDN, storage and infrastructure'),
  ('5020','NFC hardware and production','Expense','Cards, readers, printing and programming labour'),
  ('5030','Shipping and fulfilment','Expense','Registered post, couriers and packing'),
  ('5040','Payment gateway fees','Expense','WebXPay and other payment processing charges'),
  ('5050','Marketing and growth','Expense','Ads, content, promotions and outreach'),
  ('5060','Travel and field operations','Expense','Meetings, onboarding and gate support'),
  ('5070','Client packaging and distribution','Expense','Flutter/Electron builds, signing and installers'),
  ('5080','Support and operations','Expense','Support channels, contractors and operational staffing'),
  ('5090','Legal, compliance and accounting','Expense','Professional and regulatory costs'),
  ('5095','Company registration and secretarial','Expense','Company incorporation, annual returns, registry and company-secretarial costs'),
  ('5100','Office and administration','Expense','General administration costs'),
  ('5110','R&D and product development','Expense','Research and software/product development'),
  ('5990','Other expenses','Expense','Miscellaneous business expenses')
on conflict (code) do update set name=excluded.name, account_type=excluded.account_type, description=excluded.description;

insert into public.cash_accounts (name, account_type) values
  ('Company cash on hand','Cash'), ('Company bank account','Bank'),
  ('Payment gateway clearing','Payment Gateway'), ('Pasindu personal account','Founder'),
  ('Wicky personal account','Founder')
on conflict (name) do nothing;

alter table public.transactions add column if not exists account_code text references public.chart_of_accounts(code);
alter table public.transactions add column if not exists cash_account_id uuid references public.cash_accounts(id);
alter table public.transactions add column if not exists counterparty_id uuid references public.counterparties(id);
alter table public.transactions add column if not exists reference_no text not null default '';
alter table public.transactions add column if not exists status text not null default 'Posted' check (status in ('Draft','Posted','Void'));
alter table public.transactions add column if not exists notes text not null default '';
alter table public.transactions add column if not exists tax_amount numeric(14,2) not null default 0 check (tax_amount >= 0);
alter table public.transactions add column if not exists created_by uuid references auth.users(id);
alter table public.transactions add column if not exists updated_by uuid references auth.users(id);
alter table public.transactions add column if not exists entry_type text not null default 'Operating Expense';

update public.transactions set account_code = case
  when kind='Income' and category ilike '%commission%' then '4000'
  when kind='Income' and category ilike '%ticket%' then '4010'
  when kind='Income' and category ilike '%B2B%' then '4070'
  when kind='Income' then '4990'
  when category in ('Domain') then '5000'
  when category in ('Database','Hosting') then '5010'
  when category in ('NFC Reader','NFC Cards') then '5020'
  when category in ('Marketing') then '5050'
  when category in ('Travel','Meeting') then '5060'
  when category in ('Legal','Accounting') then '5090'
  when category in ('Development') then '5110'
  else '5990' end
where account_code is null;

update public.transactions set entry_type=case when kind='Income' then 'Operating Income' else 'Operating Expense' end
where entry_type in ('Operating Expense','');

create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  table_name text not null,
  record_id text not null,
  action text not null check (action in ('INSERT','UPDATE','DELETE')),
  old_data jsonb,
  new_data jsonb,
  changed_by uuid,
  changed_at timestamptz not null default now()
);

create or replace function public.audit_transaction_change() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.audit_logs(table_name,record_id,action,old_data,new_data,changed_by)
  values ('transactions',coalesce(new.id,old.id),tg_op,case when tg_op <> 'INSERT' then to_jsonb(old) end,case when tg_op <> 'DELETE' then to_jsonb(new) end,auth.uid());
  return coalesce(new,old);
end $$;
drop trigger if exists transactions_audit on public.transactions;
create trigger transactions_audit after insert or update or delete on public.transactions for each row execute function public.audit_transaction_change();

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,full_name,role,is_active)
  values(
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name',new.email),
    case when lower(new.email) in ('bgpsandaruwan@gmail.com','wickycinema@gmail.com') then 'super_admin' else 'finance' end,
    lower(new.email) in ('bgpsandaruwan@gmail.com','wickycinema@gmail.com')
  ) on conflict(id) do update set is_active=excluded.is_active;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();
insert into public.profiles(id,full_name,role,is_active)
select id,coalesce(raw_user_meta_data->>'full_name',email),
  case when lower(email) in ('bgpsandaruwan@gmail.com','wickycinema@gmail.com') then 'super_admin' else 'finance' end,
  lower(email) in ('bgpsandaruwan@gmail.com','wickycinema@gmail.com')
from auth.users on conflict(id) do update set role=excluded.role,is_active=excluded.is_active;

create or replace function public.is_active_staff() returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from profiles where id=auth.uid() and is_active) $$;

alter table public.profiles enable row level security;
alter table public.chart_of_accounts enable row level security;
alter table public.cash_accounts enable row level security;
alter table public.counterparties enable row level security;
alter table public.audit_logs enable row level security;

drop policy if exists "Shared ledger can read transactions" on public.transactions;
drop policy if exists "Shared ledger can add transactions" on public.transactions;
drop policy if exists "Shared ledger can update transactions" on public.transactions;
drop policy if exists "Shared ledger can delete transactions" on public.transactions;
drop policy if exists "Staff read transactions" on public.transactions;
drop policy if exists "Staff add transactions" on public.transactions;
drop policy if exists "Staff update transactions" on public.transactions;
drop policy if exists "Staff delete transactions" on public.transactions;
drop policy if exists "Staff read accounts" on public.chart_of_accounts;
drop policy if exists "Staff read cash accounts" on public.cash_accounts;
drop policy if exists "Staff manage counterparties" on public.counterparties;
drop policy if exists "Staff read audit" on public.audit_logs;
drop policy if exists "Users read own profile" on public.profiles;
create policy "Staff read transactions" on public.transactions for select to authenticated using (public.is_active_staff());
create policy "Staff add transactions" on public.transactions for insert to authenticated with check (public.is_active_staff());
create policy "Staff update transactions" on public.transactions for update to authenticated using (public.is_active_staff()) with check (public.is_active_staff());
create policy "Staff delete transactions" on public.transactions for delete to authenticated using (public.is_active_staff());
create policy "Staff read accounts" on public.chart_of_accounts for select to authenticated using (public.is_active_staff());
create policy "Staff read cash accounts" on public.cash_accounts for select to authenticated using (public.is_active_staff());
create policy "Staff manage counterparties" on public.counterparties for all to authenticated using (public.is_active_staff()) with check (public.is_active_staff());
create policy "Staff read audit" on public.audit_logs for select to authenticated using (public.is_active_staff());
create policy "Users read own profile" on public.profiles for select to authenticated using (id=auth.uid());


-- ===== DOUBLE-ENTRY AND FOUNDER ACCOUNTING =====
-- nZO double-entry accounting and 50/50 founder governance.
-- Run after 003_business_accounting.sql.

create table if not exists public.company_settings (
  id boolean primary key default true check (id),
  legal_name text not null default 'nZO Innovations (Pvt) Ltd',
  trading_name text not null default 'Entertain Passport',
  base_currency text not null default 'LKR' check (base_currency='LKR'),
  financial_year_start_month smallint not null default 4 check (financial_year_start_month between 1 and 12),
  reporting_framework text not null default 'SLFRS for SMEs',
  updated_at timestamptz not null default now()
);
insert into public.company_settings(id) values(true) on conflict(id) do nothing;

create table if not exists public.founders (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  full_name text not null,
  position text not null default 'Director',
  ownership_percent numeric(5,2) not null check (ownership_percent > 0 and ownership_percent <= 100),
  profile_id uuid unique references public.profiles(id),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
insert into public.founders(code,full_name,position,ownership_percent,profile_id)
select 'PASINDU','Pasindu','Director',50,p.id from public.profiles p join auth.users u on u.id=p.id where lower(u.email)='bgpsandaruwan@gmail.com'
on conflict(code) do update set ownership_percent=50,position='Director',profile_id=excluded.profile_id;
insert into public.founders(code,full_name,position,ownership_percent,profile_id)
select 'WICKY','Wicky','Director',50,p.id from public.profiles p join auth.users u on u.id=p.id where lower(u.email)='wickycinema@gmail.com'
on conflict(code) do update set ownership_percent=50,position='Director',profile_id=excluded.profile_id;

do $$ begin
  if (select coalesce(sum(ownership_percent),0) from public.founders where is_active) <> 100 then
    raise exception 'Active founder ownership must total 100%%';
  end if;
end $$;

insert into public.chart_of_accounts(code,name,account_type,description) values
 ('1010','Company bank - operating','Asset','Primary operating bank balance'),
 ('1020','Cash on hand','Asset','Physical company cash'),
 ('1030','Payment gateway clearing','Asset','Gateway funds pending settlement'),
 ('1200','Prepayments and deposits','Asset','Prepaid costs and refundable deposits'),
 ('1600','Accumulated depreciation','Asset','Contra asset for equipment depreciation'),
 ('2400','Director current account - Pasindu','Liability','Company amount payable to/from Pasindu; credit means owed by company'),
 ('2410','Director current account - Wicky','Liability','Company amount payable to/from Wicky; credit means owed by company'),
 ('2500','Accrued expenses','Liability','Costs incurred but not yet paid'),
 ('2600','Tax payable','Liability','Income and other company taxes payable'),
 ('3010','Ordinary share capital - Pasindu','Equity','Pasindu 50% issued ownership'),
 ('3020','Ordinary share capital - Wicky','Equity','Wicky 50% issued ownership'),
 ('3100','Retained earnings','Equity','Accumulated company results'),
 ('3200','Director drawings/dividends - Pasindu','Equity','Contra equity distributions to Pasindu'),
 ('3210','Director drawings/dividends - Wicky','Equity','Contra equity distributions to Wicky'),
 ('5200','Depreciation expense','Expense','Periodic depreciation of capital assets'),
 ('5300','Bank charges','Expense','Bank fees excluding payment gateway charges')
on conflict(code) do update set name=excluded.name,account_type=excluded.account_type,description=excluded.description;

create table if not exists public.fiscal_periods (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  starts_on date not null,
  ends_on date not null check (ends_on >= starts_on),
  status text not null default 'Open' check(status in ('Open','Soft Closed','Locked')),
  locked_by uuid references auth.users(id),
  locked_at timestamptz,
  created_at timestamptz not null default now()
);
insert into public.fiscal_periods(name,starts_on,ends_on) values
 ('FY 2026/27','2026-04-01','2027-03-31') on conflict(name) do nothing;

create sequence if not exists public.journal_number_seq start 1001;
create table if not exists public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  journal_no text not null unique default ('JE-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('public.journal_number_seq')::text,6,'0')),
  journal_date date not null,
  memo text not null,
  reference_no text not null default '',
  source text not null default 'Manual' check(source in ('Manual','Legacy Migration','Import','System','Reversal')),
  status text not null default 'Draft' check(status in ('Draft','Posted','Reversed')),
  fiscal_period_id uuid references public.fiscal_periods(id),
  legacy_transaction_id text unique references public.transactions(id) on update cascade on delete set null,
  reversal_of uuid unique references public.journal_entries(id),
  created_by uuid references auth.users(id),
  posted_by uuid references auth.users(id),
  posted_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.journal_lines (
  id bigint generated always as identity primary key,
  journal_id uuid not null references public.journal_entries(id) on delete cascade,
  line_no smallint not null,
  account_code text not null references public.chart_of_accounts(code),
  description text not null default '',
  debit numeric(14,2) not null default 0 check(debit >= 0),
  credit numeric(14,2) not null default 0 check(credit >= 0),
  cash_account_id uuid references public.cash_accounts(id),
  counterparty_id uuid references public.counterparties(id),
  founder_id uuid references public.founders(id),
  unique(journal_id,line_no),
  check ((debit > 0 and credit = 0) or (credit > 0 and debit = 0))
);

-- Repair the legacy foreign key when upgrading an existing database.
alter table public.journal_entries drop constraint if exists journal_entries_legacy_transaction_id_fkey;
alter table public.journal_entries add constraint journal_entries_legacy_transaction_id_fkey
foreign key (legacy_transaction_id) references public.transactions(id) on update cascade on delete set null;

create or replace function public.validate_journal(p_journal uuid) returns void language plpgsql security definer set search_path=public as $$
declare d numeric(14,2); c numeric(14,2); n integer; p_status text;
begin
 select coalesce(sum(debit),0),coalesce(sum(credit),0),count(*) into d,c,n from journal_lines where journal_id=p_journal;
 if n<2 or d<=0 or d<>c then raise exception 'Journal must contain at least two lines and balance: debits %, credits %',d,c; end if;
 select fp.status into p_status from journal_entries je left join fiscal_periods fp on fp.id=je.fiscal_period_id where je.id=p_journal;
 if p_status in ('Soft Closed','Locked') then raise exception 'Posting is not allowed in a closed fiscal period'; end if;
end $$;

create or replace function public.post_journal(p_journal uuid) returns void language plpgsql security definer set search_path=public as $$
begin
 if not is_active_staff() then raise exception 'Not authorized'; end if;
 if (select status from journal_entries where id=p_journal) <> 'Draft' then raise exception 'Only draft journals can be posted'; end if;
 perform validate_journal(p_journal);
 update journal_entries set status='Posted',posted_by=auth.uid(),posted_at=now() where id=p_journal;
end $$;

create or replace function public.protect_posted_journal() returns trigger language plpgsql as $$
begin
 if coalesce(current_setting('app.transaction_sync',true),'off') <> 'on' and old.status in ('Posted','Reversed') then raise exception 'Posted journals are immutable; create a reversing journal'; end if;
 return coalesce(new,old);
end $$;
drop trigger if exists protect_posted_journal_header on public.journal_entries;
create trigger protect_posted_journal_header before update or delete on public.journal_entries for each row execute function public.protect_posted_journal();

create or replace function public.protect_posted_lines() returns trigger language plpgsql as $$
begin
 if coalesce(current_setting('app.transaction_sync',true),'off') <> 'on' and exists(select 1 from journal_entries where id=coalesce(new.journal_id,old.journal_id) and status<>'Draft') then raise exception 'Lines of a posted journal are immutable'; end if;
 return coalesce(new,old);
end $$;
drop trigger if exists protect_posted_journal_lines on public.journal_lines;
create trigger protect_posted_journal_lines before insert or update or delete on public.journal_lines for each row execute function public.protect_posted_lines();

-- Convert every existing cash-basis transaction to one balanced journal once.
insert into public.journal_entries(journal_date,memo,reference_no,source,status,legacy_transaction_id,posted_at)
select transaction_date,description,reference_no,'Legacy Migration','Draft',id,created_at from public.transactions
on conflict(legacy_transaction_id) do nothing;
insert into public.journal_lines(journal_id,line_no,account_code,description,debit,credit)
select je.id,1,case when t.kind='Income' then '1000' else coalesce(t.account_code,'5990') end,t.description,t.amount,0
from journal_entries je join transactions t on t.id=je.legacy_transaction_id
where not exists(select 1 from journal_lines l where l.journal_id=je.id);
insert into public.journal_lines(journal_id,line_no,account_code,description,debit,credit)
select je.id,2,case when t.kind='Income' then coalesce(t.account_code,'4990') else '1000' end,t.description,0,t.amount
from journal_entries je join transactions t on t.id=je.legacy_transaction_id
where not exists(select 1 from journal_lines l where l.journal_id=je.id and l.line_no=2);
do $$ declare j record; begin for j in select id from journal_entries where source='Legacy Migration' and status='Draft' loop perform validate_journal(j.id); update journal_entries set status='Posted',posted_at=now() where id=j.id; end loop; end $$;

create or replace view public.trial_balance with (security_invoker=true) as
select a.code,a.name,a.account_type,coalesce(sum(case when j.status='Posted' then l.debit-l.credit else 0 end),0)::numeric(14,2) balance
from chart_of_accounts a left join journal_lines l on l.account_code=a.code left join journal_entries j on j.id=l.journal_id group by a.code,a.name,a.account_type;
create or replace view public.profit_and_loss with (security_invoker=true) as
select date_trunc('month',j.journal_date)::date as reporting_month,a.code,a.name,a.account_type,
 sum(case when a.account_type='Income' then l.credit-l.debit else l.debit-l.credit end)::numeric(14,2) amount
from journal_entries j join journal_lines l on l.journal_id=j.id join chart_of_accounts a on a.code=l.account_code
where j.status='Posted' and a.account_type in ('Income','Expense') group by 1,a.code,a.name,a.account_type;
create or replace view public.founder_balances with (security_invoker=true) as
select f.id,f.code,f.full_name,f.position,f.ownership_percent,
 coalesce(sum(case when j.status='Posted' and l.account_code in ('2400','2410') then l.credit-l.debit when j.status='Posted' and l.account_code in ('3010','3020') then l.credit-l.debit else 0 end),0)::numeric(14,2) company_owes_or_equity,
 coalesce(sum(case when j.status='Posted' and l.account_code in ('3200','3210') then l.debit-l.credit else 0 end),0)::numeric(14,2) drawings
from founders f left join journal_lines l on l.founder_id=f.id left join journal_entries j on j.id=l.journal_id and j.status='Posted' group by f.id;

alter table public.company_settings enable row level security;
alter table public.founders enable row level security;
alter table public.fiscal_periods enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;
drop policy if exists "Staff read company settings" on public.company_settings;
drop policy if exists "Staff read founders" on public.founders;
drop policy if exists "Staff read periods" on public.fiscal_periods;
drop policy if exists "Staff manage draft journals" on public.journal_entries;
drop policy if exists "Staff manage draft lines" on public.journal_lines;
create policy "Staff read company settings" on public.company_settings for select to authenticated using(is_active_staff());
create policy "Staff read founders" on public.founders for select to authenticated using(is_active_staff());
create policy "Staff read periods" on public.fiscal_periods for select to authenticated using(is_active_staff());
create policy "Staff manage draft journals" on public.journal_entries for all to authenticated using(is_active_staff()) with check(is_active_staff());
create policy "Staff manage draft lines" on public.journal_lines for all to authenticated using(is_active_staff()) with check(is_active_staff());
grant select on public.trial_balance,public.profit_and_loss,public.founder_balances to authenticated;
grant execute on function public.post_journal(uuid) to authenticated;


-- ===== TRANSACTION CLASSIFICATIONS =====
-- Add expanded entry classifications and requested founder/company selectors.
-- Safe whether migration 003 was already run or will be run later.
insert into public.chart_of_accounts(code,name,account_type,description) values
 ('5095','Company registration and secretarial','Expense','Company incorporation, annual returns, registry and company-secretarial costs')
on conflict(code) do update set name=excluded.name,account_type=excluded.account_type,description=excluded.description;

insert into public.cash_accounts(name,account_type) values
 ('Wicky founder account','Founder')
on conflict(name) do nothing;

alter table public.transactions add column if not exists entry_type text not null default 'Operating Expense';
update public.transactions set entry_type=case when kind='Income' then 'Operating Income' else 'Operating Expense' end
where entry_type in ('Operating Expense','');


-- ===== FOUNDER ANALYTICS =====
-- Detailed founder analytics and profit appropriation reporting.
-- Run after migrations 003, 004 and 005.

create table if not exists public.profit_allocations (
  id uuid primary key default gen_random_uuid(),
  fiscal_period_id uuid not null unique references public.fiscal_periods(id),
  profit_after_tax numeric(14,2) not null check(profit_after_tax >= 0),
  reinvestment_amount numeric(14,2) not null default 0 check(reinvestment_amount >= 0),
  distributable_amount numeric(14,2) generated always as (profit_after_tax-reinvestment_amount) stored,
  resolution_reference text not null default '',
  notes text not null default '',
  status text not null default 'Draft' check(status in ('Draft','Approved','Posted')),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  check(reinvestment_amount <= profit_after_tax)
);

create or replace view public.company_performance_summary with (security_invoker=true) as
select
  coalesce(sum(case when a.account_type='Income' then l.credit-l.debit else 0 end),0)::numeric(14,2) total_income,
  coalesce(sum(case when a.account_type='Expense' then l.debit-l.credit else 0 end),0)::numeric(14,2) total_expenses,
  coalesce(sum(case when a.account_type='Income' then l.credit-l.debit when a.account_type='Expense' then -(l.debit-l.credit) else 0 end),0)::numeric(14,2) net_profit
from public.journal_entries j
join public.journal_lines l on l.journal_id=j.id
join public.chart_of_accounts a on a.code=l.account_code
where j.status='Posted';

create or replace view public.founder_activity with (security_invoker=true) as
select
  f.id founder_id,f.code founder_code,f.full_name,j.id journal_id,j.journal_no,j.journal_date,j.memo,j.reference_no,
  l.account_code,a.name account_name,l.description,l.debit,l.credit,
  case
    when l.account_code in ('3010','3020') then 'Capital introduced'
    when l.account_code in ('2400','2410') and l.credit>0 then 'Company cost funded / amount owed to founder'
    when l.account_code in ('2400','2410') and l.debit>0 then 'Founder reimbursement / amount settled'
    when l.account_code in ('3200','3210') then 'Drawing or dividend distribution'
    else 'Founder-related adjustment' end activity_type
from public.journal_entries j
join public.journal_lines l on l.journal_id=j.id
join public.chart_of_accounts a on a.code=l.account_code
join public.founders f on f.id=l.founder_id
  or (f.code='PASINDU' and l.account_code in ('2400','3010','3200'))
  or (f.code='WICKY' and l.account_code in ('2410','3020','3210'))
where j.status='Posted';

create or replace view public.founder_financial_summary with (security_invoker=true) as
with activity as (
 select f.id,
  coalesce(sum(case when fa.activity_type='Capital introduced' then fa.credit-fa.debit else 0 end),0) capital,
  coalesce(sum(case when fa.activity_type like 'Company cost funded%' then fa.credit else 0 end),0) personally_funded,
  coalesce(sum(case when fa.activity_type like 'Founder reimbursement%' then fa.debit else 0 end),0) reimbursed,
  coalesce(sum(case when fa.activity_type='Drawing or dividend distribution' then fa.debit-fa.credit else 0 end),0) drawings
 from founders f left join founder_activity fa on fa.founder_id=f.id group by f.id
), allocations as (
 select f.id,
  coalesce(sum(case when pa.status in ('Approved','Posted') then pa.profit_after_tax*f.ownership_percent/100 else 0 end),0) profit_share,
  coalesce(sum(case when pa.status in ('Approved','Posted') then pa.reinvestment_amount*f.ownership_percent/100 else 0 end),0) reinvested_share,
  coalesce(sum(case when pa.status in ('Approved','Posted') then pa.distributable_amount*f.ownership_percent/100 else 0 end),0) distributable_share
 from founders f cross join profit_allocations pa group by f.id
)
select f.id,f.code,f.full_name,f.position,f.ownership_percent,
 a.capital::numeric(14,2) capital_introduced,a.personally_funded::numeric(14,2) personally_funded,
 a.reimbursed::numeric(14,2) reimbursed,(a.personally_funded-a.reimbursed)::numeric(14,2) current_account_due,
 a.drawings::numeric(14,2) drawings,coalesce(x.profit_share,0)::numeric(14,2) allocated_profit,
 coalesce(x.reinvested_share,0)::numeric(14,2) reinvested_profit,
 coalesce(x.distributable_share,0)::numeric(14,2) distributable_profit,
 (coalesce(x.distributable_share,0)-a.drawings)::numeric(14,2) remaining_distribution
from founders f join activity a on a.id=f.id left join allocations x on x.id=f.id;

alter table public.profit_allocations enable row level security;
drop policy if exists "Staff read profit allocations" on public.profit_allocations;
drop policy if exists "Super admins manage profit allocations" on public.profit_allocations;
create policy "Staff read profit allocations" on public.profit_allocations for select to authenticated using(is_active_staff());
create policy "Super admins manage profit allocations" on public.profit_allocations for all to authenticated
using(exists(select 1 from profiles where id=auth.uid() and is_active and role='super_admin'))
with check(exists(select 1 from profiles where id=auth.uid() and is_active and role='super_admin'));
grant select on public.company_performance_summary,public.founder_activity,public.founder_financial_summary to authenticated;


-- ===== ACCOUNTING AUDIT CONTROLS =====
-- Extend audit coverage beyond the legacy transactions table.
-- Run after migration 006.

create or replace function public.audit_accounting_change() returns trigger
language plpgsql security definer set search_path=public as $$
declare record_key text;
begin
  record_key := coalesce(to_jsonb(new)->>'id',to_jsonb(old)->>'id','unknown');
  insert into public.audit_logs(table_name,record_id,action,old_data,new_data,changed_by)
  values (tg_table_name,record_key,tg_op,
    case when tg_op <> 'INSERT' then to_jsonb(old) end,
    case when tg_op <> 'DELETE' then to_jsonb(new) end,
    auth.uid());
  return coalesce(new,old);
end $$;

drop trigger if exists journal_entries_audit on public.journal_entries;
create trigger journal_entries_audit after insert or update or delete on public.journal_entries
for each row execute function public.audit_accounting_change();
drop trigger if exists journal_lines_audit on public.journal_lines;
create trigger journal_lines_audit after insert or update or delete on public.journal_lines
for each row execute function public.audit_accounting_change();
drop trigger if exists profit_allocations_audit on public.profit_allocations;
create trigger profit_allocations_audit after insert or update or delete on public.profit_allocations
for each row execute function public.audit_accounting_change();
drop trigger if exists counterparties_audit on public.counterparties;
create trigger counterparties_audit after insert or update or delete on public.counterparties
for each row execute function public.audit_accounting_change();

-- ===== TRANSACTION-TO-JOURNAL SYNCHRONIZATION =====
-- Keeps every application page, report, trial balance and founder account in sync.
create or replace function public.sync_transaction_journal(p_transaction_id text) returns void
language plpgsql security definer set search_path=public as $$
declare t transactions%rowtype; j_id uuid; offset_account text; linked_founder uuid;
begin
  select * into t from transactions where id=p_transaction_id;
  if not found then
    perform set_config('app.transaction_sync','on',true);
    update journal_entries set status='Reversed' where legacy_transaction_id=p_transaction_id;
    return;
  end if;

  perform set_config('app.transaction_sync','on',true);
  select id into j_id from journal_entries where legacy_transaction_id=t.id;
  if j_id is null then
    insert into journal_entries(journal_date,memo,reference_no,source,status,legacy_transaction_id,created_by)
    values(t.transaction_date,t.description,t.reference_no,'System','Draft',t.id,coalesce(t.created_by,auth.uid())) returning id into j_id;
  else
    update journal_entries set journal_date=t.transaction_date,memo=t.description,reference_no=t.reference_no,status='Draft' where id=j_id;
    delete from journal_lines where journal_id=j_id;
  end if;

  if t.status='Void' then update journal_entries set status='Reversed' where id=j_id; return; end if;

  if t.paid_by in ('Pasindu') then
    offset_account:='2400'; select id into linked_founder from founders where code='PASINDU';
  elsif t.paid_by in ('Wicky','Pradeep') then
    offset_account:='2410'; select id into linked_founder from founders where code='WICKY';
  else offset_account:='1000'; linked_founder:=null;
  end if;

  if t.kind='Income' then
    insert into journal_lines(journal_id,line_no,account_code,description,debit,credit,cash_account_id,founder_id)
    values(j_id,1,offset_account,t.description,t.amount,0,t.cash_account_id,linked_founder),
          (j_id,2,coalesce(t.account_code,'4990'),t.description,0,t.amount,null,null);
  else
    insert into journal_lines(journal_id,line_no,account_code,description,debit,credit,cash_account_id,founder_id)
    values(j_id,1,coalesce(t.account_code,'5990'),t.description,t.amount,0,null,null),
          (j_id,2,offset_account,t.description,0,t.amount,t.cash_account_id,linked_founder);
  end if;
  perform validate_journal(j_id);
  update journal_entries set status=case when t.status='Posted' then 'Posted' else 'Draft' end,
    posted_by=case when t.status='Posted' then coalesce(t.updated_by,t.created_by,auth.uid()) end,
    posted_at=case when t.status='Posted' then now() end where id=j_id;
end $$;

create or replace function public.transactions_sync_trigger() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if tg_op='DELETE' then
    perform set_config('app.transaction_sync','on',true);
    -- Detach first so deletion also works on databases that still have the
    -- original restrictive foreign key instead of ON DELETE SET NULL.
    update journal_entries
      set status='Reversed', legacy_transaction_id=null
      where legacy_transaction_id=old.id;
    return old;
  end if;
  perform sync_transaction_journal(new.id);
  return new;
end $$;
drop trigger if exists transactions_journal_sync on public.transactions;
drop trigger if exists transactions_journal_sync_delete on public.transactions;
create trigger transactions_journal_sync after insert or update on public.transactions
for each row execute function public.transactions_sync_trigger();
create trigger transactions_journal_sync_delete before delete on public.transactions
for each row execute function public.transactions_sync_trigger();

-- Remove records created only by implementation propagation tests.
delete from public.transactions
where id like 'VERIFY-%'
  and description = 'Temporary propagation verification';

-- Remove obsolete rows from the original JSON import only after linked
-- journals can be safely reversed and detached.
delete from public.transactions
where id in ('EXP-002', 'EXP-003');

-- Normalize every remaining legacy primary key without breaking its journal
-- relationship. The repaired foreign key cascades the new ID automatically.
select set_config('app.transaction_sync','on',true);
update public.transactions
set id = public.generate_transaction_id(transaction_date)
where id !~ '^TXN-[0-9]{8}-[A-F0-9]{8}$';

-- Reconcile existing rows with the new synchronization rules.
do $$ declare r record; begin for r in select id from transactions loop perform sync_transaction_journal(r.id); end loop; end $$;
grant execute on function public.sync_transaction_journal(text) to authenticated;


commit;
