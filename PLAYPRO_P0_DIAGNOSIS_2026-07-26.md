# PlayPro — P0 Diagnosis & Repair Report

**Date:** 2026-07-26
**Author:** Agent 5 (CTO Copilot)
**Sprint:** P0 — Login/Register Stabilization & Profile Integrity Repair
**Method:** Static analysis of `azlanmohd076-cmyk/playpro-platform` @ `e2b766b` + live network probing.
**Rule followed:** *Jangan teka.* Every claim below is backed by a command output.

---

## 0. Executive summary — for the boss, in one paragraph

`Failed to fetch` is **not a code bug**. Your Supabase backend hostname
`muirhenvjruvfxenoaxm.supabase.co` **does not exist in global DNS**. The project is
paused or deleted. No frontend fix can repair this — the app is calling a server
that is not there.

**But** — and this matters — I found **three additional bugs that would have kept
register broken even after you restore the database.** They were hidden behind the
network failure. All three are now fixed, tested, and committed to your working copy.

> **Correction to the brief — now proven on a real database.** Section 5 says the
> profile upsert fails because it omits `email`. That is the *first* error, but it is
> only the first of **three stacked failures**. I rebuilt the PlayPro schema on
> PostgreSQL 17 and measured the exact order:
>
> | Test | Result |
> |---|---|
> | A — old code (no `email`) | `23502` null value in column "email" |
> | B — brief's fix (add `email`) | `42501` **you cannot modify your own role** |
> | C — B + role `player` | `22P02` **invalid input value for enum** |
>
> Applying only the brief's suggested fix moves the failure from error A to error B.
> **Register still breaks.** All three must be fixed together. Details in §2.

> **Correction to my own earlier report.** In my first pass I stated the upsert
> "would fail first with a role-escalation rejection". Live testing shows the
> `NOT NULL` email violation fires *before* the trigger. My ordering was wrong;
> the three bugs and the fix are unchanged. Evidence in §6.

---

## 1. ROOT CAUSE (P0-A): the Supabase project is gone

### Evidence

```
$ getent hosts muirhenvjruvfxenoaxm.supabase.co
   -> (no output, exit 2)

$ curl https://muirhenvjruvfxenoaxm.supabase.co/auth/v1/health
   curl: (6) Could not resolve host
```

Not a sandbox artefact. Verified against two independent public resolvers:

| Query | Cloudflare `1.1.1.1` | Google `8.8.8.8` |
|---|---|---|
| `muirhenvjruvfxenoaxm.supabase.co` | **Status 3 (NXDOMAIN)** | **Status 3 (NXDOMAIN)** |
| `supabase.co` (control) | Status 0 → `76.76.21.21` | Status 0 |
| `random-control-xyz-987.supabase.co` | Status 3 | — |

**Interpretation.** `NXDOMAIN` from the authoritative nameserver means the
subdomain is *not registered at all*. Live Supabase projects always publish a DNS
record. The control queries prove the resolver works and that `supabase.co` has no
wildcard, so `NXDOMAIN` is a genuine signal rather than noise.

