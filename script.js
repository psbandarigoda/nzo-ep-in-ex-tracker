let expenses = [];
let filteredExpenses = [];
let manifestSha = null;
let transactionFileShas = {};
let loadedTransactionFiles = [];
let settingsUnlocked = sessionStorage.getItem("settingsUnlocked") === "true";
let appLoggedIn = sessionStorage.getItem("appLoggedIn") === "true";

const currency = new Intl.NumberFormat("en-LK", {
  style: "currency",
  currency: "LKR",
  maximumFractionDigits: 0
});

const $ = (id) => document.getElementById(id);

function loadSettings() {
  $("repoOwner").value = localStorage.getItem("repoOwner") || "";
  $("repoName").value = localStorage.getItem("repoName") || "";
  $("branchName").value = localStorage.getItem("branchName") || "main";
  $("githubToken").value = sessionStorage.getItem("githubToken") || "";
}

function saveSettings() {
  localStorage.setItem("repoOwner", $("repoOwner").value.trim());
  localStorage.setItem("repoName", $("repoName").value.trim());
  localStorage.setItem("branchName", $("branchName").value.trim() || "main");
  sessionStorage.setItem("githubToken", $("githubToken").value.trim());
  setStatus("Settings saved in this browser.");
}

function setStatus(message) {
  $("syncStatus").textContent = message;
}

function transactionKind(item) {
  return item.kind || "Expense";
}

function isIncome(item) {
  return transactionKind(item) === "Income";
}

function normalizeRecords(records) {
  return records.map((item) => ({
    kind: "Expense",
    ...item
  }));
}

function transactionFileName(date) {
  return `${date.slice(0, 7)}.json`;
}

function transactionFilePath(fileName) {
  return `${CONFIG.storageDir}/${fileName}`;
}

function manifestPath() {
  return `${CONFIG.storageDir}/${CONFIG.manifestFile}`;
}

function groupRecordsByMonth(records) {
  return records.reduce((groups, item) => {
    const fileName = transactionFileName(item.date);
    groups[fileName] = groups[fileName] || [];
    groups[fileName].push(item);
    return groups;
  }, {});
}

function renderAppAuth() {
  $("loginPage").classList.toggle("hidden", appLoggedIn);
  $("appShell").classList.toggle("hidden", !appLoggedIn);
  $("appLoginStatus").textContent = "";
}

function loginApp(event) {
  event.preventDefault();

  const username = $("appUsername").value.trim().toLowerCase();
  const password = $("appPassword").value;
  const validUser = username === "pasindu" || username === "wicky";

  if (validUser && password === "EP@123") {
    appLoggedIn = true;
    sessionStorage.setItem("appLoggedIn", "true");
    $("appLoginForm").reset();
    renderAppAuth();
    return;
  }

  $("appLoginStatus").textContent = "Invalid username or password.";
}

function logoutApp() {
  appLoggedIn = false;
  sessionStorage.removeItem("appLoggedIn");
  showTab("summaryTab");
  renderAppAuth();
}

function showTab(tabId) {
  document.querySelectorAll(".tab-panel").forEach((panel) => {
    panel.classList.toggle("active", panel.id === tabId);
  });

  document.querySelectorAll(".tab").forEach((tab) => {
    tab.classList.toggle("active", tab.dataset.tab === tabId);
  });
}

function renderSettingsAuth() {
  $("settingsLogin").classList.toggle("hidden", settingsUnlocked);
  $("settingsContent").classList.toggle("hidden", !settingsUnlocked);
  $("settingsAuthStatus").textContent = "";
}

function unlockSettings(event) {
  event.preventDefault();

  const username = $("settingsUser").value.trim();
  const password = $("settingsPass").value;

  if (username === "root" && password === "root") {
    settingsUnlocked = true;
    sessionStorage.setItem("settingsUnlocked", "true");
    $("settingsLoginForm").reset();
    renderSettingsAuth();
    return;
  }

  $("settingsAuthStatus").textContent = "Invalid username or password.";
}

