# Taixuan Static Site

This repository hosts a multi-page static site that connects to a Supabase backend.

## Deploy via GitHub Pages (recommended)

1. Create a new GitHub repository (e.g. `taixuan-site`) with default branch `main`.
2. Push local files:
   ```powershell
   cd c:\Users\DELL\Desktop\Taixuan
   git init
   git add .
   git commit -m "init site"
   git branch -M main
   git remote add origin https://github.com/<your-username>/<repo>.git
   git push -u origin main
   ```
3. GitHub Pages setup:
   - Settings → Pages → Source: **GitHub Actions** (will appear after the first workflow run), or **Deploy from a branch** using `main` and root.
   - The included workflow `.github/workflows/pages.yml` publishes the root directory to Pages on push to `main`.

## Supabase Configuration

Update in Supabase Console → Authentication → URL Configuration:
- Site URL: `https://<username>.github.io/<repo>/`
- Additional Redirect URLs:
  - `https://<username>.github.io/<repo>/index.html`
  - `https://<username>.github.io/<repo>/repair.html`
  - `https://<username>.github.io/<repo>/health.html`

Ensure `supabase.config.js` points to your Supabase project (`url`, `anon`).

## Verification

Open:
- `.../repair.html` → Login → Self-heal → Run self-tests
- `.../health.html` → Health checks and summary
- `.../1.html?auto=1&autoOverlay=1` → Automated acceptance

## Notes

- `.nojekyll` disables Jekyll processing, suitable for raw static hosting.
- This is not an SPA; access pages via direct file paths.
- If you executed `supabase_app_diagnostics_log.sql`, logs will be written to `app_diagnostics_log` table during health checks.