# PlayPro Canonical Database Blueprint v1

**Status:** Architecture baseline — no production schema changes
**Branch:** `phase-2/canonical-model`

## 1. Purpose

This document defines the canonical domain model for PlayPro before database reconstruction/migrations. Existing tables remain the starting foundation; legacy SQL must not be applied blindly.

## 2. Core principle

One real-world fact is recorded once. Live match events are the source of truth for match-derived statistics. Profiles, club statistics, standings, discipline and development data are derived/updated from validated events and official records.

## 3. Identity model

`User Account` is the base identity. A user may hold multiple capabilities rather than being restricted to one global role.

Capabilities include:
- Player
- Coach
- Referee
- Club Admin
- Competition Organizer
- Match Admin / Match Observer
- League/competition administration where authorized

KYC is a verification gate, not a login requirement.

KYC is required for actions that create or exercise official authority, including joining a club where identity must be verified, creating a club, becoming an official organizer, and other protected actions defined by policy.

## 4. Public vs verified access

### Public / ordinary registered user
May browse permitted public profiles and competition information without KYC.

### Verified capability
A user obtains a verified capability after the required identity and authorization checks. A single user may have several capabilities.

## 5. Player domain

Canonical relationship:

`User -> Player -> Player Profile -> Football Passport -> Player Card`

### Player Profile
Current football identity and public profile data.

### Football Passport
Longitudinal football record: identity, club history, competition history, assessments, performance and development history. The Passport is not merely another name for the profile.

### Player Card
Operational matchday identity representation. It must support QR/Player ID lookup and manual search. It is used by match administrators to identify a player and check eligibility before registration/participation.

## 6. Club domain

A club is an organization/entity. Club administration is a capability assigned to verified users with appropriate ownership/authorization.

Player-club membership must be represented explicitly and must preserve history; current club should not overwrite historical membership.

## 7. Competition / organizer domain

A competition may be created by a club, individual, academy, community, association, company or other eligible organizer.

Competition status must distinguish at minimum:
- `unofficial`
- `official_pending` / verification workflow
- `official`
- `cancelled` / `completed` as lifecycle states

Official status is not equivalent to simply having KYC. KYC establishes identity; official recognition is a separate authorization decision governed by PlayPro rules.

## 8. Competition formats

The engine must support configurable formats rather than separate hard-coded systems:
- League
- Group stage
- Knockout
- Group + knockout / hybrid
- Round robin
- Single/friendly match
- Future extensible formats

Format rules determine fixtures, standings, progression, qualification and/or bracket generation.

## 9. Competition squad / player registration

The club prepares its competition squad. Eligible registered players should become available to the competition/matchday workflow without duplicate manual creation of the same player identity.

Player participation remains subject to eligibility rules, competition registration and disciplinary status.

## 10. Match domain

Canonical flow:

`Competition -> Fixture -> Match -> Live Match Events -> Result/Stats`

A match is operated by authorized Match Admin/Match Observer personnel. A referee remains a distinct officiating capability; a referee may also be granted Match Observer capability.

## 11. Live Match Event model

Events should be immutable/auditable facts wherever practical. Examples:
- Match start
- Match end
- Player in / substitution in
- Player out / substitution out
- Goal
- Assist
- Yellow card
- Red card
- Corner
- Shot / shot on target
- Save
- Man of the Match
- Other approved match events

Each player-related event should be associated with the match, competition, club/team and player where applicable.

## 12. Match clock and playing time

The Match Observer Panel contains the operational match clock.

`Match Start -> Starting XI active -> clock -> substitution events -> Match End`

Playing time is calculated from player-in/starting time to player-out/match-end. It must support extra time where applicable.

Playing time is a first-class player performance metric and a key input to the Player Development system.

The clock UI is not itself the source of truth; validated start/end/substitution events are.

## 13. Statistics propagation

The observer enters an event once. PlayPro applies its validated effects atomically/transactionally where possible.

Example:

`Goal at 37' by Player A -> match score +1 -> player match goals +1 -> club match statistic +1 -> competition aggregates/standings as applicable`

No post-match duplicate manual editing should be required for derived statistics.

## 14. Discipline and eligibility

Cards entered live feed the disciplinary system.

A red card and other suspension-triggering rules can automatically create/update suspension records according to competition rules.

Before player registration/participation, PlayPro must evaluate:
- player identity
- competition registration
- club/team relationship
- suspension/disciplinary eligibility
- other competition-specific restrictions

A suspended player must be blocked by the backend, not merely shown as red in the UI.

## 15. Player development

Match-derived data feeds development analytics, including:
- appearances
- minutes played
- starts
- substitute appearances
- goals/assists
- discipline
- competition history
- performance trends

Assessment and DNA remain separate inputs/derived layers and must have traceable provenance.

## 16. Canonical existing foundation

The active database already contains the core foundation around:
`profiles`, `players`, `clubs`, `coaches`, `leagues`, `league_staff`, `league_clubs`, `fixtures`, `match_results`, `player_match_stats`, `disciplinary_records`, `suspensions`, `standings`, `player_assessments`, `coach_assessments`, `club_assessments`, and `referees`.

These are the starting foundation, not a promise that every current table is production-complete.

## 17. Reconstruction rule

For every requested object, determine:
1. Does it already exist in active Supabase?
2. Is it used by current application code?
3. Is it required by the approved product model?
4. Is it legacy/duplicate?
5. What security/ownership model does it require?

Classify as:
- KEEP
- REBUILD
- REMOVE
- DEFER

No schema object is created merely because an old repository method or SQL file mentions it.

## 18. Deferred intelligence

Scout marketplace, player similarity, market value, advanced AI recommendations and advanced analytics are downstream capabilities. They must consume stable canonical data rather than define the core schema prematurely.

## 19. Definition of done for the canonical model

Before migration implementation begins, we must have:
- complete entity relationship map
- event catalogue
- competition format model
- KYC/verification state model
- capability/permission matrix
- player eligibility rules
- Player Card data contract
- Match Observer data contract
- playing-time calculation rules
- code-to-database dependency inventory
- KEEP/REBUILD/REMOVE/DEFER inventory
- migration sequence and rollback strategy

**No production schema change is authorized by this document alone.**