function lockSettings() {
  settingsUnlocked = false;
  sessionStorage.removeItem("settingsUnlocked");
  renderSettingsAuth();
}

function repoConfig() {
  return {
    owner: $("repoOwner").value.trim(),
    repo: $("repoName").value.trim(),
    branch: $("branchName").value.trim() || "main",
    token: $("githubToken").value.trim()
  };
}

function githubUrl(path = manifestPath()) {
  const { owner, repo } = repoConfig();
  return `https://api.github.com/repos/${owner}/${repo}/contents/${path}`;
}

async function fetchRepoJson(path, cfg) {
  const response = await fetch(`${githubUrl(path)}?ref=${cfg.branch}`, {
    headers: {
      Authorization: `Bearer ${cfg.token}`,
      Accept: "application/vnd.github+json"
    }
  });

  if (!response.ok) return null;

  const file = await response.json();
  const content = decodeURIComponent(escape(atob(file.content.replace(/\n/g, ""))));
  return {
    sha: file.sha,
    data: JSON.parse(content)
  };
}

async function loadFromRepo() {
  const cfg = repoConfig();

  if (!cfg.owner || !cfg.repo || !cfg.token) {
    await loadLocalFallback();
    return;
  }

  setStatus("Syncing from GitHub repo...");

  const manifest = await fetchRepoJson(manifestPath(), cfg);

  if (!manifest) {
    setStatus("Could not sync monthly transaction files. Loading local data instead.");
    await loadLocalFallback();
    return;
  }

  manifestSha = manifest.sha;
  loadedTransactionFiles = manifest.data.files || [];
  transactionFileShas = {};

  const monthlyFiles = await Promise.all(
    loadedTransactionFiles.map(async (fileName) => {
      const file = await fetchRepoJson(transactionFilePath(fileName), cfg);
      if (!file) return [];
      transactionFileShas[fileName] = file.sha;
      return normalizeRecords(file.data);
    })
  );

  expenses = monthlyFiles.flat();
  applyFilters();
  setStatus(`Synced ${loadedTransactionFiles.length} monthly transaction file(s) from GitHub.`);
}

async function loadLocalFallback() {
  const manifestResponse = await fetch(CONFIG.databaseFile);

  if (manifestResponse.ok) {
    const manifest = await manifestResponse.json();
    loadedTransactionFiles = manifest.files || [];
    const monthlyFiles = await Promise.all(
      loadedTransactionFiles.map(async (fileName) => {
        const response = await fetch(transactionFilePath(fileName));
        if (!response.ok) return [];
        return normalizeRecords(await response.json());
      })
    );

    expenses = monthlyFiles.flat();
    applyFilters();
    return;
  }

  const legacyResponse = await fetch(CONFIG.legacyDatabaseFile);
  expenses = normalizeRecords(await legacyResponse.json());
  loadedTransactionFiles = [...new Set(expenses.map((item) => transactionFileName(item.date)))].sort();
  applyFilters();
}

