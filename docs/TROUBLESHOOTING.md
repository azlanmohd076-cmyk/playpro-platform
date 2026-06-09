# PlayPro Troubleshooting Guide

## Common Issues & Solutions

### 1. Application Won't Load

**Error: "Cannot connect to Supabase"**
- Check `src/supabase.js` has correct URL and API key
- Verify Supabase project is active
- Check browser console (F12) for errors
- Verify internet connection

**Solution:**
```javascript
// src/supabase.js should have real values:
window.PLAYPRO_SUPABASE_URL = 'https://xxxxx.supabase.co';
window.PLAYPRO_SUPABASE_ANON_KEY = 'eyJxxx...';
```

### 2. SQL Migration Fails

**Error: "uuid-ossp extension not found"**
- Login to Supabase Dashboard
- Go to Extensions
- Search for "uuid-ossp"
- Click "Install"
- Wait 2-3 minutes
- Retry migration

**Error: "Column does not exist"**
- Check migrations ran in EXACT order (01, 02, 03... 15)
- Never skip a migration
- If skipped, manually run skipped steps
- Check for SQL syntax errors

### 3. Materialized Views Empty

**Issue: Player leaderboard shows no data**
- This is NORMAL on first deploy
- Run in Supabase SQL Editor:
```sql
SELECT run_intelligence_batch();
SELECT refresh_all_public_views();
```
- Wait 1-2 minutes
- Views should populate

### 4. Login Not Working

**Error: "Auth not configured"**
- Go to Supabase Dashboard
- Click Authentication → Providers
- Enable Email provider (minimum)
- Save changes
- Check RLS policies on `profiles` table

### 5. Match Observer Can't Record Events

**Error: "match_events insert failed"**
- Check `fixtures.season_id` column exists
- Verify user is authenticated
- Verify user is coach for that club
- Check RLS policy allows insert

### 6. Player Stats Show Error (HTTP 400)

**Issue: Stats tab crashes**
- Check `src/playpro_audit_fixes.js` is loaded
- Should load AFTER `src/dashboard_integration.js`
- Check browser console for errors
- Verify script tag in HTML: `<script src="../src/playpro_audit_fixes.js"></script>`

### 7. Can't Claim Passport

**Issue: Claim not saved**
- Check `src/playpro_audit_fixes.js` is loaded
- Verify user is authenticated (check Auth.session())
- Check `player_ownership_claims` table exists
- Verify RLS allows insert

### 8. Development Data Still Empty After 24 Hours

**Issue: Fitness/Morale/Development data missing**
- Check Supabase pg_cron extension is enabled
- Go to Extensions → pg_cron → Install if needed
- Configure cron jobs (see DEPLOYMENT.md)
- Wait for scheduled time (default 03:00 MYT)
- Or run manually: `SELECT run_development_nightly();`

### 9. Vercel Deploy Fails

**Error: Build fails with "404 not found"**
- Check Vercel Root Directory is set to `public/`
- Check all HTML files are in `public/` folder
- Check JS files are in `src/` folder with correct paths
- Rebuild manually in Vercel dashboard

### 10. RLS Blocking Data Access

**Issue: Data visible in Supabase editor but not in app**
- This means RLS policy is blocking the user
- Check user role matches policy requirements
- Verify user is authenticated
- Check user has correct club/league affiliation

## Debug Checklist

- [ ] Browser console (F12) shows no errors
- [ ] Network tab shows API calls returning 200 status
- [ ] Check `Auth.session()` in browser console returns user
- [ ] Verify Supabase connection works
- [ ] Check all HTML files have correct script paths
- [ ] Verify database tables exist (check Supabase Table Editor)
- [ ] Test RLS with table editor (can you see data?)

## Getting Help

1. Check this troubleshooting guide first
2. Check browser console for error messages (F12)
3. Check Supabase Logs: Dashboard → Logs
4. Check Vercel Build Logs: Dashboard → Deployments
5. Create GitHub Issue with:
   - Error message
   - Steps to reproduce
   - Browser/device info
   - Screenshots if applicable

## Common Gotchas

⚠️ **Don't forget:** `playpro_audit_fixes.js` MUST load AFTER `dashboard_integration.js` or 7 critical fixes won't work!

⚠️ **RLS is active:** If something works in Table Editor but not in app, it's probably RLS.

⚠️ **Extensions needed:** uuid-ossp and pg_cron MUST be enabled in Supabase before migrations.

⚠️ **Migration order matters:** Run SQL files in exact order 01-15. Skipping breaks the database!