This exactly matches the documented Supabase failure mode: a paused/stuck project
stops resolving, and the browser surfaces `ERR_NAME_NOT_RESOLVED` →
`TypeError: Failed to fetch`. ([reference](https://www.answeroverflow.com/m/1439675256871850104))

### What is NOT the problem — ruled out by test

| Hypothesis (from brief §5) | Verdict | Evidence |
|---|---|---|
| CORS misconfiguration | **Ruled out** | CORS requires a TCP connection. DNS fails before that. |
| Deployment / cache issue | **Ruled out** | Live `index.html` md5 == repo HEAD md5 (`dc8dc654…`). Vercel is current. |
| Frontend broken | **Ruled out** | All 15 loader modules return HTTP 200 live. |
| Anon key expired | **Ruled out** | JWT decodes: `role=anon`, `exp` = 2036-06-10. Valid. |
| Browser/network local issue | **Ruled out** | Failure reproduces from a datacenter and from two public DNS resolvers. |

### Fix — only you can do this (needs dashboard access)

1. Open the Supabase dashboard → find project ref `muirhenvjruvfxenoaxm`.
2. **If paused** → **Restore**. Wait for status `Active`, then re-test.
3. **If deleted** → create a new project, then:
   - run every file in `/database` in order,
   - run `database/model6_p0_auth_identity_repair.sql` (new, §3),
   - update `PLAYPRO_SUPABASE_URL` + anon key in **10 HTML files** (list in §5).
4. Verify with `/p0_auth_doctor.html` (new tool, §4) before touching anything else.

---

## 2. THE HIDDEN BUGS — why register would still fail after restore

This is the part the network outage was masking.

### Bug B1 — Invalid enum value (fatal, silent) 🔴

`database/01_phase1_core_schema.sql:25`

```sql
CREATE TYPE user_role AS ENUM (
  'developer','league_founder','league_admin',
  'club_admin','coach','technical_assessor'
);
```

`public/index.html:2753` — the signup role picker:

```js
pickRole('player',…)  pickRole('coach',…)  pickRole('club_admin',…)
pickRole('league_admin',…)  pickRole('referee',…)
```

| UI sends | In enum? |
|---|---|
| `player` | ❌ **NO** |
| `referee` | ❌ **NO** |
| `coach`, `club_admin`, `league_admin` | ✅ yes |

`'player'` is also the JS fallback default (`||'player'`, line 2954).

**Impact:** every player and referee signup — the highest-volume path in the entire
product — dies with `invalid input value for enum user_role` (SQLSTATE `22P02`).
Note `players` is a *separate table*; `player` was simply never added to the role enum.

### Bug B2 — Every signup silently became `club_admin` 🔴

`playpro_phase4_1_2_security_patch.sql:381` replaced the auth trigger:

```sql
CREATE OR REPLACE FUNCTION handle_new_user() …
  INSERT INTO profiles (id, full_name, email, role)
  VALUES (NEW.id, …, NEW.email,
    'club_admin'   -- role hardcoded; signup metadata IGNORED
  ) ON CONFLICT (id) DO NOTHING;
```

A legitimate security fix (LOW-01, blocking `role=developer` injection) — but it
used a sledgehammer. **Every** coach, player and league-admin signup was written as
`club_admin`.

**This directly explains two symptoms in the brief:** "role router gagal" and
"data coach belum cukup lengkap". The coach data was never missing — those users
were never stored as coaches.

### Bug B3 — The client's profile write was guaranteed to be rejected 🔴

Chain of events on every signup:

1. `handle_new_user()` trigger **already inserted** the `profiles` row.
2. Client then calls `.upsert({…, role}, {onConflict:'id'})` → row exists → **UPDATE**.
3. `trg_prevent_role_escalation` (`BEFORE UPDATE ON profiles`) fires:

```sql
IF NEW.id = auth.uid()
   AND NEW.role IS DISTINCT FROM OLD.role      -- 'player' vs 'club_admin' → TRUE
   AND get_my_role() <> 'developer'            -- TRUE
THEN RAISE EXCEPTION … ERRCODE = '42501';
```

Since B2 forced `OLD.role='club_admin'` and the client sends the real role, the
values **always** differ → **every signup profile write raised `42501`**.

### Bug B4 — Why nobody ever saw B1/B2/B3 🔴

```js
try{
  await SB.from('profiles').upsert({...});
}catch(e){console.warn('profiles insert on register:',e.message);}
```

Two independent failures:

1. **supabase-js resolves with `{data, error}` — it does not throw.** The `catch`
   block is unreachable dead code. The `error` field was never destructured, never
   checked. *Verified in `tests/auth-session.test.js` §10.*
2. Even if it had fired, `console.warn` is invisible to users.

So the DB rejected every profile write, and the app cheerfully proceeded to
onboarding as if nothing happened. **This is the mechanism behind "data pemain
hilang / bercampur".** The data was never saved.

### Combined failure chain

```
signUp() ──► auth.users row created ✅
   │
   ├─ trigger handle_new_user()
   │     └─ role forced to 'club_admin'          [B2]
   │
   ├─ client .upsert({role:'player'})
   │     ├─ 'player' not in enum                 [B1] → 22P02
   │     ├─ becomes UPDATE, role differs         [B3] → 42501
   │     └─ email omitted (NOT NULL)             [brief §5] → 23502
   │
   └─ catch(e){console.warn} never fires         [B4] → silent
         │
         └─► showOnboarding() runs on a BROKEN profile
               └─► orphaned auth user, wrong role, lost data
```

---

## 3. WHAT I FIXED

### 3.1 `database/model6_p0_auth_identity_repair.sql` — **NEW** (you must run this)

Idempotent. **Part A must run separately from Part B** (`ALTER TYPE … ADD VALUE`
cannot be used in the same transaction that references the new value — the same
constraint already documented in `playpro_phase6_5_dna_migration.sql:56`).

| Section | Fix |
|---|---|
| **Part A** | Adds `'player'` + `'referee'` to `user_role` → kills **B1** |
| **B.1** | `playpro_safe_signup_role()` — allow-list mapping untrusted metadata → safe role |
| **B.2** | Rebuilds `handle_new_user()` — real role restored → kills **B2** |
| **B.3** | `ensure_profile_after_signup()` RPC — the only client write path → kills **B3** |
| **B.4** | `get_my_profile()` — authoritative role source for the router |
| **B.5** | Backfill: orphaned auth users, NULL emails, optional role reclaim |
| **Part C** | 6 copy-paste verification queries |

**Security is preserved, not traded away.** The original LOW-01 vulnerability stays
closed: `developer`, `league_founder` and `technical_assessor` are **not**
self-assignable — anything outside the allow-list collapses to `player`.
`technical_assessor` is deliberately excluded because per your business model PCSAP
status must be *earned* via the mock exam, never claimed at signup.
`trg_prevent_role_escalation` is left **fully intact**.

### 3.2 `src/modules/auth/auth-session.service.js` — **NEW** (brief §13-D)

Mirrored to `public/src/`, registered in `model6-loader.js`.
Provides `signUp` · `signIn` · `signOut` · `ensureProfile` · `getCurrentRole` ·
`getSession` · `preflight` · `classifyError`.

Key behaviours:

- **Never writes `profiles.role`** — the DB owns it.
- **Preflight probe** hits `/auth/v1/health` first, so a dead backend is reported as
  *"cannot reach server"* instead of *"wrong password"*.
- **`classifyError()`** maps `22P02`/`42501`/`23502`/`23505`/`PGRST202`/network
  failures to a Malay user message **plus** an actionable developer hint.
- **Ordering contract enforced:** `readyForOnboarding` is set **only** after the
  profile row is confirmed (brief §13-E). On profile failure it returns
  `{ok:false, partial:true}` and onboarding is blocked.

### 3.3 `public/index.html` — minimal surgical patch (brief rule #3)

Only the auth paths were touched. **All 4 client-side `profiles` role writes removed**
(1 in `doRegister`, 3 in onboarding — all had the identical B1/B3/B4 bug):

- `doRegister()` → delegates to the auth service, with a safe inline fallback.
- `doLogin()` → network errors no longer misreported as bad credentials; added
  profile self-heal so legacy broken accounts repair themselves on next login.
- 3 × onboarding `profiles.upsert(...role...)` → `ensure_profile_after_signup` RPC.

### 3.4 `js/shared_dashboard_components.js` — syntax error fixed

```js
const pad = { t:14, r:6, b=18, l:6 };   // ← `b=18` is a SyntaxError
```

The **entire file failed to parse**, so every component in it was dead. Fixed to
`b:18`. All 38 JS files now pass `node --check` (brief rule #5).

---

## 4. `public/p0_auth_doctor.html` — **NEW** self-serve diagnostic

Open `/p0_auth_doctor.html`, paste URL + anon key, click once. Read-only.

Checks: URL shape → anon-key JWT decode (role / project-ref match / expiry, warns
loudly on a `service_role` key) → **DNS + reachability** → REST + `profiles`
visibility → whether the P0 RPCs are deployed. Ends with a plain-language verdict
and numbered next steps.

Use this to confirm the backend is alive **before** debugging anything else.

---

## 5. Other findings (not P0 — logged, not fixed)

| # | Finding | Severity | Notes |
|---|---|---|---|
| 1 | Supabase URL + anon key hardcoded in **10 HTML files** | Medium | Anon keys are public by design (RLS-gated) — **not** a leak. But a project migration means 10 manual edits. Centralise later. |
| 2 | **No `service_role` key committed** | ✅ Good | Scanned every file & decoded every JWT: all `role=anon`. |
| 3 | `/js/*.js` returns **404 live** | High (latent) | `vercel.json` sets `outputDirectory: public`, so root `js/` is never deployed. The 4 command-center pages load 5 such scripts each → all 404 in production. |
| 4 | `src/` ↔ `public/src/` drift | Medium | `league-os.service.js`, `passport.service.js` exist only in `src/` (not served); `coach-info-injector.js` only in `public/src/` (not in source). |
| 5 | Duplicate functions in `index.html` | Low | `safeSet`, `aksiLikeHub`, `hantarKomenHub` ×2 — later definition silently wins. |
| 6 | 45 `localStorage` calls; 9 silent `catch` swallows | Medium | P1 source-of-truth cleanup (brief §14). |
| 7 | `js/supabase.js` placeholder fallback | Low | Falls back to `https://YOUR_PROJECT.supabase.co` — would produce a confusing DNS error. |

---

## 6. Verification performed

```
[1] node --check, all 38 JS files ............... PASS
[2] index.html inline JS (167 KB, 2 blocks) ..... PASS
[3] auth service unit tests ..................... 52/52 PASS
[7] PostgreSQL 17 live patch execution .......... PASS (see 6.1)
[8] model6_p0_verify.sql ........................ 9 LULUS / 0 GAGAL
[4] src <-> public/src mirror sync ............... PASS
[5] loader: all 15 dependencies resolve ......... PASS
[6] p0_auth_doctor.html parse + inline JS ....... PASS
```

`tests/auth-session.test.js` (`node tests/auth-session.test.js`, no install) mocks
supabase-js faithfully — **resolving** with `{data,error}` rather than throwing — and
replays the real production failures: enum rejection, `42501` escalation, missing
email, network loss, privilege-escalation attempts, and the dead-`catch` regression.

### 6.1 Live database execution (added 2026-07-26, second pass)

The SQL patch is no longer theory. I installed **PostgreSQL 17.10**, rebuilt a
Supabase-equivalent environment (`auth.users`, `auth.uid()`, RLS roles, signup
trigger), loaded the **real** `01_phase1_core_schema.sql` from this repo (21 tables),
and executed the patch end-to-end.

**Bugs reproduced before the patch:**

| Bug | Observed SQLSTATE |
|---|---|
| B1 enum | `22P02 invalid input value for enum user_role: "player"` / `"referee"` |
| B2 role flattening | coach signup → stored as `club_admin` |
| B3 escalation guard | `42501 you cannot modify your own role` |
| brief §5 email | `23502 null value in column "email"` |

**After the patch — 7 signups across every role:**

| Requested | Stored | Result |
|---|---|---|
| `player` | `player` | correct |
| `coach` | `coach` | correct |
| `club_admin` | `club_admin` | correct |
| `league_admin` | `league_admin` | correct |
| `referee` | `referee` | correct |
| `jurulatih` (BM alias) | `coach` | correct |
| `developer` (attack) | `player` | **escalation blocked** |

**Final state: 9/9 profiles hold the correct role.**

Also verified live:
- `ensure_profile_after_signup` updates name/phone **without touching role** → no `42501`.
- Self-heal works: an orphaned auth user with no profile gets one on next login, with the right role.
- Backfill B.5.3 recovered a `coach` that had been flattened to `club_admin`.
- Escalation guard **still blocks** a user promoting themselves to `developer` (`42501`).
- Patch is **idempotent** — ran twice, no errors, data intact.

### 6.2 A real bug found in my own patch instructions

Running Part A and Part B **in a single transaction** against a database that already
contains orphaned users fails hard:

```
ERROR: unsafe use of new value "player" of enum type user_role
→ whole patch ROLLS BACK, backfill repairs 0 profiles
```

Run Part A first, then Part B → backfill succeeds. The Supabase SQL editor wraps each
*Run* in one transaction, so this is a live trap, not a theoretical one. The patch
header now carries a hard bilingual warning with this evidence.

**Honest limits — what I still could NOT test** (brief rule #1):
- No live end-to-end signup against *your* project: the backend still does not resolve.
- Testing used a **local rebuild** of the schema. Your production database may have
  drifted from these migration files — run `model6_p0_verify.sql` after patching.
- `storage.*` policies in the phase-1 schema were skipped locally (Supabase-only
  objects). They are unrelated to auth.
- Role reclaim (B.5.3) stays **commented out** — inspect the `SELECT` before the `UPDATE`.

---

## 7. Your next steps, in order

1. **Check the Supabase dashboard.** Paused → restore. Deleted → recreate. *Nothing
   else can proceed until DNS resolves.* ← **you, now**
2. Open `/p0_auth_doctor.html` → confirm host reachable.
3. Run `database/model6_p0_auth_identity_repair.sql` — **Part A first**, then Part B.
4. Run the Part C verification queries — all 6 must pass.
5. Re-run the doctor → "P0 repair RPCs present".
6. Test all 6 flows from brief §13-F: player / coach / club-manager signup, existing
   login, logout→login, refresh session.
7. Only then move to P1 (source-of-truth cleanup).

**Do not deploy the frontend changes before step 3.** The patched code calls
`ensure_profile_after_signup`; without the RPC it falls back gracefully and reports
`RPC_MISSING`, but signup will not complete.

---

## 8. Revised project status

Frontend delivery is healthier than the brief assumed (Vercel current, all modules
200). The damage is concentrated in the **identity layer**.

| Area | Brief estimate | Assessed | Note |
|---|---|---|---|
| Database foundation | 50–60% | **45%** | Enum/trigger contradiction was fatal |
| Auth/onboarding | 10–20% | **15% → ~70%** after patch + restore |
| Frontend stability | 10–20% | **25%** | Deploy pipeline fine; monolith fragile |
| Commercial readiness | 10–15% | **10%** | Unchanged |

**The single most important insight:** the "missing player data" and "incomplete
coach data" were never a UI or data-loss problem. Writes were being **rejected by the
database and silently discarded by the client**. Fix the identity layer and a whole
class of downstream symptoms disappears at once.

---

*No secrets are reproduced in this report. Verify every claim — commands are inline.*
