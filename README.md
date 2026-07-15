# nZO Internal Business Administration & Accounting

Internal company books for **nZO Innovations**, operator of Entertain Passport. This is a company general ledger for founders and finance/operations staff. It is not the organizer settlement or ticketing-report system.

## Capabilities

- Authenticated internal staff access with Supabase Auth and RLS
- LKR income and expense ledger with draft, posted and void states
- nZO-specific Chart of Accounts covering platform revenue, operating costs, assets and liabilities
- Cash/bank account, counterparty, reference, tax/WHT and proof tracking
- Monthly management P&L, account breakdown and CSV export
- Immutable audit log for transaction inserts, updates and voids
- Existing transaction IDs and amounts retained and backfilled into the Chart of Accounts

## Safe production upgrade

Use the single [`supabase/nzo_complete_schema.sql`](supabase/nzo_complete_schema.sql)
file in the Supabase SQL Editor. It is the complete source of truth for the
ledger, current seed records, accounting, founders, reporting, RLS, and auditing.

The live database already has migrations `001` and `002`. Perform this order:

1. In Supabase **Authentication → Users**, create these two internal users: `bgpsandaruwan@gmail.com` and `wickycinema@gmail.com`. Both receive `super_admin`; migration 003 disables every other profile.
2. In **SQL Editor**, run [`supabase/nzo_complete_schema.sql`](supabase/nzo_complete_schema.sql).
3. Confirm `profiles`, `chart_of_accounts`, `cash_accounts`, `counterparties`, and `audit_logs` exist.
4. Confirm the existing three rows remain in `transactions` and each has an `account_code`.
5. Deploy the new commit to Vercel and sign in with the Supabase Auth user.

The schema establishes the 50/50 founder register, director current accounts,
double-entry journals, fiscal-period controls, trial balance, reports, and audit
history while retaining the current transactions.

## Environment variables

```env
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

Never expose a database password or service-role key as a `NEXT_PUBLIC_` variable.

## Local development

```bash
npm install
npm run dev
```

## Accounting boundary

The original cash-basis rows remain as migration evidence; migration 004 introduces the controlled double-entry book. Liability accounts cover organizer payables, refunds/chargebacks, WHT, and deferred card orders, but this app does not calculate ticket settlements or generate organizer reports.

## Founder accounting policy

Pasindu and Wicky are Directors and equal 50% shareholders. Company income and expenses are recorded 100% in nZO's books; they are not split into personal halves. Share capital, director-funded expenses, reimbursements, drawings and dividends use separate accounts for each founder. Profit belongs to the company until a lawful distribution or equity allocation is approved and recorded. Final statutory classifications, tax treatments, dividends and year-end adjustments must be reviewed by a Sri Lankan Chartered Accountant.
