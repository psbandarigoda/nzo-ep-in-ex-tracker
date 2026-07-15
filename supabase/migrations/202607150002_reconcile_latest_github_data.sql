-- Reconcile database state with the final GitHub-backed ledger after migration
-- 001 was run. The removed IDs were explicitly deleted in the legacy app.
insert into public.transactions
  (id, kind, transaction_date, category, payment_method, paid_by, amount, description, proof_url)
values
  ('EXP-001', 'Expense', '2026-06-17', 'Domain', 'Debit Card', 'Pasindu', 6500, 'Buy a Domain', ''),
  ('EXP-1782313948281', 'Expense', '2026-06-20', 'NFC Reader', 'Cash', 'Pasindu', 1530, 'Testing Reader - 01', ''),
  ('EXP-1782314060558', 'Expense', '2026-06-20', 'NFC Cards', 'Cash', 'Pasindu', 250, 'NFC Testing - 5 Cards', '')
on conflict (id) do update set
  kind = excluded.kind,
  transaction_date = excluded.transaction_date,
  category = excluded.category,
  payment_method = excluded.payment_method,
  paid_by = excluded.paid_by,
  amount = excluded.amount,
  description = excluded.description,
  proof_url = excluded.proof_url,
  updated_at = now();

delete from public.transactions where id in ('EXP-002', 'EXP-003');
