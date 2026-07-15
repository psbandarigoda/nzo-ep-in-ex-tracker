# Supabase database setup

1. Open the Supabase project SQL Editor.
2. Run `migrations/202607150001_create_transactions.sql` once.
3. Confirm that Table Editor -> `transactions` contains `EXP-001`, `EXP-002`, and `EXP-003`.

Migration `202607150002_reconcile_latest_github_data.sql` captures transactions
that changed in the legacy app after the first migration was prepared. Run it
after migration 001 when setting up manually.

The import uses `on conflict do nothing`, so rerunning it is safe. Keep the legacy JSON files in source control as the pre-migration backup until the production data has been verified.
