# PLAYPRO CLUB — IMPLEMENTATION BASELINE

**Status:** CLUB FOUNDATION IMPLEMENTED · Supabase live + standalone frontend pages

## Canonical flow

`USER / PLAYER / COACH / REFEREE / ANYONE → OWNER KYC → CREATE CLUB → CLUB IDENTITY → CLUB PROFILE → CLUB VERIFIED → STAFF / ADMIN → COACH → PLAYER → TEAM / SQUAD`

A club never creates fake people. Owner, admin, coach and player records point to real PlayPro `profiles`; role-specific identities live in `profile_role_profiles` and the role subject tables.

## Club types

The creator selects one club type. Type does **not** restrict squad age categories.

Current catalogue: Professional, Semi-professional, Amateur, Grassroots Academy, Educational Institution, Government Agency, Corporate, Community, Women's Club, Futsal, Development, Other.

The catalogue is extensible. FAM club licensing material covers sporting, infrastructure, personal/administrative, legal, financial and business criteria; FAM's SupaRimau Charter specifically recognises grassroots academies. FIFA also describes club licensing across sporting, infrastructure, administration, legal and financial areas.

## Club profile

Implemented fields cover club name, logo, owner, founding year, ROS registration (optional), description, contact/WhatsApp, location and verification state. Training grounds are separate records and can store latitude/longitude, Google Place ID and Google Maps URL. Google Maps URLs can open a pin/directions without requiring a Google Maps API key.

## Team / Squad

Teams are created empty and can be created for:

`U6 U7 U8 U9 U10 U11 U12 U13 U14 U15 U16 U17 U18 U19 U20 U21 U22 U23 OPEN VETERAN`

A club may create multiple squads per age category (`A`, `B`, `C`, etc.). Veteran is 35+. Open has no age restriction. For U-categories, a KYC-verified player's current age must not be below the selected category. The rule is enforced server-side, not only by the UI.

## Team page / tactical board

Each team has its own page. The tactical XI supports formation selection and player placement. Player selection references real Player Profiles. The saved tactical template is separate from TMR.

### TMR architecture

TMR is a match operation room, not club history. The canonical identity is `(team_id, fixture_id)` so one team can have unlimited historical TMRs without creating an unmanageable permanent stack. Once finalized, a TMR is not reset or overwritten; the next fixture gets a new room. Match events remain linked to the official fixture/event pipeline.

## Training and history

Training sessions are separate records with team, coach, venue, time, type and notes. Club History is a separate record set for achievements, competitions and milestones. TMR data is not mixed into Club History.

## Security

New club tables have RLS enabled and explicit authenticated grants. Club creation requires verified owner KYC. Adding a player to a squad requires a real PlayPro Player Profile and verified KYC, then enforces the age rule. Team coaching appointments require a real verified Coach Profile. Sensitive identity documents are not exposed by club directory functions.

## Frontend

- `public/club.html` — Club Center: create club, edit club profile, training ground/Google Maps pin, squad creation and navigation.
- `public/club_team.html` — Team/Squad page: formation, tactical XI, player pool, player profile links and TMR entry point.

The pages use the compact database-screen language of the PlayPro player/coach references rather than a generic SaaS dashboard.

## Not yet built in Club

- final Club Verification review workflow/UI;
- full staff appointment management UI;
- full TMR event-operation screen (uses existing match/observer architecture next);
- competition registration automation into organiser/observer panels;
- padang booking marketplace;
- final club finance/ewallet modules.

These are deliberately downstream of the Club foundation and should be built by connecting to the existing competition, LTO and identity pipelines rather than duplicating registration data.