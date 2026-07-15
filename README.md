# Entertain Passport Expense Tracker

Next.js expense and income ledger backed by Supabase and ready for Vercel.

## Local setup

```bash
npm install
npm run dev
```

Copy `.env.example` to `.env.local` and add the Supabase project values. The supplied project values are already present locally in `.env.local`, which is ignored by Git.

## Migrate existing data

1. Open the Supabase dashboard for the project.
2. Open **SQL Editor** and run [`supabase/migrations/202607150001_create_transactions.sql`](supabase/migrations/202607150001_create_transactions.sql).
3. In **Table Editor**, verify that `transactions` has the three records `EXP-001`, `EXP-002`, and `EXP-003`.
4. Start the app and verify the dashboard total expense is LKR 34,000 before adding new data.

The import is idempotent and never overwrites existing rows. The original `expenses.json` and `data/transactions/2026-06.json` remain in the repository as migration backups.

## Deploy to Vercel

1. Push this project to GitHub and import that repository in Vercel.
2. Set these Vercel environment variables for Production, Preview, and Development:
   - `NEXT_PUBLIC_SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
3. Deploy. Vercel detects Next.js and uses `npm run build` automatically.

## Security note

The migration preserves the original app's shared-login model by granting anonymous database CRUD access. The on-screen password is therefore only a UI gate, not strong database authorization. Before sharing the deployment publicly, migrate the two users to Supabase Auth and replace the anonymous RLS policies with authenticated-user policies.
