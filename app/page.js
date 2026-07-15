"use client";

import { useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";

const kinds = ["Expense", "Income"];
const expenseCategories = ["Database", "Hosting", "Domain", "NFC Reader", "NFC Cards", "Travel", "Meeting", "Development", "Marketing", "Legal", "Accounting", "Other"];
const incomeCategories = ["B2B Deals", "Ticket Income", "Ticket Sales", "Sponsorship", "Vendor Payment", "Advertising", "Commission", "Refund", "Investment", "Other"];
const categories = [...new Set([...expenseCategories, ...incomeCategories])];
const methods = ["Credit Card", "Debit Card", "Bank Transfer", "Cash", "Payment Gateway", "Company Account", "Virtual", "Physical"];
const people = ["Pasindu", "Pradeep", "Company Shared"];
const money = new Intl.NumberFormat("en-LK", { style: "currency", currency: "LKR", maximumFractionDigits: 0 });
const emptyForm = { id: "", kind: "Expense", date: "", category: "", type: "", paidBy: "", amount: "", description: "", proof: "" };
const emptyFilters = { search: "", kind: "", date: "", from: "", to: "", category: "", type: "", person: "" };

const fromRow = (row) => ({ id: row.id, kind: row.kind, date: row.transaction_date, category: row.category, type: row.payment_method, paidBy: row.paid_by, amount: Number(row.amount), description: row.description, proof: row.proof_url || "" });
const toRow = (item) => ({ id: item.id, kind: item.kind, transaction_date: item.date, category: item.category, payment_method: item.type, paid_by: item.paidBy, amount: Number(item.amount), description: item.description, proof_url: item.proof || "", updated_at: new Date().toISOString() });

function Select({ value, onChange, options, label, required = false }) {
  return <select value={value} onChange={onChange} required={required}><option value="">{label}</option>{options.map((item) => <option key={item}>{item}</option>)}</select>;
}

function balanceText(total, pasindu) {
  const difference = pasindu - total / 2;
  if (Math.abs(difference) < 1) return "Balanced";
  return difference > 0 ? `Pradeep owes ${money.format(difference)}` : `Pasindu owes ${money.format(Math.abs(difference))}`;
}

function totals(records) {
  return records.reduce((result, item) => {
    const amount = Number(item.amount || 0);
    if (item.kind === "Income") { result.income += amount; result.incomeCount += 1; }
    else { result.expense += amount; result.expenseCount += 1; if (item.paidBy === "Pasindu") result.pasindu += amount; if (item.paidBy === "Pradeep") result.pradeep += amount; }
    return result;
  }, { income: 0, expense: 0, pasindu: 0, pradeep: 0, incomeCount: 0, expenseCount: 0 });
}

export default function Home() {
  const [loggedIn, setLoggedIn] = useState(false);
  const [loginError, setLoginError] = useState("");
  const [tab, setTab] = useState("summary");
  const [records, setRecords] = useState([]);
  const [loading, setLoading] = useState(true);
  const [status, setStatus] = useState("");
  const [form, setForm] = useState(emptyForm);
  const [filters, setFilters] = useState(emptyFilters);
  const [month, setMonth] = useState(() => new Date().toISOString().slice(0, 7));

  useEffect(() => { setLoggedIn(sessionStorage.getItem("appLoggedIn") === "true"); loadRecords(); }, []);

  async function loadRecords() {
    if (!supabase) { setStatus("Supabase environment variables are missing."); setLoading(false); return; }
    setLoading(true);
    const { data, error } = await supabase.from("transactions").select("*").order("transaction_date", { ascending: false });
    if (error) setStatus(`Database connection failed: ${error.message}. Run the included Supabase migration first.`);
    else { setRecords(data.map(fromRow)); setStatus(`Connected to Supabase · ${data.length} records loaded`); }
    setLoading(false);
  }

  const filtered = useMemo(() => records.filter((item) => {
    const haystack = Object.values(item).join(" ").toLowerCase();
    return (!filters.search || haystack.includes(filters.search.toLowerCase())) && (!filters.kind || item.kind === filters.kind) && (!filters.date || item.date === filters.date) && (!filters.from || item.date >= filters.from) && (!filters.to || item.date <= filters.to) && (!filters.category || item.category === filters.category) && (!filters.type || item.type === filters.type) && (!filters.person || item.paidBy === filters.person);
  }), [records, filters]);
  const summary = useMemo(() => totals(filtered), [filtered]);
  const monthlyRecords = useMemo(() => records.filter((item) => item.date.startsWith(month)), [records, month]);
  const monthly = useMemo(() => totals(monthlyRecords), [monthlyRecords]);
  const categoryTotals = useMemo(() => monthlyRecords.reduce((all, item) => { const key = `${item.kind} - ${item.category}`; all[key] = (all[key] || 0) + item.amount; return all; }, {}), [monthlyRecords]);

  function login(event) {
    event.preventDefault();
    const values = new FormData(event.currentTarget);
    const username = String(values.get("username")).trim().toLowerCase();
    if (["pasindu", "wicky"].includes(username) && values.get("password") === "EP@123") { sessionStorage.setItem("appLoggedIn", "true"); setLoggedIn(true); setLoginError(""); }
    else setLoginError("Invalid username or password.");
  }

  async function saveRecord(event) {
    event.preventDefault();
    const record = { ...form, id: form.id || `${form.kind === "Income" ? "INC" : "EXP"}-${Date.now()}` };
    setStatus("Saving transaction…");
    const { error } = await supabase.from("transactions").upsert(toRow(record));
    if (error) { setStatus(`Save failed: ${error.message}`); return; }
    setForm(emptyForm); setTab("view"); await loadRecords();
  }

  async function removeRecord(item) {
    if (!confirm(`Delete this ${item.kind.toLowerCase()}?\n\n${item.description}\n${money.format(item.amount)}`)) return;
    const { error } = await supabase.from("transactions").delete().eq("id", item.id);
    if (error) setStatus(`Delete failed: ${error.message}`); else await loadRecords();
  }

  function editRecord(item) { setForm({ ...item, amount: String(item.amount) }); setTab("add"); window.scrollTo({ top: 0, behavior: "smooth" }); }
  function field(name, value) { setForm((current) => ({ ...current, [name]: value })); }
  function filter(name, value) { setFilters((current) => ({ ...current, [name]: value })); }

  if (!loggedIn) return <section className="login-page"><form className="login-panel" onSubmit={login}><p className="tag">Entertain Passport</p><h1>Ledger Login</h1><label>Username<input name="username" autoComplete="username" placeholder="Username" /></label><label>Password<input name="password" autoComplete="current-password" type="password" placeholder="Password" /></label><button>Login</button><p className="status">{loginError}</p></form></section>;

  const tabs = [["summary", "Summary Dashboard"], ["add", "Add Transaction"], ["view", "View Records"], ["report", "Report"], ["settings", "Settings"]];
  return <main className="container">
    <nav className="tabs">{tabs.map(([id, label]) => <button key={id} className={`tab ${tab === id ? "active" : ""}`} onClick={() => setTab(id)}>{label}</button>)}<button className="tab logout-tab" onClick={() => { sessionStorage.removeItem("appLoggedIn"); setLoggedIn(false); }}>Logout</button></nav>

    {tab === "summary" && <section className="hero"><p className="tag">Transparent Collaboration Ledger</p><h1>Platform Balance Sheet</h1><p>Collaboration between <strong>Pasindu Bandarigoda</strong>, Owner/Director of <strong>nZO Innovations Pvt Ltd</strong> and <strong>Pradeep Nawarathna</strong>, Director/Owner of <strong>Liyanawicky Pvt Ltd</strong>.</p><p className="split">Share split: <strong>50% : 50%</strong></p><div className="cards dashboard-cards"><Card label="Total Revenue" value={money.format(summary.income)} /><Card label="Total Expenses" value={money.format(summary.expense)} /><Card label="Net Balance" value={money.format(summary.income - summary.expense)} /><Card label="Partner Balance" value={balanceText(summary.expense, summary.pasindu)} /></div><div className="cards dashboard-cards secondary-cards"><Card label="Pasindu Paid" value={money.format(summary.pasindu)} /><Card label="Pradeep Paid" value={money.format(summary.pradeep)} /><Card label="Income Records" value={summary.incomeCount} /><Card label="Expense Records" value={summary.expenseCount} /></div></section>}

    {tab === "add" && <section className="panel"><h2>{form.id ? "Update" : "Add"} Transaction</h2><form className="form" onSubmit={saveRecord}><label>Record Type<Select required value={form.kind} onChange={(e) => field("kind", e.target.value)} options={kinds} label="Select record type" /></label><label>Date<input required type="date" value={form.date} onChange={(e) => field("date", e.target.value)} /></label><label>Category<Select required value={form.category} onChange={(e) => field("category", e.target.value)} options={categories} label="Select category" /></label><label>Payment Method<Select required value={form.type} onChange={(e) => field("type", e.target.value)} options={methods} label="Select payment method" /></label><label>Paid / Received By<Select required value={form.paidBy} onChange={(e) => field("paidBy", e.target.value)} options={people} label="Select person" /></label><label>Amount LKR<input required type="number" min="0" step="0.01" value={form.amount} onChange={(e) => field("amount", e.target.value)} /></label><label>Description<input required value={form.description} onChange={(e) => field("description", e.target.value)} placeholder="Description" /></label><label>Proof Link<input value={form.proof} onChange={(e) => field("proof", e.target.value)} placeholder="Receipt / invoice link" /></label><div className="button-row"><button>{form.id ? "Update" : "Submit"} Transaction</button><button type="button" className="secondary" onClick={() => setForm(emptyForm)}>Clear</button></div></form></section>}

    {tab === "view" && <><section className="panel"><div className="panel-head"><h2>Search & Filter</h2><button className="secondary small" onClick={() => setFilters(emptyFilters)}>Clear Filters</button></div><div className="filters"><input type="search" placeholder="Search description/category/person..." value={filters.search} onChange={(e) => filter("search", e.target.value)} /><Select value={filters.kind} onChange={(e) => filter("kind", e.target.value)} options={kinds} label="All record types" /><input type="date" title="Single date" value={filters.date} onChange={(e) => filter("date", e.target.value)} /><input type="date" title="From date" value={filters.from} onChange={(e) => filter("from", e.target.value)} /><input type="date" title="To date" value={filters.to} onChange={(e) => filter("to", e.target.value)} /><Select value={filters.category} onChange={(e) => filter("category", e.target.value)} options={categories} label="All categories" /><Select value={filters.type} onChange={(e) => filter("type", e.target.value)} options={methods} label="All payment methods" /><Select value={filters.person} onChange={(e) => filter("person", e.target.value)} options={people} label="All people" /></div></section><section className="panel"><div className="panel-head"><h2>Transaction Records</h2><span className="badge">{filtered.length} records</span></div><TransactionTable records={filtered} edit={editRecord} remove={removeRecord} /></section></>}

    {tab === "report" && <section className="panel"><div className="panel-head"><h2>Monthly Report</h2><input type="month" value={month} onChange={(e) => setMonth(e.target.value)} /></div><div className="cards report-cards"><Card label="Monthly Revenue" value={money.format(monthly.income)} /><Card label="Monthly Expenses" value={money.format(monthly.expense)} /><Card label="Monthly Net" value={money.format(monthly.income - monthly.expense)} /><Card label="Pasindu" value={money.format(monthly.pasindu)} /><Card label="Pradeep" value={money.format(monthly.pradeep)} /><Card label="Monthly Balance" value={balanceText(monthly.expense, monthly.pasindu)} /></div><h3>Category Breakdown</h3><div className="table-wrap"><table><thead><tr><th>Category</th><th>Total</th></tr></thead><tbody>{Object.entries(categoryTotals).sort((a, b) => b[1] - a[1]).map(([name, amount]) => <tr key={name}><td>{name}</td><td>{money.format(amount)}</td></tr>)}{!Object.keys(categoryTotals).length && <tr><td colSpan="2">No records for this month</td></tr>}</tbody></table></div></section>}

    {tab === "settings" && <section className="panel"><div className="panel-head"><h2>Supabase Database</h2><button className="secondary small" onClick={loadRecords}>Refresh</button></div><p className="note">Transactions now save directly to Supabase. GitHub tokens are no longer used or stored by this application.</p><p className="status">{loading ? "Connecting to Supabase…" : status}</p><p className="note">Before first use, run <code>supabase/migrations/202607150001_create_transactions.sql</code> in the Supabase SQL Editor. It creates the table and safely imports all 3 existing records.</p></section>}
  </main>;
}

function Card({ label, value }) { return <div className="card"><span>{label}</span><strong>{value}</strong></div>; }

function TransactionTable({ records, edit, remove }) {
  return <div className="table-wrap"><table><thead><tr><th>Date</th><th>Record Type</th><th>Category</th><th>Payment Method</th><th>Description</th><th>Paid / Received By</th><th>Amount</th><th>Proof</th><th>Actions</th></tr></thead><tbody>{records.slice().sort((a, b) => b.date.localeCompare(a.date)).map((item) => <tr key={item.id}><td>{item.date}</td><td><span className={`badge ${item.kind === "Income" ? "success" : ""}`}>{item.kind}</span></td><td>{item.category}</td><td>{item.type}</td><td>{item.description}</td><td>{item.paidBy}</td><td className={item.kind === "Income" ? "amount-income" : "amount-expense"}>{money.format(item.amount)}</td><td>{item.proof ? <a href={item.proof} target="_blank" rel="noreferrer">View</a> : "-"}</td><td className="actions"><button className="small" onClick={() => edit(item)}>Edit</button><button className="small danger" onClick={() => remove(item)}>Delete</button></td></tr>)}</tbody></table></div>;
}
