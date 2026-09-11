# PLAYPRO SCHEMA REVIEW — MATCH OPERATIONS

**Status:** REVIEW FINDINGS · production inspected read-only on 2026-09-12

## 1. Result

The live database has enough existing match primitives to anchor the new workflow, but it does not yet contain the full canonical report/assignment/incident/appeal/venue-slot/rule configuration model.

Therefore the correct implementation path is **extension and controlled migration**, not a parallel application model.

## 2. Confirmed live foundations

`playpro2` contains:

- `fixtures`
- `match_events`
- `match_participants`
- `match_playing_time`
- `match_results`
- `player_match_stats`
- `match_admin_assignments`
- `disciplinary_records`
- `suspensions`
- `standings`
- `referees`

`match_results` has the existing officiality fields and the `trg_official_result_standings` trigger.

`match_events` already has recorder identity/time, sequence, and void/audit fields.

## 3. Critical implementation findings

### F01 — Observer finalization is incompatible with the new canonical gate

Live `finalize_match(p_fixture_id)` checks the caller's observer scope and currently permits only the `main` observer to finalize an ENDED fixture.

Canonical architecture requires:

`START OPERATOR END → MATCH REPORT → REFEREE REVIEW → APPROVE → OFFICIAL`

Therefore `finalize_match()` must be redesigned during implementation so END is not equivalent to officialization.

### F02 — Suspension automation still uses old defaults

Live `auto_suspend_on_red_card()` reads `leagues.red_card_ban_matches` and falls back to **1** match. Canonical PlayPro policy is configurable, with the Owner-discussed defaults of 2 for direct red and 1 for second-yellow dismissal.

This must be migrated to the competition-rule configuration/ledger model. Do not merely change the default number without preserving rule provenance.

### F03 — Existing suspension table is too small for the canonical ledger

Live `suspensions` has 12 columns. The canonical design requires additional provenance, qualifying-fixture and appeal fields. Extend the existing table rather than create a second suspension source.

### F04 — Referee assignment source is not present as a live table

A live `referee_assignments` table was not found in the current public schema. `fixtures.referee_id` exists and `referees` exists.

The implementation must introduce the Owner-approved single assignment source and preserve the existing referee reference as compatibility/derivation until the migration is verified.

### F05 — Venue/pitch scheduling model is incomplete in live public schema

A live `venues` or `venue_availability` table was not found in the current public schema query. `fixtures.venue` is text.

The implementation needs a normalized venue/pitch/slot model to support concurrent pitches and prevent booking collisions.

### F06 — Match report and appeal layers are not present as live public tables

`match_reports` and `disciplinary_appeals` were not found in the current public table list. They therefore require new schema objects during the approved migration stage.

### F07 — Competition rule configuration is not present as a live public table

No `competition_rules` / `competition_rule_config` table was found in the current public table list. The 17 Phase-A rule areas therefore need a competition-scoped configuration model.

## 4. Authorization review

Current policies allow public reads on several match tables and league-admin writes on core result/stat tables. This is not yet sufficient to express the canonical authority boundaries.

The implementation must enforce, at minimum:

- only assigned match staff can record observer events;
- only the designated start operator can START/END;
- observers cannot approve one another;
- only the assigned referee can APPROVE/RETURN the match report;
- only authorized PlayPro administrative action can correct an official locked record;
- suspended/banned players cannot be selected/used when the eligibility rule blocks them.

Do not weaken existing public read behaviour unless required by the approved product/privacy policy.

## 5. Trigger review

Existing trigger chain includes:

- automatic suspension after disciplinary-record insert;
- yellow accumulation suspension;
- official-result standings update;
- updated-at maintenance.

The migration must replace/adjust the relevant disciplinary trigger path without creating duplicate suspension records or duplicate standings updates.

## 6. Required implementation tests

The test suite must cover the exact authority boundaries and state transitions, including RETURN FOR CORRECTION, referee approval, official lock, qualifying-fixture suspension service, ban eligibility, incident outcomes and four-pitch collision prevention.

## 7. Review conclusion

**READY FOR MIGRATION DESIGN:** yes.

**READY TO APPLY PRODUCTION DDL:** no — migration artifacts and tests must be created/reviewed first.

This is a gate, not a request for another Owner decision. The previously locked business decisions remain unchanged.
