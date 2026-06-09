# PlayPro Database Schema Overview

## Core Tables

### Authentication & Profiles
- `profiles` - User accounts linked to auth.users
- `user_device_tokens` - Push notification tokens
- `user_preferences` - User settings and preferences

### Leagues & Clubs
- `leagues` - Football leagues
- `league_quality_tiers` - League classification system
- `clubs` - Football clubs
- `league_clubs` - Club membership in leagues
- `league_staff` - League administrators
- `club_staff` - Club staff members

### Players & Development
- `players` - Player records with DNA and passport scores
- `player_league_registrations` - Player eligibility per league
- `player_attributes` - 18 core attributes
- `player_attribute_history` - Attribute change tracking
- `player_hidden_attributes` - Non-public attributes
- `player_ownership_claims` - Passport ownership claims
- `player_guardians` - Guardian/parent relationships

### Matches & Events
- `fixtures` - Scheduled matches
- `match_results` - Match outcomes
- `match_events` - Individual match events (goals, fouls, etc)
- `match_lineups` - Team lineups per match
- `player_match_stats` - Per-player statistics
- `match_event_details` - Detailed event information

### Development & Training
- `training_programmes` - Training schedules
- `training_sessions` - Individual training sessions
- `player_training_attendance` - Session attendance records
- `player_training_performance` - Session ratings
- `player_fitness_snapshots` - Daily fitness metrics
- `player_morale_snapshots` - Daily morale metrics
- `player_development_projections` - Growth forecasts

### Intelligence & Analytics
- `player_similarities` - Player comparison data
- `player_market_values` - Player valuation data
- `scout_reports` - AI-generated player reports
- `reputation_scores` - Reputation tracking

## Materialized Views

### Reporting Views
- `mv_player_passport_scores` - Player leaderboard
- `mv_league_standings` - League table with rankings
- `mv_top_scorers` - Goal scorers leaderboard
- `mv_club_dna` - Club DNA summary
- `mv_squad_development` - Squad development progress
- `mv_player_search_index` - Search optimization index

## Key Database Functions

### Authentication Functions
- `get_my_role()` - Get current user role
- `get_my_player_id()` - Get current user's player record
- `is_coach_for_club()` - Permission check for coaches

### Calculation Functions
- `calculate_player_dna()` - DNA rating computation
- `compute_player_passport_score()` - Passport rating
- `compute_player_similarities()` - Player similarity matching
- `compute_player_market_value()` - Valuation computation

### Processing Pipelines
- `run_post_match_pipeline()` - Match completion processing
- `run_intelligence_batch()` - Nightly intelligence updates
- `run_development_nightly()` - Nightly development updates
- `refresh_all_public_views()` - Materialized view refresh

## Security & RLS
- All 85 tables have RLS enabled
- Public read for non-sensitive data
- Role-based write access
- Row-level filtering by club/player/league affiliation

## For Complete Schema Details
Refer to SQL migration files in `/database/` directory for complete table definitions and constraints.
