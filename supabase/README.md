# Supabase setup

`nzo_complete_schema.sql` is the only authoritative database setup file.

Before running it, create and confirm these Supabase Auth users:

- `bgpsandaruwan@gmail.com`
- `wickycinema@gmail.com`

Then paste the complete SQL file into the Supabase SQL Editor and run it once.
The file creates the base ledger, imports the three current records, and installs
the accounting, founder, reporting, security, and audit schema in one transaction.