async function saveToRepo(message) {
  const cfg = repoConfig();

  if (!cfg.owner || !cfg.repo || !cfg.token) {
    alert("Please add GitHub repo settings and token first. Without this, GitHub Pages cannot save transaction files.");
    return false;
  }

  setStatus("Saving monthly transaction files to GitHub repo...");

  const grouped = groupRecordsByMonth(expenses);
  const activeFiles = Object.keys(grouped).sort();
  const filesToWrite = [...new Set([...loadedTransactionFiles, ...activeFiles])].sort();

  for (const fileName of filesToWrite) {
    const records = grouped[fileName] || [];
    const body = {
      message: `${message} (${fileName})`,
      content: btoa(unescape(encodeURIComponent(JSON.stringify(records, null, 2)))),
      branch: cfg.branch
    };

    if (transactionFileShas[fileName]) body.sha = transactionFileShas[fileName];

    const response = await fetch(githubUrl(transactionFilePath(fileName)), {
      method: "PUT",
      headers: {
        Authorization: `Bearer ${cfg.token}`,
        Accept: "application/vnd.github+json",
        "Content-Type": "application/json"
      },
      body: JSON.stringify(body)
    });

    if (!response.ok) {
      const errorText = await response.text();
      setStatus("Save failed. Check token/repo permission.");
      console.error(errorText);
      alert("Save failed. Check GitHub token, repo name, branch, and permissions.");
      return false;
    }

    const result = await response.json();
    transactionFileShas[fileName] = result.content.sha;
  }

  const manifest = { files: activeFiles };
  const manifestBody = {
    message: `${message} (manifest)`,
    content: btoa(unescape(encodeURIComponent(JSON.stringify(manifest, null, 2)))),
    branch: cfg.branch
  };

  if (manifestSha) manifestBody.sha = manifestSha;

  const manifestResponse = await fetch(githubUrl(manifestPath()), {
    method: "PUT",
    headers: {
      Authorization: `Bearer ${cfg.token}`,
      Accept: "application/vnd.github+json",
      "Content-Type": "application/json"
    },
    body: JSON.stringify(manifestBody)
  });

  if (!manifestResponse.ok) {
    const errorText = await manifestResponse.text();
    setStatus("Manifest save failed. Check token/repo permission.");
    console.error(errorText);
    alert("Transaction data saved, but manifest update failed. Check GitHub permissions.");
    return false;
  }

  const manifestResult = await manifestResponse.json();
  manifestSha = manifestResult.content.sha;
  loadedTransactionFiles = activeFiles;
  setStatus(`Saved ${activeFiles.length} monthly transaction file(s) in GitHub repo.`);
  return true;
}

function fillSelect(selectId, values, defaultLabel) {
  const select = $(selectId);
  select.innerHTML = `<option value="">${defaultLabel}</option>`;
  values.forEach((v) => {
    const option = document.createElement("option");
    option.value = v;
    option.textContent = v;
    select.appendChild(option);
  });
}

function initSelects() {
  fillSelect("kindSelect", CONFIG.transactionKinds, "Select record type");
  $("kindSelect").value = "Expense";
  updateCategoryOptions();
  fillSelect("typeSelect", CONFIG.paymentMethods, "Select payment method");
  fillSelect("personSelect", CONFIG.people, "Select person");
  fillSelect("filterKind", CONFIG.transactionKinds, "All record types");
  fillSelect("filterCategory", CONFIG.categories, "All categories");
  fillSelect("filterType", CONFIG.paymentMethods, "All payment methods");
  fillSelect("filterPerson", CONFIG.people, "All people");
}

function updateCategoryOptions(selectedValue = "") {
  const kind = $("kindSelect").value || "Expense";
  const categories = kind === "Income" ? CONFIG.incomeCategories : CONFIG.expenseCategories;
  fillSelect("categorySelect", categories, "Select category");
  if (selectedValue && categories.includes(selectedValue)) {
    $("categorySelect").value = selectedValue;
  }
}

function applyFilters() {
  const q = $("searchText").value.toLowerCase();
  const singleDate = $("filterDate").value;
  const fromDate = $("fromDate").value;
  const toDate = $("toDate").value;
  const kind = $("filterKind").value;
  const category = $("filterCategory").value;
  const type = $("filterType").value;
  const person = $("filterPerson").value;

  filteredExpenses = expenses.filter((item) => {
    const textMatch = Object.values(item).join(" ").toLowerCase().includes(q);
    const singleMatch = !singleDate || item.date === singleDate;
    const fromMatch = !fromDate || item.date >= fromDate;
    const toMatch = !toDate || item.date <= toDate;
    const kindMatch = !kind || transactionKind(item) === kind;
    const categoryMatch = !category || item.category === category;
    const typeMatch = !type || item.type === type;
    const personMatch = !person || item.paidBy === person;

    return textMatch && singleMatch && fromMatch && toMatch && kindMatch && categoryMatch && typeMatch && personMatch;
  });

  renderTable();
  renderSummary(filteredExpenses);
  renderMonthlyReport();
}

