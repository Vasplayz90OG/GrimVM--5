<div align="center">

```
  ██████╗ ██████╗ ██╗███╗   ███╗██╗   ██╗███╗   ███╗
 ██╔════╝ ██╔══██╗██║████╗ ████║██║   ██║████╗ ████║
 ██║  ███╗██████╔╝██║██╔████╔██║██║   ██║██╔████╔██║
 ██║   ██║██╔══██╗██║██║╚██╔╝██║╚██╗ ██╔╝██║╚██╔╝██║
 ╚██████╔╝██║  ██║██║██║ ╚═╝ ██║ ╚████╔╝ ██║ ╚═╝ ██║
  ╚═════╝ ╚═╝  ╚═╝╚═╝╚═╝     ╚═╝  ╚═══╝  ╚═╝     ╚═╝
```

**GrimVM — Hypervisor Panel**

Project `#5` · Author: **Vasplayz90 · ArizNodes Team** · License: **MIT**
Copyright Reserved 2026 · ArizNodes Team

[![License: MIT](https://img.shields.io/badge/License-MIT-6c47ff.svg)](LICENSE)
[![PHP](https://img.shields.io/badge/PHP-8.2-777bb4)](https://php.net)
[![Docker](https://img.shields.io/badge/Docker-Powered-2496ed)](https://docker.com)
[![Nginx](https://img.shields.io/badge/Nginx-TLS%201.3-009639)](https://nginx.org)
[![MySQL](https://img.shields.io/badge/MySQL-8.0-4479a1)](https://mysql.com)

</div>

---

## What is GrimVM?

GrimVM is a self-hosted hypervisor panel that provisions, manages, and monitors VPS instances via Docker containers. It gives admins full control over nodes, eggs, mounts, and users — and gives members a clean dashboard with console access, rank progression, and reward claiming.

Built for Ubuntu 22.04+ and Debian 11+. One command installs everything.

---

## Quick Install

```bash
bash <(curl -s https://raw.githubusercontent.com/Vasplayz90OG/GrimVM--5/main/install.sh)
```

The installer handles everything:

- System dependencies (Nginx, MySQL 8, PHP 8.2, Redis, Docker, Fail2ban)
- SSL certificate via Let's Encrypt (Certbot)
- Full database schema creation and seeding
- Admin account creation
- Nginx + PHP-FPM configuration
- UFW firewall rules
- Fail2ban hardening
- Default node, eggs, and settings

---

## Requirements

| Requirement | Version |
|---|---|
| OS | Ubuntu 22.04+ or Debian 11+ |
| RAM | 1 GB minimum (2 GB recommended) |
| Disk | 20 GB minimum |
| PHP | 8.2 |
| MySQL | 8.0 |
| Nginx | Latest |
| Docker | Latest |
| Domain | Required (for SSL) |

> Root access required. Run as `sudo` or directly as root.

---

## Stack

| Layer | Technology |
|---|---|
| Backend | PHP 8.2 + Slim Framework 4 |
| Auth | JWT (HS256, 7-day expiry) |
| Database | MySQL 8.0 + PDO |
| Cache / Sessions | Redis |
| Container Engine | Docker via Unix socket |
| Console Access | tmate (SSH + web session per container) |
| Reverse Proxy | Nginx with TLS 1.3 |
| Rate Limiting | Redis-backed, 120 req/min per IP |
| Process Manager | PHP-FPM (dynamic pool) |

---

## Panel Pages

### Dashboard (Public — all members)
Overview of assigned VPS, running count, current rank, and recent server list.

### My Servers (Public — all members)
Full VPS list with power controls (start / stop / restart) and console shortcut. Members can view and control their own VPS only.

### Console (Public — all members)
tmate session viewer. Displays SSH access string and web terminal link for each assigned VPS. No raw shell exposed through the panel — tmate handles it inside the container.

### Ranks (Public — all members)
Displays current rank, progression thresholds, and a reward claim form.

### Admin Panel (Private — admin and owner only)
Full control surface:
- Create and delete VPS (assign to any user)
- User management: ban, unban, mute, IP ban
- Node management: create and list nodes
- Settings editor
- Audit log viewer

### Database (Private — owner only via MySQL)
Direct MySQL access. Not exposed through the panel UI. Protected by MySQL auth and Nginx deny rules on `.env`.

---

## VPS Lifecycle

```
Admin creates VPS
       │
       ▼
Docker container created (image from egg)
       │
       ▼
Container started
       │
       ▼
tmate installed inside container
       │
       ▼
tmate session started → SSH + web URL returned
       │
       ▼
VPS record updated → owner notified
       │
       ▼
Owner VPS count incremented → rank recalculated
```

Each VPS is a Docker container labeled `grimvm.managed=true`. The panel communicates with Docker via the Unix socket at `/var/run/docker.sock`.

---

## Rank System

| Rank | Requirement | Notes |
|---|---|---|
| Newbie | Default | All new accounts start here |
| Pro | 2 VPS assigned | Auto-promoted when count reaches threshold |
| Ultimate | 4 VPS assigned | Unlocks reward claim system |

Rank is recalculated automatically every time a VPS is created or deleted. No manual promotion needed.

### Rewards
Ultimate-rank users can claim reward codes through the dashboard. Codes are one-time-use and validated server-side against the user's current rank.

---

## Protection System

### Daily Delete Limit
Admins are capped at **20 VPS deletions per day**. Exceeding the limit triggers an automatic account suspension with a logged reason. The cap resets at midnight.

### Ban / Unban
Full ban system with reason logging and optional IP ban. Banned users cannot authenticate.

### Mute
Time-based mute (in minutes). Stored as `muted_until` timestamp. Application-layer enforcement.

### Rate Limiting
120 requests per minute per IP, enforced via Redis. Returns `HTTP 429` with `Retry-After` header on breach.

### Fail2ban
Nginx auth failure and bot scanning jails active out of the box. 24-hour ban on 2 hits for bot scanning.

### UFW Firewall
Opens ports 22 (SSH), 80 (HTTP), 443 (HTTPS), and 2222 (tmate relay). All other ports closed by default.

---

## Directory Structure

```
/var/www/grimvm/
├── public/
│   ├── index.php          # Application entry point
│   ├── index.html         # Dashboard SPA
│   ├── admin.html         # Admin panel SPA
│   ├── css/
│   ├── js/
│   └── img/
├── app/
│   ├── Controllers/
│   │   ├── AuthController.php
│   │   ├── VPSController.php
│   │   └── AdminController.php
│   ├── Models/
│   │   ├── User.php
│   │   └── VPS.php
│   ├── Middleware/
│   │   ├── AuthMiddleware.php
│   │   ├── SessionMiddleware.php
│   │   └── RateLimitMiddleware.php
│   └── Services/
│       ├── DatabaseService.php
│       ├── DockerService.php
│       ├── TmateService.php
│       ├── RankService.php
│       └── AuditService.php
├── config/
│   └── container.php
├── routes/
│   ├── web.php
│   ├── api.php
│   └── admin.php
├── database/
│   └── schema.sql
├── storage/
│   ├── logs/
│   ├── sessions/
│   ├── cache/
│   └── backups/
├── vendor/               # Composer dependencies
├── composer.json
└── .env                  # Environment config (chmod 600)
```

---

## API Reference

### Auth

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| POST | `/api/auth/login` | None | Login, returns JWT |
| POST | `/api/auth/register` | None | Create account |

### VPS (Member)

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| GET | `/api/vps` | Member | List own VPS |
| POST | `/api/vps/{uuid}/power/{action}` | Member | start / stop / restart |

### VPS (Admin)

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| POST | `/api/admin/vps` | Admin | Create VPS |
| GET | `/api/admin/vps` | Admin | List all VPS |
| DELETE | `/api/admin/vps/{uuid}` | Admin | Delete VPS |

### Admin

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| GET | `/api/admin/users` | Admin | List all users |
| POST | `/api/admin/users/{id}/ban` | Admin | Ban user |
| POST | `/api/admin/users/{id}/unban` | Admin | Unban user |
| POST | `/api/admin/users/{id}/mute` | Admin | Mute user |
| POST | `/api/admin/nodes` | Admin | Create node |
| GET | `/api/admin/nodes` | Admin | List nodes |
| GET | `/api/admin/settings` | Admin | Get settings |
| PUT | `/api/admin/settings/{key}` | Admin | Update setting |
| GET | `/api/admin/audit` | Admin | View audit log |

---

## Environment Variables

```env
APP_NAME=GrimVM
APP_ENV=production
APP_URL=https://your.domain.com
APP_SECRET=<generated-on-install>

DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=grimvm
DB_USERNAME=grimvm_user
DB_PASSWORD=<your-password>

REDIS_HOST=127.0.0.1
REDIS_PORT=6379

SESSION_DRIVER=redis
CACHE_DRIVER=redis

DOCKER_SOCKET=/var/run/docker.sock
TMATE_SERVER=ssh.tmate.io

MAX_VPS_PER_NODE=50
VPS_DELETE_DAILY_LIMIT=20
```

---

## Post-Install Checklist

- [ ] Access `https://your-domain.com` and sign in with your admin credentials
- [ ] Navigate to Admin Panel → Nodes and verify Node-01 is listed
- [ ] Create a test VPS assigned to your admin account
- [ ] Verify tmate SSH string is returned in the Console tab
- [ ] Check `/var/www/grimvm/storage/logs/app.log` for any errors
- [ ] Confirm SSL certificate is active (`https://` loads without warning)
- [ ] Run `ufw status` — ports 22, 80, 443, 2222 should be open
- [ ] Run `fail2ban-client status` — nginx jails should be active

---

## Updating

```bash
cd /var/www/grimvm
git pull
composer install --no-dev --optimize-autoloader
chown -R www-data:www-data .
systemctl reload nginx php8.2-fpm
```

---

## License

MIT License — Copyright Reserved 2026 · ArizNodes Team

Permission is granted, free of charge, to any person obtaining a copy of this software to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.

---

## Credits

| Role | Name |
|---|---|
| Author & Lead Dev | Vasplayz90 |
| Team | ArizNodes Team |
| Project | GrimVM #5 |
| GitHub | [Vasplayz90OG/GrimVM--5](https://github.com/Vasplayz90OG/GrimVM--5) |

---

<div align="center">
<sub>Built by ArizNodes Team · GrimVM Project #5 · 2026</sub>
</div>
