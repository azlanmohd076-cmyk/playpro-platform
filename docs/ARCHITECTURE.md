# PlayPro System Architecture

## Overview
PlayPro adalah sistem pengurusan bola sepak grassroots dengan 3 layer utama:

### Layer 1: Frontend (Static Web)
- 8 HTML files (public dashboards, portals)
- Vanilla JavaScript (no frameworks)
- Real-time data via Supabase PostgREST API
- Responsive design

### Layer 2: Backend API (PostgREST)
- Supabase provides auto-generated REST API from database
- 65+ custom database functions (RPC calls)
- Row-Level Security (RLS) for data protection
- Real-time subscriptions

### Layer 3: Database (PostgreSQL)
- 85 tables with comprehensive schema
- 86 functions for business logic
- ~99 triggers for automation
- 6 materialized views for reporting

## Key Systems

### 1. Authentication & Authorization
- Supabase Auth (Email/Google/SSO)
- profiles table linked to auth.users
- Role-based access control (RBAC)
- Row-level security on all tables

### 2. Football Passport System
- Player attributes (18 core attributes)
- DNA rating (technical, physical, mental, tactical)
- Passport score calculation
- Historical tracking and progression

### 3. Match Observer & Pipeline
- Real-time event recording during matches
- 12 event types (goals, fouls, substitutions, etc)
- Player statistics aggregation
- Automatic DNA update trigger on match completion

### 4. Player Development Engine
- Training session tracking and attendance
- Attribute growth calculation
- Morale and fitness snapshots
- Injury risk assessment
- Development projections and wonderkid identification

### 5. Intelligence & Analytics
- Player similarity matching
- Market value calculation
- Scout report generation
- Reputation scoring
- League quality analysis

## Data Flow

```
User Action (HTML)
        ↓
  JavaScript
        ↓
  Supabase API
        ↓
  PostgreSQL
        ↓
  Trigger fires
        ↓
  RPC Function executes
        ↓
  Update Tables
        ↓
  Real-time subscription
        ↓
  UI Updates Live
```

## Security Architecture
- Row-Level Security (RLS) on all 85 tables
- Row-level filtering by user role
- Auth context checked on every database query
- No sensitive data exposed to frontend
- Encrypted connections (HTTPS/SSL)

## Scalability Considerations
- Stateless frontend (no server sessions)
- Database connection pooling
- Materialized views for heavy analytical queries
- Nightly batch processing for reports
- Indexed queries on common filter columns