function renderSummary(data) {
  let income = 0;
  let expense = 0;
  let pasindu = 0;
  let pradeep = 0;
  let incomeRecords = 0;
  let expenseRecords = 0;

  data.forEach((item) => {
    const amount = Number(item.amount || 0);
    if (isIncome(item)) {
      income += amount;
      incomeRecords += 1;
    } else {
      expense += amount;
      expenseRecords += 1;
      if (item.paidBy === "Pasindu") pasindu += amount;
      if (item.paidBy === "Pradeep") pradeep += amount;
    }
  });

  $("totalIncome").textContent = currency.format(income);
  $("totalExpenses").textContent = currency.format(expense);
  $("netBalance").textContent = currency.format(income - expense);
  $("pasinduPaid").textContent = currency.format(pasindu);
  $("pradeepPaid").textContent = currency.format(pradeep);
  $("balanceNote").textContent = balanceText(expense, pasindu, pradeep);
  $("incomeCount").textContent = incomeRecords;
  $("expenseCount").textContent = expenseRecords;
}

function balanceText(total, pasindu, pradeep) {
  const expectedEach = total / 2;
  const pasinduDiff = pasindu - expectedEach;

  if (Math.abs(pasinduDiff) < 1) return "Balanced";
  if (pasinduDiff > 0) return `Pradeep owes ${currency.format(pasinduDiff)}`;
  return `Pasindu owes ${currency.format(Math.abs(pasinduDiff))}`;
}

function renderTable() {
  const tbody = $("expenseTable");
  tbody.innerHTML = "";

  filteredExpenses
    .slice()
    .sort((a, b) => b.date.localeCompare(a.date))
    .forEach((item) => {
      const tr = document.createElement("tr");
      const kind = transactionKind(item);
      tr.innerHTML = `
        <td>${item.date}</td>
        <td><span class="badge ${kind === "Income" ? "success" : ""}">${kind}</span></td>
        <td>${item.category}</td>
        <td>${item.type}</td>
        <td>${item.description}</td>
        <td>${item.paidBy}</td>
        <td class="${kind === "Income" ? "amount-income" : "amount-expense"}">${currency.format(item.amount)}</td>
        <td>${item.proof ? `<a href="${item.proof}" target="_blank">View</a>` : "-"}</td>
        <td class="actions">
          <button class="small" onclick="editExpense('${item.id}')">Edit</button>
          <button class="small danger" onclick="deleteExpense('${item.id}')">Delete</button>
        </td>
      `;
      tbody.appendChild(tr);
    });

  $("recordCount").textContent = `${filteredExpenses.length} records`;
}

async function submitExpense(event) {
  event.preventDefault();

  const form = new FormData(event.target);
  const kind = form.get("kind") || "Expense";
  const prefix = kind === "Income" ? "INC" : "EXP";
  const id = form.get("id") || `${prefix}-${Date.now()}`;

  const record = {
    id,
    kind,
    date: form.get("date"),
    category: form.get("category"),
    type: form.get("type"),
    paidBy: form.get("paidBy"),
    amount: Number(form.get("amount")),
    description: form.get("description"),
    proof: form.get("proof") || ""
  };

  const index = expenses.findIndex((x) => x.id === id);
  if (index >= 0) {
    expenses[index] = record;
  } else {
    expenses.push(record);
  }

  const saved = await saveToRepo(index >= 0 ? `Update transaction ${id}` : `Add transaction ${id}`);
  if (saved) {
    resetForm();
    applyFilters();
  }
}

function editExpense(id) {
  const item = expenses.find((x) => x.id === id);
  if (!item) return;

  const form = $("expenseForm");
  form.elements.id.value = item.id;
  form.elements.kind.value = transactionKind(item);
  updateCategoryOptions(item.category);
  form.elements.date.value = item.date;
  form.elements.category.value = item.category;
  form.elements.type.value = item.type;
  form.elements.paidBy.value = item.paidBy;
  form.elements.amount.value = item.amount;
  form.elements.description.value = item.description;
  form.elements.proof.value = item.proof || "";

  $("formTitle").textContent = "Update Transaction";
  $("submitExpenseBtn").textContent = "Update Transaction";
  showTab("addTab");
  window.scrollTo({ top: 0, behavior: "smooth" });
}

