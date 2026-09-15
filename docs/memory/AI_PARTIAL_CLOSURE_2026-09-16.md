# PlayPro — Partial Workflow Closure — 2026-09-16

This checkpoint records the implementation block executed against production `playpro2` and GitHub `main`.

## Closed in this block

### Club training
- Added backend RPC `playpro_create_training_session`.
- Added backend RPC `playpro_list_team_training_sessions`.
- Added backend RPC `playpro_update_training_session`.
- RPCs enforce authenticated Club Owner/Admin authority through `playpro_is_club_manager`.
- Venue ownership is checked when a venue is supplied.
- Added production route `/club/training` served by `public/club_training.html`.
- The page reads the real Club dashboard and real `club_teams`, then creates and lists real training sessions through RPCs.

### Club history
- Added automatic projection from an `is_official=true` and ratified `match_results` row into `club_history_records` for both participating clubs.
- Projection uses `source_fixture_id` and an idempotency unique index so repeated ratification/update events do not duplicate the same official-match history record.
- TMR is not used as Club History.

### Membership fee integrity
- `club_membership_settings.platform_fee_percent` is now a database invariant of exactly `5.00`.
- Existing non-5% settings were normalized before the constraint was added.
- `playpro_save_club_fee_settings` always writes 5%.
- `playpro_prepare_membership_payment` calculates the platform fee directly from the 5% invariant rather than trusting a club-configured percentage.

## Git commits
- `81cf190b8971f92d5131bbb3c3a492bb899a78ba` — feat(club): close partial training history and fee workflows
- `6b1a6ce7cd44149054c11af4ec514cce4e3bc73a` — fix(club): make official history projection idempotent
- `e87dd4e1b662f8ec35304bb1f8ce94282c434c35` — feat(club): add end-to-end training scheduler surface
- `9c53664dd3657783d3340a9a5b41a28d48db97fc` — feat(club): route training scheduler

## Production verification
- Supabase migration applied successfully to `playpro2`.
- Database constraint verified: `platform_fee_percent = 5.00`.
- Training/history RPCs verified present in `public`.
- Official history idempotency index verified present.
- Vercel production deployment for main commit `9c53664dd3657783d3340a9a5b41a28d48db97fc` is `READY`.
- `/club/training` returned HTTP 200 from the production deployment.

## Still legitimately PARTIAL / blocked
- Player/Coach KYC cannot be marked complete merely because UI/database exists; the real verification path and production credentials/provider behavior must be proven end-to-end.
- Competition self-service/organiser automation remains a separate implementation block; do not fake completion from Club UI.
- Full Wallet remains not started.
- Developer Master Control remains a separate implementation block.
- Club main tab currently contains legacy placeholder text for Training/History; `/club/training` is the production-complete surface added in this block. Main Club tab integration is a UI patch still required before calling the entire Club Center surface complete.

Rule: screen existence is not completion. Completion requires USER → DB → permission → workflow → output → production verification.
