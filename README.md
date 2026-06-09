# PlayPro - Grassroots Football Intelligence Platform

![PlayPro](https://img.shields.io/badge/Status-Development-yellow)
![License](https://img.shields.io/badge/License-MIT-green)

## About PlayPro

PlayPro adalah platform pengurusan bola sepak grassroots yang komprehensif dengan fitur:

- **Football Passport**: Sistem penilaian pemain yang komprehensif
- **DNA Rating**: Analisis atribut teknikal, fizikal, mental, dan taktikal
- **Player Development Engine**: Mesin pembelajaran dan proyeksi perkembangan
- **Match Observer**: Pencatatan real-time peristiwa perlawanan
- **League Management**: Pengurusan liga, kelab, pemain, dan perlawanan

## Tech Stack

- **Frontend**: Vanilla JavaScript, HTML5, CSS3
- **Backend**: Supabase (PostgreSQL + PostgREST)
- **Hosting**: Vercel (Frontend) + Supabase (Database)
- **Authentication**: Supabase Auth

## Quick Start

### Prerequisites
- Node.js 16+ (optional, untuk development)
- Supabase account (free tier cukup)
- Vercel account (untuk deployment)

### Local Setup

```bash
# 1. Clone repository
git clone https://github.com/azlanmohd076-cmyk/playpro-platform.git
cd playpro-platform

# 2. Copy environment template
cp config/.env.example .env.local

# 3. Fill in Supabase credentials
# Edit .env.local dengan URL dan API key Supabase kamu

# 4. Buka public/playpro_public.html dalam browser
# atau guna live server extension
```

## Project Structure

```
playpro-platform/
├── public/          # HTML files (laman web)
├── js/              # JavaScript files (logik aplikasi)
├── css/             # CSS files (styling)
├── database/        # SQL migrations (pangkalan data)
├── docs/            # Documentation
├── config/          # Configuration files
└── .github/         # GitHub workflows
```

## Deployment

Untuk panduan deployment lengkap, lihat [DEPLOYMENT.md](docs/DEPLOYMENT.md)

**Quick deployment:**
1. Setup Supabase credentials
2. Run SQL migrations dalam urutan
3. Push ke GitHub
4. Vercel auto-deploy

## Documentation

- [Deployment Guide](docs/DEPLOYMENT.md) - Panduan deploy step-by-step
- [Architecture](docs/ARCHITECTURE.md) - System design & architecture
- [Database Schema](docs/DATABASE.md) - Database tables & relationships
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues & fixes

## Contributors

- Azlan Mohd (azlanmohd076-cmyk)

## License

MIT License - lihat [LICENSE](LICENSE) untuk details

## Support

Ada soalan atau issue? [Buat GitHub Issue](https://github.com/azlanmohd076-cmyk/playpro-platform/issues)

---

**Last Updated**: 2026-06-09  
**Version**: 1.0.0-beta
