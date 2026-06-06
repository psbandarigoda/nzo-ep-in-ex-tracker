const CONFIG = {
  expenseCategories: [
    "Database",
    "Hosting",
    "Domain",
    "NFC Reader",
    "NFC Cards",
    "Travel",
    "Meeting",
    "Development",
    "Marketing",
    "Legal",
    "Accounting",
    "Other"
  ],
  incomeCategories: [
    "Ticket Sales",
    "Sponsorship",
    "Vendor Payment",
    "Advertising",
    "Commission",
    "Refund",
    "Investment",
    "Other"
  ],
  categories: [],
  transactionKinds: ["Expense", "Income"],
  types: ["Logical", "Virtual", "Physical"],
  people: ["Pasindu", "Pradeep", "Company Shared"],
  storageDir: "data/transactions",
  manifestFile: "manifest.json",
  legacyDatabaseFile: "expenses.json",
  databaseFile: "data/transactions/manifest.json"
};

CONFIG.categories = [...new Set([...CONFIG.expenseCategories, ...CONFIG.incomeCategories])];
