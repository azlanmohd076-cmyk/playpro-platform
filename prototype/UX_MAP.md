# PlayPro Interactive Prototype 2.0 — UX Map

Status: Phase 1 working draft  
Target review: 18 November 2026  
Prototype boundary: isolated frontend, simulated data only; no production Supabase writes.

## Product principle
People come to PlayPro to play football, develop players, coach, manage a club, organise competitions, officiate matches or follow the grassroots ecosystem. The interface must help them do that; it must not turn the product into a sequence of administrative forms.

## Experience model
- One account and one identity.
- A person can hold multiple roles; switching role changes the workspace/context, not the account.
- Progressive onboarding: create a useful basic profile first; request additional information only when a user starts an action that needs it.
- Identity KYC is shared across applicable individual roles; professional accreditation and organisation recognition remain separate concepts.
- Public discovery and ordinary profile setup should not be blocked by KYC. Gate only controlled/official actions that require verification.
- A consistent application shell, navigation, typography, spacing, cards, buttons, form controls, status labels and feedback across all modules.
- Mobile-first, responsive on desktop; every visible control must have a meaningful prototype action or be clearly marked unavailable.

## Primary global navigation
1. **Home** — personalised activity feed, recommended next actions, upcoming fixtures and announcements.
2. **Discover** — find players, clubs, teams, coaches, referees, competitions and matches.
3. **Competitions** — browse competitions, register, view standings, fixtures and results.
4. **Inbox** — conversations, invitations, notifications and requests.
5. **My PlayPro** — personal identity, role workspaces, profile, Player Card/Passport, settings and verification.

Persistent global actions: search, create (+), notifications, account/role switcher.

## Role workspaces and modules
### User / shared identity
- Account overview, profile, privacy, role switcher, identity KYC status, security and settings.
- Add a role without creating another account or repeating identity KYC.

### Player
- Player profile and privacy controls.
- Football DNA / assessment history.
- Player Card (front/back, zoom/rotate) and Football Passport.
- Club/team membership, competition eligibility, match history and development timeline.
- Profile creation remains lightweight; official-action gates appear contextually.

### Parent / guardian
- Linked dependent player profiles and consent/visibility controls where supported by existing product rules.
- Parent role is a relationship/permission context, not a duplicate player identity.

### Coach
- Coach profile, coaching experience and qualifications/accreditation.
- Teams and player development, training sessions, assessment permissions and history.
- Identity KYC is distinct from coaching licence/accreditation.

### Club owner / manager
- Create and manage club, squads, staff and player invitations.
- Club identity/recognition is distinct from personal identity KYC.
- Owner can establish a basic club/squad before formal recognition, subject to controlled action gates.

### Organizer
- Organizer profile and organisation details.
- Create/manage competitions, registration windows, categories, fixtures, venues, rules, announcements and results.
- Self-service competition setup is a core product journey.

### Referee
- Referee profile, availability, appointments, match assignments and match reports.
- Personal identity KYC is distinct from referee licence/accreditation.

### Merchant / services (future or limited prototype coverage)
- Storefront, service listings, orders and service-provider profile.
- Keep separate from the core football journeys unless a supported existing feature is confirmed.

### Admin / Developer (restricted operational surfaces)
- Role and access administration, KYC review queue, reports and system operations.
- These surfaces are not part of normal user navigation and must be protected by role permissions.

## Core end-to-end journeys
1. **New person:** open app → sign up/sign in → land on Home → explore → create a basic profile or add a role only when useful.
2. **Player:** My PlayPro → Player profile → add football details → view Player Card/Passport → discover club/competition → attempt official registration → complete only the missing required verification.
3. **Coach:** add Coach role → create concise profile → add qualifications/accreditation separately → create/manage team or training → assess players where authorised.
4. **Club:** create Club → set name/badge/location → create squad → invite players/staff → complete organisation recognition only when a controlled club action requires it.
5. **Organizer:** create competition → set format/category/rules/venue/dates → open registration → review entries → publish fixtures → manage matchday → publish results/table.
6. **Referee:** add Referee role → create profile → add licence/accreditation → set availability → accept appointment → manage match → submit report.
7. **Discover and communicate:** search/filter → view profile/entity → follow/contact/invite where permitted → continue conversation in Inbox.
8. **Role switching:** account menu → choose role/workspace → same account/session, context changes consistently.

## Screen inventory for prototype
### Shared shell
- Sign in / sign up
- Home feed
- Global search and results
- Discover hub and category result lists
- Notifications
- Inbox list and conversation
- Create action menu
- Account menu / role switcher
- My PlayPro hub
- Profile and privacy settings
- Shared KYC status / verification explanation
- Empty, loading, error, success and access-denied states

### Player
- Player overview
- Edit profile
- Football DNA / assessment
- Player Card front and back
- Football Passport
- Membership / invitations
- Match and development history

### Coach
- Coach overview
- Coach profile and qualifications
- Teams / squad
- Training sessions
- Player assessment workspace

### Club
- Club overview
- Club profile / settings
- Squad list and squad detail
- Invite / manage members
- Club recognition status

### Organizer / Competition
- Organizer dashboard
- Competition list and detail
- Create/edit competition wizard
- Registration and participant list
- Fixtures / bracket / standings
- Matchday operations and results

### Referee
- Referee dashboard
- Profile / accreditation
- Availability and appointments
- Match assignment and report

### Shared / operational
- Profile view
- KYC submission and status
- Inbox
- Shop/services placeholder only if supported
- Admin review queue (restricted prototype view)
- Settings and privacy

## Interaction rules
- No dead buttons. Every control navigates, opens a modal, changes state, submits a simulated action or is visibly disabled with an explanation.
- Forms are split into short contextual steps; preserve entered data when moving back.
- Use inline validation and clear next-step guidance.
- Show why information is needed at the point it is needed.
- Do not display private identity documents or sensitive KYC data in public profile screens.
- Use realistic but clearly synthetic fixture/profile data; never represent it as production data.
- Consistent responsive patterns for mobile bottom navigation and desktop sidebar/top navigation.

## Phase 1 decisions to confirm
- Final top-level navigation labels and ordering.
- Exact inclusion and scope of Parent/Guardian and Merchant in the first prototype.
- Which Admin/Developer screens are represented and which are intentionally excluded.
- Final visual direction and brand palette (Phase 2).
