# PlayPro Deployment Guide

## Prerequisites
- Supabase project with uuid-ossp and pg_cron extensions enabled
- Vercel account connected to GitHub
- GitHub Secrets configured with Supabase credentials

## Deployment Steps

### Step 1: Setup Supabase (Day 1 - Morning)
1. Create Supabase project
2. Enable extensions: uuid-ossp, pg_cron
3. Enable Auth
4. Record URL and anon key

### Step 2: Fix Critical Issues (Day 1 - Midday)
1. Update `src/supabase.js` with real Supabase credentials
2. Add `<script src="../src/playpro_audit_fixes.js"></script>` to all HTML files

### Step 3: Run SQL Migrations (Day 1 - Afternoon)
Run in exact order in Supabase SQL Editor:
1. 01_phase1_core_schema.sql
2. 02_phase2_transfers_events.sql
3. 03_phase3_staff_injuries.sql
4. 04_phase4_critical_fix.sql
5. 05_phase4_1_stabilization.sql
6. 06_phase4_1_1_remediation.sql
7. 07_phase4_1_2_security.sql
8. 08_phase4_1_3_remediation.sql
9. 09_phase4_2_hotfix.sql
10. 10_phase6_5_dna_migration.sql
11. 11_sprint1_identity_patch.sql
12. 12_phase6_6_intelligence.sql
13. 13_phase6_7_pipeline.sql
14. 14_phase6_8_development.sql
15. 15_audit_fixes.sql

### Step 4: Verify Database (Day 1 - Evening)
Run verification queries in Supabase SQL Editor to confirm tables and functions created successfully.

### Step 5: Push to GitHub (Day 2 - Morning)
```bash
git add .
git commit -m "Complete PlayPro project setup"
git push origin main
```

### Step 6: Deploy to Vercel (Day 2 - Midday)
1. Connect Vercel to GitHub repo
2. Set root directory to `public/`
3. Vercel auto-deploys after GitHub push
4. Wait 2-3 minutes for build
5. Test public page loads

### Step 7: Load Test Data (Day 2 - Afternoon)
1. Create test data via portals.html
2. Run intelligence batch:
```sql
SELECT run_intelligence_batch();
SELECT refresh_all_public_views();
```

### Step 8: Configure Cron Jobs (Day 3 - Morning)
In Supabase Extensions → pg_cron, add:
- Development nightly: `0 19 * * *`
- Weekly growth: `0 20 * * 1`
- Intelligence batch: `0 21 * * *`
- Refresh views: `0 22 * * *`

## Go Live!
Your PlayPro platform is ready for users! 🚀