async function deleteExpense(id) {
  const item = expenses.find((x) => x.id === id);
  if (!item) return;

  const ok = confirm(`Delete this ${transactionKind(item).toLowerCase()}?\n\n${item.description}\n${currency.format(item.amount)}`);
  if (!ok) return;

  expenses = expenses.filter((x) => x.id !== id);
  const saved = await saveToRepo(`Delete transaction ${id}`);
  if (saved) applyFilters();
}

function resetForm() {
  $("expenseForm").reset();
  $("expenseForm").elements.id.value = "";
  $("kindSelect").value = "Expense";
  updateCategoryOptions();
  $("formTitle").textContent = "Add Transaction";
  $("submitExpenseBtn").textContent = "Submit Transaction";
}

function clearFilters() {
  ["searchText", "filterKind", "filterDate", "fromDate", "toDate", "filterCategory", "filterType", "filterPerson"].forEach((id) => {
    $(id).value = "";
  });
  applyFilters();
}

function renderMonthlyReport() {
  let month = $("reportMonth").value;
  if (!month) {
    const now = new Date();
    month = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
    $("reportMonth").value = month;
  }

  const monthData = expenses.filter((x) => x.date.startsWith(month));

  let income = 0;
  let total = 0;
  let pasindu = 0;
  let pradeep = 0;
  const categoryTotals = {};

  monthData.forEach((item) => {
    const amount = Number(item.amount || 0);
    const key = `${transactionKind(item)} - ${item.category}`;
    categoryTotals[key] = (categoryTotals[key] || 0) + amount;

    if (isIncome(item)) {
      income += amount;
    } else {
      total += amount;
      if (item.paidBy === "Pasindu") pasindu += amount;
      if (item.paidBy === "Pradeep") pradeep += amount;
    }
  });

  $("monthlyIncome").textContent = currency.format(income);
  $("monthlyTotal").textContent = currency.format(total);
  $("monthlyNet").textContent = currency.format(income - total);
  $("monthlyPasindu").textContent = currency.format(pasindu);
  $("monthlyPradeep").textContent = currency.format(pradeep);
  $("monthlyBalance").textContent = balanceText(total, pasindu, pradeep);

  const rows = Object.entries(categoryTotals)
    .sort((a, b) => b[1] - a[1])
    .map(([category, amount]) => `<tr><td>${category}</td><td>${currency.format(amount)}</td></tr>`)
    .join("");

  $("categoryReport").innerHTML = `
    <h3>Category Breakdown</h3>
    <div class="table-wrap">
      <table>
        <thead><tr><th>Category</th><th>Total</th></tr></thead>
        <tbody>${rows || `<tr><td colspan="2">No records for this month</td></tr>`}</tbody>
      </table>
    </div>
  `;
}

function bindEvents() {
  $("appLoginForm").addEventListener("submit", loginApp);
  $("logoutBtn").addEventListener("click", logoutApp);

  document.querySelectorAll(".tab[data-tab]").forEach((tab) => {
    tab.addEventListener("click", () => showTab(tab.dataset.tab));
  });

  $("kindSelect").addEventListener("change", () => updateCategoryOptions());
  $("settingsLoginForm").addEventListener("submit", unlockSettings);
  $("lockSettings").addEventListener("click", lockSettings);
  $("saveSettings").addEventListener("click", saveSettings);
  $("syncBtn").addEventListener("click", loadFromRepo);
  $("expenseForm").addEventListener("submit", submitExpense);
  $("resetForm").addEventListener("click", resetForm);
  $("clearFilters").addEventListener("click", clearFilters);
  $("reportMonth").addEventListener("change", renderMonthlyReport);

  ["searchText", "filterKind", "filterDate", "fromDate", "toDate", "filterCategory", "filterType", "filterPerson"].forEach((id) => {
    $(id).addEventListener("input", applyFilters);
    $(id).addEventListener("change", applyFilters);
  });
}

initSelects();
loadSettings();
bindEvents();
renderAppAuth();
renderSettingsAuth();
loadFromRepo();
