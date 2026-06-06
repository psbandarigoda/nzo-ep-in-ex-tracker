# nZO x Liyanawicky Expense Tracker - CRUD Version

This is a free GitHub Pages web app for transparent project expense tracking.

## Features

- Add expenses
- Update expenses
- Delete expenses
- Search expenses
- Filter by:
  - Single date
  - Date range
  - Expense type
  - Category
  - Person
- Filtered total calculation
- 50/50 balance calculation
- Monthly report
- Stores data in `expenses.json` inside the GitHub repository

## Files

- `index.html`
- `style.css`
- `script.js`
- `config.js`
- `expenses.json`

## GitHub Pages Setup

1. Create a GitHub repository.
2. Upload all files to the repository root.
3. Go to Settings -> Pages.
4. Select branch `main` and root folder.
5. Open your GitHub Pages URL.

## Enable Save/Add/Update/Delete

GitHub Pages is static hosting, so it cannot write to a file by itself.  
This app uses the GitHub REST API to update `expenses.json`.

Create a fine-grained GitHub token:

1. GitHub -> Settings -> Developer settings
2. Personal access tokens -> Fine-grained tokens
3. Select only this repository
4. Repository permissions:
   - Contents: Read and Write
5. Generate token

Open the web app and enter:
- GitHub owner
- Repository name
- Branch
- Token

The token is stored only in browser session storage, not inside the repo.

## Security Note

For a private internal tool this is okay for you and Pradeep.  
For public users, do not expose GitHub write tokens in the browser. Use Supabase, Firebase, or a small backend API instead.
