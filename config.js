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
    "B2B Deals",
    "Ticket Income",
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
  paymentMethods: [
    "Credit Card",
    "Debit Card",
    "Bank Transfer",
    "Cash",
    "Payment Gateway",
    "Company Account"
  ],
  types: [],
  people: ["Pasindu", "Pradeep", "Company Shared"],
  storageDir: "data/transactions",
  manifestFile: "manifest.json",
  legacyDatabaseFile: "expenses.json",
  databaseFile: "data/transactions/manifest.json"
};

CONFIG.categories = [...new Set([...CONFIG.expenseCategories, ...CONFIG.incomeCategories])];
CONFIG.types = CONFIG.paymentMethods;
