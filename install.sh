#!/usr/bin/env bash
# ============================================================
#  GrimVM Panel — Full Auto Installer v2.0
#  Author:  Vasplayz90 • ArizNodes Team
#  Project: #5
#  License: MIT
#  Copyright: Reserved 2026 Team • ArizNodes
#  GitHub:  https://github.com/Vasplayz90OG/GrimVM--5
#  Mode: Cloudflare Tunnel (no certbot needed)
# ============================================================
set -uo pipefail

# ── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${GREEN}[GrimVM]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()  { echo -e "${RED}[ERR]${RESET}   $*"; }
ok()   { echo -e "${GREEN}[OK]${RESET}    $*"; }

# ── Banner ────────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
cat << 'EOF'
  ██████╗ ██████╗ ██╗███╗   ███╗██╗   ██╗███╗   ███╗
 ██╔════╝ ██╔══██╗██║████╗ ████║██║   ██║████╗ ████║
 ██║  ███╗██████╔╝██║██╔████╔██║██║   ██║██╔████╔██║
 ██║   ██║██╔══██╗██║██║╚██╔╝██║╚██╗ ██╔╝██║╚██╔╝██║
 ╚██████╔╝██║  ██║██║██║ ╚═╝ ██║ ╚████╔╝ ██║ ╚═╝ ██║
  ╚═════╝ ╚═╝  ╚═╝╚═╝╚═╝     ╚═╝  ╚═══╝  ╚═╝     ╚═╝
EOF
echo -e "${RESET}"
echo -e " ${BOLD}GrimVM Panel v2.0 — Full Auto Installer${RESET}"
echo -e " Author: Vasplayz90 • ArizNodes Team"
echo -e " Mode:   Cloudflare Tunnel (HTTP only, no SSL needed)"
echo -e " ─────────────────────────────────────────────────────"
echo ""

# ── Root check ────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  err "Run as root: sudo bash install.sh"
  exit 1
fi

# ── Fix invoke-rc.d / policy-rc.d noise ──────────────────────
log "Suppressing invoke-rc.d policy errors..."
echo '#!/bin/sh
exit 0' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d

# ── Detect init system ────────────────────────────────────────
USE_SYSTEMD=false
if pidof systemd &>/dev/null || [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
  USE_SYSTEMD=true
  log "Init system: systemd"
else
  warn "Init system: SysV/container — using service commands"
fi

svc_start() {
  if $USE_SYSTEMD; then
    systemctl enable "$1" 2>/dev/null || true
    systemctl start  "$1" 2>/dev/null || true
  else
    service "$1" start 2>/dev/null || true
  fi
}

svc_reload() {
  if $USE_SYSTEMD; then
    systemctl reload "$1" 2>/dev/null || systemctl restart "$1" 2>/dev/null || true
  else
    service "$1" reload 2>/dev/null || service "$1" restart 2>/dev/null || true
  fi
}

svc_status() {
  if $USE_SYSTEMD; then
    systemctl is-active "$1" 2>/dev/null || echo "unknown"
  else
    service "$1" status 2>/dev/null | grep -q "running" && echo "active" || echo "inactive"
  fi
}

# ── Hardcoded config (Cloudflare Tunnel mode) ─────────────────
DOMAIN="hvm1.ariznodes.sryze.cc"
ADMIN_EMAIL="admin@gmail.com"
MYSQL_ROOT_PASS="admin"
DB_PASS="admin"
ADMIN_USER="admin"
ADMIN_PASS="admin"
ADMIN_EMAIL_ACCT="admin@gmail.com"
DB_NAME="grimvm"
DB_USER="grimvm_user"
APP_DIR="/var/www/grimvm"
APP_PORT="8080"

log "Domain:   ${DOMAIN}"
log "App dir:  ${APP_DIR}"
log "Mode:     Cloudflare Tunnel → localhost:${APP_PORT}"
echo ""

# ── OS detection ──────────────────────────────────────────────
source /etc/os-release 2>/dev/null || true
log "OS: ${PRETTY_NAME:-Unknown}"

# ── System update ────────────────────────────────────────────
log "Updating system..."
DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>/dev/null || warn "apt update had warnings, continuing"
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq 2>/dev/null || warn "apt upgrade had warnings, continuing"

# ── Base tools ───────────────────────────────────────────────
log "Installing base tools..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  curl wget git unzip tar software-properties-common \
  apt-transport-https lsb-release ca-certificates gnupg 2>/dev/null || true

# ── PHP 8.2 repo ─────────────────────────────────────────────
log "Adding PHP 8.2 repository..."
if [[ "${ID:-}" == "ubuntu" ]]; then
  add-apt-repository -y ppa:ondrej/php 2>/dev/null || warn "PPA add had warnings"
elif [[ "${ID:-}" == "debian" ]]; then
  wget -qO /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg 2>/dev/null || true
  echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" \
    > /etc/apt/sources.list.d/php.list
fi
apt-get update -qq 2>/dev/null || true

# ── Install PHP 8.2 ──────────────────────────────────────────
log "Installing PHP 8.2..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  php8.2 php8.2-fpm php8.2-mysql php8.2-mbstring \
  php8.2-xml php8.2-curl php8.2-zip php8.2-bcmath \
  php8.2-gd php8.2-cli php8.2-redis php8.2-intl 2>/dev/null || {
  warn "php8.2-redis failed, trying pecl..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    php8.2 php8.2-fpm php8.2-mysql php8.2-mbstring \
    php8.2-xml php8.2-curl php8.2-zip php8.2-bcmath \
    php8.2-gd php8.2-cli php8.2-intl 2>/dev/null || true
}

# ── Install Nginx ────────────────────────────────────────────
log "Installing Nginx..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx 2>/dev/null || true
svc_start nginx

# ── Install MySQL ────────────────────────────────────────────
log "Installing MySQL..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mysql-server 2>/dev/null || true
svc_start mysql

# Wait for MySQL socket
log "Waiting for MySQL to be ready..."
for i in {1..30}; do
  if mysqladmin ping --silent 2>/dev/null; then
    ok "MySQL is ready"
    break
  fi
  sleep 1
done

# ── Install Redis ─────────────────────────────────────────────
log "Installing Redis..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq redis-server 2>/dev/null || true

# Start Redis — try multiple methods
svc_start redis-server 2>/dev/null || true
if ! redis-cli ping &>/dev/null; then
  warn "Redis service start failed, launching directly..."
  mkdir -p /var/log/redis /var/run/redis
  redis-server \
    --daemonize yes \
    --logfile /var/log/redis/redis-server.log \
    --pidfile /var/run/redis/redis-server.pid \
    --bind 127.0.0.1 \
    --port 6379 2>/dev/null || true
  sleep 2
fi

if redis-cli ping &>/dev/null; then
  ok "Redis is running"
else
  warn "Redis could not start — sessions will fall back to files"
  # Patch .env to use file sessions later
  REDIS_FALLBACK=true
fi
REDIS_FALLBACK=${REDIS_FALLBACK:-false}

# ── Install Docker ────────────────────────────────────────────
log "Installing Docker..."
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | bash 2>/dev/null || \
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io 2>/dev/null || true
fi
svc_start docker
usermod -aG docker www-data 2>/dev/null || true

# ── Install Composer ──────────────────────────────────────────
log "Installing Composer..."
if ! command -v composer &>/dev/null; then
  curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer 2>/dev/null || true
fi

# ── Verify PHP-FPM sock ───────────────────────────────────────
log "Starting PHP-FPM..."
svc_start php8.2-fpm 2>/dev/null || true
# If sock doesn't exist, start directly
if [[ ! -S /run/php/php8.2-fpm.sock ]]; then
  warn "FPM sock missing, starting directly..."
  php-fpm8.2 -D 2>/dev/null || true
  sleep 2
fi

if [[ -S /run/php/php8.2-fpm.sock ]]; then
  ok "PHP-FPM socket ready"
else
  warn "PHP-FPM socket still missing — check php8.2-fpm install"
fi

# ── MySQL hardening + DB setup ────────────────────────────────
log "Configuring MySQL..."
# Try auth with no password first (fresh install), then with password
mysql -u root --connect-expired-password 2>/dev/null <<SQL || \
mysql -u root -p"${MYSQL_ROOT_PASS}" 2>/dev/null <<SQL || true
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASS}';
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# ── App directory structure ───────────────────────────────────
log "Creating application structure..."
mkdir -p "${APP_DIR}"/{public,app,config,storage,routes,resources,database,scripts,docker}
mkdir -p "${APP_DIR}"/storage/{logs,sessions,cache,backups}
mkdir -p "${APP_DIR}"/public/{css,js,img,fonts}
mkdir -p "${APP_DIR}"/app/{Controllers,Models,Middleware,Services}
mkdir -p "${APP_DIR}"/resources/views

# ── .env ──────────────────────────────────────────────────────
log "Writing .env..."
APP_SECRET=$(openssl rand -hex 32)

if $REDIS_FALLBACK; then
  SESSION_DRV="file"
  CACHE_DRV="file"
else
  SESSION_DRV="redis"
  CACHE_DRV="redis"
fi

cat > "${APP_DIR}/.env" <<ENV
APP_NAME=GrimVM
APP_ENV=production
APP_URL=https://${DOMAIN}
APP_SECRET=${APP_SECRET}

DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=${DB_NAME}
DB_USERNAME=${DB_USER}
DB_PASSWORD=${DB_PASS}

REDIS_HOST=127.0.0.1
REDIS_PORT=6379

SESSION_DRIVER=${SESSION_DRV}
CACHE_DRIVER=${CACHE_DRV}

ADMIN_EMAIL=${ADMIN_EMAIL_ACCT}
ADMIN_USER=${ADMIN_USER}

DOCKER_SOCKET=/var/run/docker.sock
TMATE_SERVER=ssh.tmate.io

MAX_VPS_PER_NODE=50
VPS_DELETE_DAILY_LIMIT=20
ENV

# ── composer.json ─────────────────────────────────────────────
cat > "${APP_DIR}/composer.json" <<'JSON'
{
  "name": "ariz/grimvm",
  "description": "GrimVM Hypervisor Panel",
  "version": "1.0.0",
  "license": "MIT",
  "require": {
    "php": ">=8.2",
    "ext-pdo": "*",
    "ext-json": "*",
    "slim/slim": "^4.12",
    "slim/psr7": "^1.6",
    "php-di/php-di": "^7.0",
    "vlucas/phpdotenv": "^5.5",
    "firebase/php-jwt": "^6.9",
    "respect/validation": "^2.3",
    "monolog/monolog": "^3.4",
    "phpmailer/phpmailer": "^6.8"
  },
  "autoload": {
    "psr-4": {
      "GrimVM\\": "app/"
    }
  }
}
JSON

# ── Database schema ───────────────────────────────────────────
log "Writing database schema..."
cat > "${APP_DIR}/database/schema.sql" <<'SQL'
SET FOREIGN_KEY_CHECKS=0;

CREATE TABLE IF NOT EXISTS `users` (
  `id`           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `username`     VARCHAR(64) UNIQUE NOT NULL,
  `email`        VARCHAR(255) UNIQUE NOT NULL,
  `password`     VARCHAR(255) NOT NULL,
  `role`         ENUM('owner','admin','member') DEFAULT 'member',
  `rank`         ENUM('Newbie','Pro','Ultimate') DEFAULT 'Newbie',
  `vps_count`    INT DEFAULT 0,
  `banned`       TINYINT DEFAULT 0,
  `ban_reason`   TEXT,
  `ban_ip`       VARCHAR(64),
  `muted_until`  DATETIME,
  `api_token`    VARCHAR(128),
  `created_at`   DATETIME DEFAULT CURRENT_TIMESTAMP,
  `updated_at`   DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nodes` (
  `id`         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `name`       VARCHAR(128) NOT NULL,
  `location`   VARCHAR(128) NOT NULL,
  `ip`         VARCHAR(64) NOT NULL,
  `port`       INT DEFAULT 2222,
  `memory_mb`  INT NOT NULL,
  `disk_gb`    INT NOT NULL,
  `cpu_cores`  INT NOT NULL,
  `active`     TINYINT DEFAULT 1,
  `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `vps` (
  `id`            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `uuid`          CHAR(36) UNIQUE NOT NULL,
  `name`          VARCHAR(128) NOT NULL,
  `owner_id`      BIGINT UNSIGNED NOT NULL,
  `node_id`       BIGINT UNSIGNED NOT NULL,
  `container_id`  VARCHAR(128),
  `image`         VARCHAR(255) NOT NULL,
  `memory_mb`     INT NOT NULL,
  `disk_gb`       INT NOT NULL,
  `cpu_cores`     INT NOT NULL,
  `status`        ENUM('running','stopped','suspended','deleted') DEFAULT 'stopped',
  `tmate_session` VARCHAR(255),
  `sftp_port`     INT,
  `console_port`  INT,
  `created_at`    DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`owner_id`) REFERENCES `users`(`id`),
  FOREIGN KEY (`node_id`)  REFERENCES `nodes`(`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `eggs` (
  `id`           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `name`         VARCHAR(128) NOT NULL,
  `docker_image` VARCHAR(255) NOT NULL,
  `startup_cmd`  TEXT,
  `env_vars`     JSON,
  `description`  TEXT,
  `author`       VARCHAR(128),
  `active`       TINYINT DEFAULT 1,
  `created_at`   DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mounts` (
  `id`         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `name`       VARCHAR(128) NOT NULL,
  `source`     VARCHAR(512) NOT NULL,
  `target`     VARCHAR(512) NOT NULL,
  `read_only`  TINYINT DEFAULT 0,
  `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `vps_mounts` (
  `vps_id`   BIGINT UNSIGNED,
  `mount_id` BIGINT UNSIGNED,
  PRIMARY KEY(`vps_id`,`mount_id`),
  FOREIGN KEY(`vps_id`)   REFERENCES `vps`(`id`),
  FOREIGN KEY(`mount_id`) REFERENCES `mounts`(`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `audit_log` (
  `id`         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `user_id`    BIGINT UNSIGNED,
  `action`     VARCHAR(128) NOT NULL,
  `target`     VARCHAR(255),
  `ip`         VARCHAR(64),
  `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(`user_id`) REFERENCES `users`(`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `delete_log` (
  `id`         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `admin_id`   BIGINT UNSIGNED,
  `vps_uuid`   CHAR(36),
  `deleted_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(`admin_id`) REFERENCES `users`(`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `rewards` (
  `id`          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `name`        VARCHAR(128) NOT NULL,
  `description` TEXT,
  `rank_req`    ENUM('Pro','Ultimate') NOT NULL,
  `code`        VARCHAR(64) UNIQUE,
  `claimed_by`  BIGINT UNSIGNED,
  `claimed_at`  DATETIME,
  FOREIGN KEY(`claimed_by`) REFERENCES `users`(`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `settings` (
  `key`   VARCHAR(128) PRIMARY KEY,
  `value` TEXT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO `settings` (`key`,`value`) VALUES
  ('panel_name','GrimVM'),
  ('max_vps_per_node','50'),
  ('vps_delete_daily_limit','20'),
  ('registration_open','1'),
  ('maintenance_mode','0');

SET FOREIGN_KEY_CHECKS=1;
SQL

# Load schema
log "Loading database schema..."
mysql -u root -p"${MYSQL_ROOT_PASS}" "${DB_NAME}" < "${APP_DIR}/database/schema.sql" 2>/dev/null || \
mysql -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" < "${APP_DIR}/database/schema.sql" 2>/dev/null || \
warn "Schema load had warnings — tables may already exist"

# ── Seed data ─────────────────────────────────────────────────
log "Seeding admin account..."
HASHED=$(php -r "echo password_hash('${ADMIN_PASS}', PASSWORD_BCRYPT, ['cost'=>12]);")

mysql -u root -p"${MYSQL_ROOT_PASS}" "${DB_NAME}" 2>/dev/null <<SQL || true
INSERT INTO users (username, email, password, role, rank)
VALUES ('${ADMIN_USER}', '${ADMIN_EMAIL_ACCT}', '${HASHED}', 'owner', 'Ultimate')
ON DUPLICATE KEY UPDATE role='owner', rank='Ultimate';

INSERT IGNORE INTO nodes (name, location, ip, port, memory_mb, disk_gb, cpu_cores)
VALUES ('Node-01', 'US-East', '127.0.0.1', 2222, 8192, 100, 4);

INSERT IGNORE INTO eggs (name, docker_image, startup_cmd, description, author) VALUES
  ('Ubuntu 22.04',   'ubuntu:22.04',         '/bin/bash', 'Ubuntu 22.04 LTS', 'ArizNodes'),
  ('Debian 12',      'debian:12',             '/bin/bash', 'Debian Bookworm',  'ArizNodes'),
  ('Alpine Linux',   'alpine:3.19',           '/bin/sh',   'Alpine Linux',     'ArizNodes'),
  ('Node.js 20',     'node:20-alpine',        'node',      'Node.js 20 LTS',   'ArizNodes'),
  ('Python 3.12',    'python:3.12-slim',      'python3',   'Python 3.12',      'ArizNodes'),
  ('Minecraft Java', 'itzg/minecraft-server', '',          'Minecraft Java',   'ArizNodes');
SQL

# ── PHP-FPM pool config ───────────────────────────────────────
log "Configuring PHP-FPM pool..."
mkdir -p /etc/php/8.2/fpm/pool.d
cat > /etc/php/8.2/fpm/pool.d/grimvm.conf <<INI
[grimvm]
user = www-data
group = www-data
listen = /run/php/php8.2-fpm.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 20
pm.start_servers = 3
pm.min_spare_servers = 2
pm.max_spare_servers = 8
pm.max_requests = 500
php_admin_value[error_log] = ${APP_DIR}/storage/logs/php-fpm.log
php_admin_flag[log_errors] = on
php_value[upload_max_filesize] = 64M
php_value[post_max_size] = 64M
php_value[memory_limit] = 256M
INI

svc_reload php8.2-fpm 2>/dev/null || php-fpm8.2 -D 2>/dev/null || true
sleep 1

# ── Nginx config — HTTP only (Cloudflare Tunnel handles TLS) ──
log "Writing Nginx config (Cloudflare Tunnel mode — HTTP only)..."
cat > /etc/nginx/sites-available/grimvm <<NGINX
server {
    listen ${APP_PORT};
    server_name _;

    root ${APP_DIR}/public;
    index index.php index.html;

    client_max_body_size 64M;

    # Trust Cloudflare IPs for real IP forwarding
    set_real_ip_from 103.21.244.0/22;
    set_real_ip_from 103.22.200.0/22;
    set_real_ip_from 103.31.4.0/22;
    set_real_ip_from 104.16.0.0/13;
    set_real_ip_from 104.24.0.0/14;
    set_real_ip_from 108.162.192.0/18;
    set_real_ip_from 131.0.72.0/22;
    set_real_ip_from 141.101.64.0/18;
    set_real_ip_from 162.158.0.0/15;
    set_real_ip_from 172.64.0.0/13;
    set_real_ip_from 173.245.48.0/20;
    set_real_ip_from 188.114.96.0/20;
    set_real_ip_from 190.93.240.0/20;
    set_real_ip_from 197.234.240.0/22;
    set_real_ip_from 198.41.128.0/17;
    real_ip_header CF-Connecting-IP;

    # Security headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;

    location /api {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_SCHEME https;
        fastcgi_param HTTPS on;
        include fastcgi_params;
        fastcgi_read_timeout 300;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location ~ /\.env  { deny all; return 404; }
    location ~ /\.git  { deny all; return 404; }
    location ~ /vendor { deny all; return 404; }

    access_log ${APP_DIR}/storage/logs/nginx_access.log;
    error_log  ${APP_DIR}/storage/logs/nginx_error.log;
}
NGINX

ln -sf /etc/nginx/sites-available/grimvm /etc/nginx/sites-enabled/grimvm
rm -f /etc/nginx/sites-enabled/default

# Test nginx config
if nginx -t 2>/dev/null; then
  ok "Nginx config valid"
  svc_reload nginx
else
  err "Nginx config test failed — check /etc/nginx/sites-available/grimvm"
fi

# ── Write all PHP application files ───────────────────────────
log "Writing application files..."

# public/index.php
cat > "${APP_DIR}/public/index.php" <<'PHP'
<?php
declare(strict_types=1);

define('GRIMVM_ROOT', dirname(__DIR__));
define('GRIMVM_VERSION', '2.0.0');

// Show errors in dev, hide in prod
if (getenv('APP_ENV') !== 'production') {
    ini_set('display_errors', '1');
    error_reporting(E_ALL);
}

$autoload = GRIMVM_ROOT . '/vendor/autoload.php';
if (!file_exists($autoload)) {
    http_response_code(503);
    echo json_encode(['error' => 'Dependencies not installed. Run: composer install']);
    exit;
}

require $autoload;

use DI\ContainerBuilder;
use Slim\Factory\AppFactory;
use GrimVM\Middleware\SessionMiddleware;
use GrimVM\Middleware\RateLimitMiddleware;

$dotenv = Dotenv\Dotenv::createImmutable(GRIMVM_ROOT);
$dotenv->safeLoad();

$builder = new ContainerBuilder();
$builder->addDefinitions(GRIMVM_ROOT . '/config/container.php');

try {
    $container = $builder->build();
} catch (Exception $e) {
    http_response_code(503);
    echo json_encode(['error' => 'Container build failed: ' . $e->getMessage()]);
    exit;
}

AppFactory::setContainer($container);
$app = AppFactory::create();

$errorMiddleware = $app->addErrorMiddleware(true, true, true);
$errorMiddleware->getDefaultErrorHandler()->forceContentType('application/json');

$app->add(new SessionMiddleware());

try {
    $redis = $container->get('redis');
    $app->add(new RateLimitMiddleware($redis));
} catch (Exception $e) {
    // Redis unavailable — skip rate limiting, don't crash
}

require GRIMVM_ROOT . '/routes/web.php';
require GRIMVM_ROOT . '/routes/api.php';
require GRIMVM_ROOT . '/routes/admin.php';

$app->run();
PHP

# config/container.php
cat > "${APP_DIR}/config/container.php" <<'PHP'
<?php
declare(strict_types=1);

use GrimVM\Services\DatabaseService;
use GrimVM\Services\DockerService;
use GrimVM\Services\TmateService;
use GrimVM\Services\RankService;
use GrimVM\Services\AuditService;
use Monolog\Logger;
use Monolog\Handler\StreamHandler;

return [
    'db' => function () {
        return new DatabaseService(
            $_ENV['DB_HOST']     ?? '127.0.0.1',
            $_ENV['DB_DATABASE'] ?? 'grimvm',
            $_ENV['DB_USERNAME'] ?? 'grimvm_user',
            $_ENV['DB_PASSWORD'] ?? 'admin'
        );
    },
    'docker' => function () {
        return new DockerService($_ENV['DOCKER_SOCKET'] ?? '/var/run/docker.sock');
    },
    'tmate' => function () {
        return new TmateService($_ENV['TMATE_SERVER'] ?? 'ssh.tmate.io');
    },
    'rank' => function ($c) {
        return new RankService($c->get('db'));
    },
    'audit' => function ($c) {
        return new AuditService($c->get('db'));
    },
    'redis' => function () {
        $r = new Redis();
        $connected = @$r->connect(
            $_ENV['REDIS_HOST'] ?? '127.0.0.1',
            (int)($_ENV['REDIS_PORT'] ?? 6379),
            2.0
        );
        if (!$connected) {
            throw new RuntimeException('Redis connection failed');
        }
        return $r;
    },
    'logger' => function () {
        $log = new Logger('grimvm');
        $logPath = ($_ENV['APP_DIR'] ?? '/var/www/grimvm') . '/storage/logs/app.log';
        $log->pushHandler(new StreamHandler($logPath, Logger::DEBUG));
        return $log;
    },
];
PHP

# app/Services/DatabaseService.php
cat > "${APP_DIR}/app/Services/DatabaseService.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Services;

class DatabaseService
{
    private \PDO $pdo;

    public function __construct(string $host, string $db, string $user, string $pass)
    {
        $dsn = "mysql:host={$host};dbname={$db};charset=utf8mb4;port=3306";
        $this->pdo = new \PDO($dsn, $user, $pass, [
            \PDO::ATTR_ERRMODE            => \PDO::ERRMODE_EXCEPTION,
            \PDO::ATTR_DEFAULT_FETCH_MODE => \PDO::FETCH_ASSOC,
            \PDO::ATTR_EMULATE_PREPARES   => false,
            \PDO::ATTR_TIMEOUT            => 5,
        ]);
    }

    public function query(string $sql, array $params = []): \PDOStatement
    {
        $stmt = $this->pdo->prepare($sql);
        $stmt->execute($params);
        return $stmt;
    }

    public function fetch(string $sql, array $params = []): ?array
    {
        $result = $this->query($sql, $params)->fetch();
        return $result ?: null;
    }

    public function fetchAll(string $sql, array $params = []): array
    {
        return $this->query($sql, $params)->fetchAll();
    }

    public function insert(string $sql, array $params = []): string
    {
        $this->query($sql, $params);
        return $this->pdo->lastInsertId();
    }

    public function execute(string $sql, array $params = []): int
    {
        return $this->query($sql, $params)->rowCount();
    }
}
PHP

# app/Services/DockerService.php
cat > "${APP_DIR}/app/Services/DockerService.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Services;

class DockerService
{
    private string $socket;

    public function __construct(string $socket = '/var/run/docker.sock')
    {
        $this->socket = $socket;
    }

    private function request(string $method, string $path, array $body = []): array
    {
        if (!file_exists($this->socket)) {
            throw new \RuntimeException('Docker socket not found: ' . $this->socket);
        }

        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_UNIX_SOCKET_PATH => $this->socket,
            CURLOPT_URL              => 'http://localhost/v1.43' . $path,
            CURLOPT_RETURNTRANSFER   => true,
            CURLOPT_TIMEOUT          => 30,
            CURLOPT_HTTPHEADER       => ['Content-Type: application/json'],
        ]);

        if ($method === 'POST') {
            curl_setopt($ch, CURLOPT_POST, true);
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body));
        } elseif ($method === 'DELETE') {
            curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'DELETE');
        }

        $response = curl_exec($ch);
        $code     = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $error    = curl_error($ch);
        curl_close($ch);

        if ($response === false) {
            throw new \RuntimeException('Docker request failed: ' . $error);
        }

        return ['code' => $code, 'body' => json_decode($response, true) ?? []];
    }

    public function createContainer(array $config): string
    {
        $result = $this->request('POST',
            '/containers/create?name=grimvm_' . $config['uuid'],
            [
                'Image'    => $config['image'],
                'Hostname' => 'grimvm-' . substr($config['uuid'], 0, 8),
                'Env'      => $config['env'] ?? [],
                'Cmd'      => $config['cmd'] ?? [],
                'Tty'      => true,
                'OpenStdin'=> true,
                'HostConfig' => [
                    'Memory'        => $config['memory_mb'] * 1024 * 1024,
                    'NanoCpus'      => $config['cpu_cores'] * 1_000_000_000,
                    'RestartPolicy' => ['Name' => 'unless-stopped'],
                    'Binds'         => $config['mounts'] ?? [],
                ],
                'Labels' => [
                    'grimvm.managed' => 'true',
                    'grimvm.uuid'    => $config['uuid'],
                    'grimvm.owner'   => (string)$config['owner_id'],
                ],
            ]
        );

        if ($result['code'] !== 201) {
            throw new \RuntimeException('Container create failed: ' . json_encode($result['body']));
        }

        return $result['body']['Id'];
    }

    public function startContainer(string $id): bool
    {
        $r = $this->request('POST', "/containers/{$id}/start");
        return in_array($r['code'], [204, 304]);
    }

    public function stopContainer(string $id): bool
    {
        $r = $this->request('POST', "/containers/{$id}/stop");
        return in_array($r['code'], [204, 304]);
    }

    public function deleteContainer(string $id): bool
    {
        $r = $this->request('DELETE', "/containers/{$id}?force=true");
        return $r['code'] === 204;
    }

    public function listContainers(): array
    {
        $filter = urlencode(json_encode(['label' => ['grimvm.managed=true']]));
        $r = $this->request('GET', "/containers/json?all=true&filters={$filter}");
        return $r['body'] ?? [];
    }
}
PHP

# app/Services/TmateService.php
cat > "${APP_DIR}/app/Services/TmateService.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Services;

class TmateService
{
    public function __construct(private string $server = 'ssh.tmate.io') {}

    public function createSession(string $containerId, string $uuid): array
    {
        $name   = 'gvm-' . substr($uuid, 0, 8);
        $script = "apt-get update -qq && apt-get install -y -qq tmate && "
                . "tmate -S /tmp/{$name}.sock new-session -d -s {$name} && "
                . "tmate -S /tmp/{$name}.sock wait tmate-ready && "
                . "tmate -S /tmp/{$name}.sock display -p '#{tmate_ssh}' > /tmp/{$name}_ssh.txt && "
                . "tmate -S /tmp/{$name}.sock display -p '#{tmate_web}' > /tmp/{$name}_web.txt";

        shell_exec("docker exec {$containerId} bash -c " . escapeshellarg($script) . " 2>/dev/null");

        $ssh = trim(shell_exec("docker exec {$containerId} cat /tmp/{$name}_ssh.txt 2>/dev/null") ?? '');
        $web = trim(shell_exec("docker exec {$containerId} cat /tmp/{$name}_web.txt 2>/dev/null") ?? '');

        return ['ssh' => $ssh, 'web' => $web, 'name' => $name];
    }

    public function killSession(string $containerId, string $uuid): void
    {
        $name = 'gvm-' . substr($uuid, 0, 8);
        shell_exec("docker exec {$containerId} tmate -S /tmp/{$name}.sock kill-session 2>/dev/null");
    }
}
PHP

# app/Services/RankService.php
cat > "${APP_DIR}/app/Services/RankService.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Services;

class RankService
{
    private const THRESHOLDS = ['Newbie' => 0, 'Pro' => 2, 'Ultimate' => 4];

    public function __construct(private DatabaseService $db) {}

    public function recalculate(int $userId): string
    {
        $user = $this->db->fetch('SELECT vps_count FROM users WHERE id = ?', [$userId]);
        if (!$user) return 'Newbie';

        $rank = 'Newbie';
        foreach (self::THRESHOLDS as $r => $min) {
            if ((int)$user['vps_count'] >= $min) $rank = $r;
        }

        $this->db->execute('UPDATE users SET rank = ? WHERE id = ?', [$rank, $userId]);
        return $rank;
    }

    public function claimReward(int $userId, string $code): array
    {
        $user   = $this->db->fetch('SELECT rank FROM users WHERE id = ?', [$userId]);
        $reward = $this->db->fetch(
            'SELECT * FROM rewards WHERE code = ? AND claimed_by IS NULL', [$code]
        );

        if (!$reward) return ['success' => false, 'message' => 'Invalid or already claimed.'];
        if (!in_array($user['rank'], ['Pro', 'Ultimate'])) {
            return ['success' => false, 'message' => "Requires {$reward['rank_req']} rank."];
        }

        $this->db->execute(
            'UPDATE rewards SET claimed_by = ?, claimed_at = NOW() WHERE id = ?',
            [$userId, $reward['id']]
        );
        return ['success' => true, 'reward' => $reward];
    }
}
PHP

# app/Services/AuditService.php
cat > "${APP_DIR}/app/Services/AuditService.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Services;

class AuditService
{
    private const LIMIT = 20;

    public function __construct(private DatabaseService $db) {}

    public function log(int $userId, string $action, string $target = '', string $ip = ''): void
    {
        $this->db->execute(
            'INSERT INTO audit_log (user_id, action, target, ip) VALUES (?,?,?,?)',
            [$userId, $action, $target, $ip]
        );
    }

    public function checkDeleteLimit(int $adminId): array
    {
        $count = (int)($this->db->fetch(
            'SELECT COUNT(*) as c FROM delete_log WHERE admin_id = ? AND DATE(deleted_at) = CURDATE()',
            [$adminId]
        )['c'] ?? 0);

        if ($count >= self::LIMIT) {
            $this->db->execute(
                'UPDATE users SET banned = 1, ban_reason = ? WHERE id = ?',
                ['Auto-ban: exceeded daily delete limit (' . self::LIMIT . ')', $adminId]
            );
            return ['allowed' => false, 'reason' => 'Daily delete limit exceeded. Account suspended.'];
        }

        return ['allowed' => true, 'count' => $count, 'limit' => self::LIMIT];
    }

    public function logDelete(int $adminId, string $uuid): void
    {
        $this->db->execute(
            'INSERT INTO delete_log (admin_id, vps_uuid) VALUES (?,?)',
            [$adminId, $uuid]
        );
    }

    public function getLog(int $limit = 200): array
    {
        return $this->db->fetchAll(
            'SELECT a.*, u.username FROM audit_log a
             LEFT JOIN users u ON u.id = a.user_id
             ORDER BY a.created_at DESC LIMIT ?',
            [$limit]
        );
    }
}
PHP

# app/Models/User.php
cat > "${APP_DIR}/app/Models/User.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Models;

use GrimVM\Services\DatabaseService;

class User
{
    public function __construct(private DatabaseService $db) {}

    public function find(int $id): ?array
    {
        return $this->db->fetch('SELECT * FROM users WHERE id = ?', [$id]);
    }

    public function findByEmail(string $email): ?array
    {
        return $this->db->fetch('SELECT * FROM users WHERE email = ?', [$email]);
    }

    public function findByToken(string $token): ?array
    {
        return $this->db->fetch('SELECT * FROM users WHERE api_token = ?', [$token]);
    }

    public function create(array $data): int
    {
        return (int)$this->db->insert(
            'INSERT INTO users (username, email, password, role) VALUES (?,?,?,?)',
            [
                $data['username'],
                $data['email'],
                password_hash($data['password'], PASSWORD_BCRYPT, ['cost' => 12]),
                $data['role'] ?? 'member',
            ]
        );
    }

    public function all(): array
    {
        return $this->db->fetchAll(
            'SELECT id,username,email,role,rank,vps_count,banned,created_at FROM users ORDER BY created_at DESC'
        );
    }

    public function ban(int $id, string $reason, string $ip = ''): void
    {
        $this->db->execute(
            'UPDATE users SET banned=1, ban_reason=?, ban_ip=? WHERE id=?',
            [$reason, $ip, $id]
        );
    }

    public function unban(int $id): void
    {
        $this->db->execute(
            'UPDATE users SET banned=0, ban_reason=NULL, ban_ip=NULL WHERE id=?', [$id]
        );
    }

    public function mute(int $id, int $minutes): void
    {
        $until = date('Y-m-d H:i:s', strtotime("+{$minutes} minutes"));
        $this->db->execute('UPDATE users SET muted_until=? WHERE id=?', [$until, $id]);
    }
}
PHP

# app/Models/VPS.php
cat > "${APP_DIR}/app/Models/VPS.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Models;

use GrimVM\Services\DatabaseService;

class VPS
{
    public function __construct(private DatabaseService $db) {}

    public function find(string $uuid): ?array
    {
        return $this->db->fetch('SELECT * FROM vps WHERE uuid=?', [$uuid]);
    }

    public function forUser(int $uid): array
    {
        return $this->db->fetchAll(
            'SELECT v.*, n.name as node_name, n.location
             FROM vps v JOIN nodes n ON n.id=v.node_id
             WHERE v.owner_id=? AND v.status!="deleted"
             ORDER BY v.created_at DESC',
            [$uid]
        );
    }

    public function all(): array
    {
        return $this->db->fetchAll(
            'SELECT v.*, u.username, n.name as node_name
             FROM vps v
             JOIN users u ON u.id=v.owner_id
             JOIN nodes n ON n.id=v.node_id
             WHERE v.status!="deleted"
             ORDER BY v.created_at DESC'
        );
    }

    public function create(array $d): string
    {
        $uuid = sprintf('%04x%04x-%04x-%04x-%04x-%04x%04x%04x',
            mt_rand(0,0xffff), mt_rand(0,0xffff), mt_rand(0,0xffff),
            mt_rand(0,0x0fff)|0x4000, mt_rand(0,0x3fff)|0x8000,
            mt_rand(0,0xffff), mt_rand(0,0xffff), mt_rand(0,0xffff)
        );
        $this->db->insert(
            'INSERT INTO vps (uuid,name,owner_id,node_id,image,memory_mb,disk_gb,cpu_cores)
             VALUES (?,?,?,?,?,?,?,?)',
            [$uuid,$d['name'],$d['owner_id'],$d['node_id'],
             $d['image'],$d['memory_mb'],$d['disk_gb'],$d['cpu_cores']]
        );
        return $uuid;
    }

    public function updateStatus(string $uuid, string $status): void
    {
        $this->db->execute('UPDATE vps SET status=? WHERE uuid=?', [$status, $uuid]);
    }

    public function updateContainer(string $uuid, string $cid, ?string $tmate = null): void
    {
        $this->db->execute(
            'UPDATE vps SET container_id=?, tmate_session=? WHERE uuid=?',
            [$cid, $tmate, $uuid]
        );
    }
}
PHP

# app/Middleware/AuthMiddleware.php
cat > "${APP_DIR}/app/Middleware/AuthMiddleware.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Middleware;

use Firebase\JWT\JWT;
use Firebase\JWT\Key;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use Slim\Psr7\Response;

class AuthMiddleware implements MiddlewareInterface
{
    private const HIERARCHY = ['member' => 0, 'admin' => 1, 'owner' => 2];

    public function __construct(private string $required = 'member') {}

    public function process(ServerRequestInterface $req, RequestHandlerInterface $handler): ResponseInterface
    {
        $header = $req->getHeaderLine('Authorization');
        if (!str_starts_with($header, 'Bearer ')) {
            return $this->fail(401, 'Missing token');
        }

        try {
            $payload = JWT::decode(
                substr($header, 7),
                new Key($_ENV['APP_SECRET'] ?? 'fallback-secret', 'HS256')
            );
        } catch (\Throwable $e) {
            return $this->fail(401, 'Invalid or expired token');
        }

        $userLevel = self::HIERARCHY[$payload->role] ?? 0;
        $reqLevel  = self::HIERARCHY[$this->required] ?? 0;

        if ($userLevel < $reqLevel) {
            return $this->fail(403, 'Insufficient permissions');
        }

        return $handler->handle($req->withAttribute('auth_user', [
            'id'   => $payload->sub,
            'role' => $payload->role,
            'rank' => $payload->rank,
        ]));
    }

    private function fail(int $code, string $msg): ResponseInterface
    {
        $res = new Response($code);
        $res->getBody()->write(json_encode(['error' => $msg]));
        return $res->withHeader('Content-Type', 'application/json');
    }
}
PHP

# app/Middleware/SessionMiddleware.php
cat > "${APP_DIR}/app/Middleware/SessionMiddleware.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Middleware;

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;

class SessionMiddleware implements MiddlewareInterface
{
    public function process(ServerRequestInterface $req, RequestHandlerInterface $handler): ResponseInterface
    {
        if (session_status() === PHP_SESSION_NONE) {
            session_set_cookie_params([
                'lifetime' => 86400 * 7,
                'secure'   => true,
                'httponly' => true,
                'samesite' => 'Lax',
            ]);
            session_start();
        }
        return $handler->handle($req);
    }
}
PHP

# app/Middleware/RateLimitMiddleware.php
cat > "${APP_DIR}/app/Middleware/RateLimitMiddleware.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Middleware;

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use Slim\Psr7\Response;

class RateLimitMiddleware implements MiddlewareInterface
{
    private const WINDOW = 60;
    private const LIMIT  = 120;

    public function __construct(private \Redis $redis) {}

    public function process(ServerRequestInterface $req, RequestHandlerInterface $handler): ResponseInterface
    {
        $ip  = $req->getServerParams()['HTTP_CF_CONNECTING_IP']
            ?? $req->getServerParams()['REMOTE_ADDR']
            ?? 'unknown';
        $key = "rl:{$ip}";

        try {
            $hits = $this->redis->incr($key);
            if ($hits === 1) $this->redis->expire($key, self::WINDOW);
            if ($hits > self::LIMIT) {
                $res = new Response(429);
                $res->getBody()->write(json_encode(['error' => 'Rate limit exceeded']));
                return $res->withHeader('Content-Type','application/json')
                           ->withHeader('Retry-After', (string)self::WINDOW);
            }
        } catch (\Throwable) {
            // Redis down — skip rate limiting
        }

        return $handler->handle($req);
    }
}
PHP

# app/Controllers/AuthController.php
cat > "${APP_DIR}/app/Controllers/AuthController.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Controllers;

use GrimVM\Models\User;
use GrimVM\Services\AuditService;
use Firebase\JWT\JWT;
use Psr\Http\Message\ResponseInterface as Res;
use Psr\Http\Message\ServerRequestInterface as Req;

class AuthController
{
    public function __construct(
        private User $user,
        private AuditService $audit
    ) {}

    public function login(Req $req, Res $res): Res
    {
        $b     = (array)$req->getParsedBody();
        $email = trim($b['email'] ?? '');
        $pass  = $b['password'] ?? '';

        $user = $this->user->findByEmail($email);

        if (!$user || !password_verify($pass, $user['password'])) {
            return $this->json($res, ['error' => 'Invalid credentials'], 401);
        }

        if ($user['banned']) {
            return $this->json($res, ['error' => 'Account banned: ' . $user['ban_reason']], 403);
        }

        $token = JWT::encode([
            'sub'  => $user['id'],
            'role' => $user['role'],
            'rank' => $user['rank'],
            'iat'  => time(),
            'exp'  => time() + 86400 * 7,
        ], $_ENV['APP_SECRET'] ?? 'fallback', 'HS256');

        $ip = $req->getServerParams()['HTTP_CF_CONNECTING_IP']
           ?? $req->getServerParams()['REMOTE_ADDR'] ?? '';
        $this->audit->log($user['id'], 'login', '', $ip);

        return $this->json($res, [
            'token' => $token,
            'user'  => [
                'id'       => $user['id'],
                'username' => $user['username'],
                'email'    => $user['email'],
                'role'     => $user['role'],
                'rank'     => $user['rank'],
            ],
        ]);
    }

    public function register(Req $req, Res $res): Res
    {
        $b    = (array)$req->getParsedBody();
        $user = trim($b['username'] ?? '');
        $mail = trim($b['email'] ?? '');
        $pass = $b['password'] ?? '';

        if (!$user || !$mail || !$pass) {
            return $this->json($res, ['error' => 'All fields required'], 400);
        }
        if (!filter_var($mail, FILTER_VALIDATE_EMAIL)) {
            return $this->json($res, ['error' => 'Invalid email'], 400);
        }
        if (strlen($pass) < 6) {
            return $this->json($res, ['error' => 'Password min 6 chars'], 400);
        }

        try {
            $id = $this->user->create(['username'=>$user,'email'=>$mail,'password'=>$pass]);
            return $this->json($res, ['message' => 'Account created', 'id' => $id], 201);
        } catch (\PDOException) {
            return $this->json($res, ['error' => 'Username or email already exists'], 409);
        }
    }

    private function json(Res $res, array $data, int $code = 200): Res
    {
        $res->getBody()->write(json_encode($data));
        return $res->withHeader('Content-Type','application/json')->withStatus($code);
    }
}
PHP

# app/Controllers/VPSController.php
cat > "${APP_DIR}/app/Controllers/VPSController.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Controllers;

use GrimVM\Models\{VPS, User};
use GrimVM\Services\{DockerService, TmateService, RankService, AuditService, DatabaseService};
use Psr\Http\Message\ResponseInterface as Res;
use Psr\Http\Message\ServerRequestInterface as Req;

class VPSController
{
    public function __construct(
        private VPS $vps,
        private User $user,
        private DockerService $docker,
        private TmateService $tmate,
        private RankService $rank,
        private AuditService $audit,
        private DatabaseService $db
    ) {}

    public function create(Req $req, Res $res): Res
    {
        $admin = $req->getAttribute('auth_user');
        $b     = (array)$req->getParsedBody();

        foreach (['name','owner_id','node_id','image','memory_mb','disk_gb','cpu_cores'] as $f) {
            if (empty($b[$f])) return $this->json($res, ['error' => "Missing: {$f}"], 400);
        }

        $uuid = $this->vps->create([
            'name'      => $b['name'],
            'owner_id'  => (int)$b['owner_id'],
            'node_id'   => (int)$b['node_id'],
            'image'     => $b['image'],
            'memory_mb' => (int)$b['memory_mb'],
            'disk_gb'   => (int)$b['disk_gb'],
            'cpu_cores' => (int)$b['cpu_cores'],
        ]);

        try {
            $cid = $this->docker->createContainer([
                'uuid'      => $uuid,
                'image'     => $b['image'],
                'memory_mb' => (int)$b['memory_mb'],
                'disk_gb'   => (int)$b['disk_gb'],
                'cpu_cores' => (int)$b['cpu_cores'],
                'owner_id'  => (int)$b['owner_id'],
            ]);
            $this->docker->startContainer($cid);
            $tmate = $this->tmate->createSession($cid, $uuid);
            $this->vps->updateContainer($uuid, $cid, $tmate['ssh']);
            $this->vps->updateStatus($uuid, 'running');
        } catch (\Throwable $e) {
            $this->vps->updateStatus($uuid, 'stopped');
            $cid   = '';
            $tmate = ['ssh' => '', 'web' => ''];
        }

        $this->db->execute(
            'UPDATE users SET vps_count = vps_count + 1 WHERE id = ?',
            [(int)$b['owner_id']]
        );
        $newRank = $this->rank->recalculate((int)$b['owner_id']);
        $this->audit->log($admin['id'], 'vps_create', $uuid);

        return $this->json($res, [
            'uuid'       => $uuid,
            'tmate_ssh'  => $tmate['ssh'] ?? '',
            'tmate_web'  => $tmate['web'] ?? '',
            'owner_rank' => $newRank,
        ], 201);
    }

    public function delete(Req $req, Res $res, array $args): Res
    {
        $admin = $req->getAttribute('auth_user');
        $limit = $this->audit->checkDeleteLimit($admin['id']);
        if (!$limit['allowed']) {
            return $this->json($res, ['error' => $limit['reason']], 429);
        }

        $vps = $this->vps->find($args['uuid']);
        if (!$vps) return $this->json($res, ['error' => 'Not found'], 404);

        if ($vps['container_id']) {
            try {
                $this->tmate->killSession($vps['container_id'], $vps['uuid']);
                $this->docker->stopContainer($vps['container_id']);
                $this->docker->deleteContainer($vps['container_id']);
            } catch (\Throwable) {}
        }

        $this->vps->updateStatus($vps['uuid'], 'deleted');
        $this->db->execute(
            'UPDATE users SET vps_count = GREATEST(vps_count-1,0) WHERE id=?',
            [$vps['owner_id']]
        );
        $this->rank->recalculate((int)$vps['owner_id']);
        $this->audit->logDelete($admin['id'], $vps['uuid']);

        return $this->json($res, ['message' => 'Deleted', 'uuid' => $vps['uuid']]);
    }

    public function power(Req $req, Res $res, array $args): Res
    {
        $user   = $req->getAttribute('auth_user');
        $vps    = $this->vps->find($args['uuid']);
        $action = $args['action'];

        if (!$vps) return $this->json($res, ['error' => 'Not found'], 404);

        if ($vps['owner_id'] !== $user['id'] && !in_array($user['role'], ['admin','owner'])) {
            return $this->json($res, ['error' => 'Forbidden'], 403);
        }

        try {
            match ($action) {
                'start'   => $this->docker->startContainer($vps['container_id']),
                'stop'    => $this->docker->stopContainer($vps['container_id']),
                'restart' => (function() use ($vps) {
                    $this->docker->stopContainer($vps['container_id']);
                    $this->docker->startContainer($vps['container_id']);
                })(),
                default => throw new \InvalidArgumentException('Invalid action')
            };
            $status = $action === 'stop' ? 'stopped' : 'running';
            $this->vps->updateStatus($vps['uuid'], $status);
        } catch (\Throwable $e) {
            return $this->json($res, ['error' => $e->getMessage()], 500);
        }

        return $this->json($res, ['message' => "VPS {$action} OK"]);
    }

    public function list(Req $req, Res $res): Res
    {
        $user = $req->getAttribute('auth_user');
        return $this->json($res, ['vps' => $this->vps->forUser($user['id'])]);
    }

    public function adminList(Req $req, Res $res): Res
    {
        return $this->json($res, ['vps' => $this->vps->all()]);
    }

    private function json(Res $res, array $data, int $code = 200): Res
    {
        $res->getBody()->write(json_encode($data));
        return $res->withHeader('Content-Type','application/json')->withStatus($code);
    }
}
PHP

# app/Controllers/AdminController.php
cat > "${APP_DIR}/app/Controllers/AdminController.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Controllers;

use GrimVM\Models\User;
use GrimVM\Services\{AuditService, DatabaseService};
use Psr\Http\Message\ResponseInterface as Res;
use Psr\Http\Message\ServerRequestInterface as Req;

class AdminController
{
    public function __construct(
        private User $user,
        private AuditService $audit,
        private DatabaseService $db
    ) {}

    public function listUsers(Req $req, Res $res): Res
    {
        return $this->json($res, ['users' => $this->user->all()]);
    }

    public function banUser(Req $req, Res $res, array $args): Res
    {
        $admin  = $req->getAttribute('auth_user');
        $b      = (array)$req->getParsedBody();
        $this->user->ban((int)$args['id'], $b['reason'] ?? 'No reason', $b['ip'] ?? '');
        $this->audit->log($admin['id'], 'ban', $args['id']);
        return $this->json($res, ['message' => 'Banned']);
    }

    public function unbanUser(Req $req, Res $res, array $args): Res
    {
        $admin = $req->getAttribute('auth_user');
        $this->user->unban((int)$args['id']);
        $this->audit->log($admin['id'], 'unban', $args['id']);
        return $this->json($res, ['message' => 'Unbanned']);
    }

    public function muteUser(Req $req, Res $res, array $args): Res
    {
        $admin = $req->getAttribute('auth_user');
        $b     = (array)$req->getParsedBody();
        $min   = (int)($b['minutes'] ?? 60);
        $this->user->mute((int)$args['id'], $min);
        $this->audit->log($admin['id'], 'mute', $args['id']);
        return $this->json($res, ['message' => "Muted {$min} min"]);
    }

    public function createNode(Req $req, Res $res): Res
    {
        $admin = $req->getAttribute('auth_user');
        $b     = (array)$req->getParsedBody();
        $id    = $this->db->insert(
            'INSERT INTO nodes (name,location,ip,port,memory_mb,disk_gb,cpu_cores)
             VALUES (?,?,?,?,?,?,?)',
            [$b['name'],$b['location'],$b['ip'],
             (int)($b['port']??2222),(int)$b['memory_mb'],
             (int)$b['disk_gb'],(int)$b['cpu_cores']]
        );
        $this->audit->log($admin['id'], 'node_create', (string)$id);
        return $this->json($res, ['message' => 'Node created', 'id' => $id], 201);
    }

    public function listNodes(Req $req, Res $res): Res
    {
        return $this->json($res, ['nodes' => $this->db->fetchAll('SELECT * FROM nodes ORDER BY id')]);
    }

    public function getSettings(Req $req, Res $res): Res
    {
        $rows = $this->db->fetchAll('SELECT * FROM settings');
        return $this->json($res, ['settings' => array_column($rows, 'value', 'key')]);
    }

    public function updateSetting(Req $req, Res $res, array $args): Res
    {
        $b = (array)$req->getParsedBody();
        $this->db->execute(
            'INSERT INTO settings (`key`,`value`) VALUES (?,?) ON DUPLICATE KEY UPDATE `value`=?',
            [$args['key'], $b['value']??'', $b['value']??'']
        );
        return $this->json($res, ['message' => 'Updated']);
    }

    public function getAuditLog(Req $req, Res $res): Res
    {
        return $this->json($res, ['log' => $this->audit->getLog()]);
    }

    private function json(Res $res, array $data, int $code = 200): Res
    {
        $res->getBody()->write(json_encode($data));
        return $res->withHeader('Content-Type','application/json')->withStatus($code);
    }
}
PHP

# routes/web.php
cat > "${APP_DIR}/routes/web.php" <<'PHP'
<?php
$app->get('/', function($req, $res) {
    return $res->withHeader('Location', '/dashboard')->withStatus(302);
});

$app->get('/dashboard[/{path:.*}]', function($req, $res) {
    $f = GRIMVM_ROOT . '/public/index.html';
    $res->getBody()->write(file_exists($f) ? file_get_contents($f) : '<h1>GrimVM</h1>');
    return $res->withHeader('Content-Type','text/html');
});

$app->get('/admin[/{path:.*}]', function($req, $res) {
    $f = GRIMVM_ROOT . '/public/index.html';
    $res->getBody()->write(file_exists($f) ? file_get_contents($f) : '<h1>GrimVM Admin</h1>');
    return $res->withHeader('Content-Type','text/html');
});
PHP

# routes/api.php
cat > "${APP_DIR}/routes/api.php" <<'PHP'
<?php
use GrimVM\Controllers\{AuthController, VPSController};
use GrimVM\Middleware\AuthMiddleware;

$app->group('/api/auth', function($g) {
    $g->post('/login',    [AuthController::class, 'login']);
    $g->post('/register', [AuthController::class, 'register']);
});

$app->group('/api/vps', function($g) {
    $g->get('',                              [VPSController::class, 'list']);
    $g->post('/{uuid}/power/{action}',       [VPSController::class, 'power']);
})->add(new AuthMiddleware('member'));

$app->group('/api/admin/vps', function($g) {
    $g->post('',          [VPSController::class, 'create']);
    $g->get('',           [VPSController::class, 'adminList']);
    $g->delete('/{uuid}', [VPSController::class, 'delete']);
})->add(new AuthMiddleware('admin'));
PHP

# routes/admin.php
cat > "${APP_DIR}/routes/admin.php" <<'PHP'
<?php
use GrimVM\Controllers\AdminController;
use GrimVM\Middleware\AuthMiddleware;

$app->group('/api/admin', function($g) {
    $g->get('/users',              [AdminController::class, 'listUsers']);
    $g->post('/users/{id}/ban',    [AdminController::class, 'banUser']);
    $g->post('/users/{id}/unban',  [AdminController::class, 'unbanUser']);
    $g->post('/users/{id}/mute',   [AdminController::class, 'muteUser']);
    $g->post('/nodes',             [AdminController::class, 'createNode']);
    $g->get('/nodes',              [AdminController::class, 'listNodes']);
    $g->get('/settings',           [AdminController::class, 'getSettings']);
    $g->put('/settings/{key}',     [AdminController::class, 'updateSetting']);
    $g->get('/audit',              [AdminController::class, 'getAuditLog']);
})->add(new AuthMiddleware('admin'));
PHP

# ── Frontend HTML ─────────────────────────────────────────────
log "Writing frontend..."
cat > "${APP_DIR}/public/index.html" <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>GrimVM</title>
<style>
:root{--bg:#0a0c10;--bg2:#111420;--bg3:#191c2a;--border:#1e2235;--accent:#6c47ff;--green:#22c55e;--red:#ef4444;--yellow:#f59e0b;--text:#e2e8f0;--muted:#64748b;--mono:'JetBrains Mono',monospace}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--text);font-family:Inter,sans-serif;min-height:100vh}
#login{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;background:var(--bg);z-index:99}
.card{background:var(--bg2);border:1px solid var(--border);border-radius:12px;padding:36px;width:360px}
.logo{font-family:var(--mono);font-size:24px;font-weight:700;color:var(--accent);margin-bottom:4px}
.sub{color:var(--muted);font-size:12px;margin-bottom:24px}
.fg{margin-bottom:14px}
.fg label{display:block;font-size:11px;color:var(--muted);margin-bottom:5px;text-transform:uppercase;letter-spacing:.05em}
.fg input{width:100%;padding:9px 12px;background:var(--bg3);border:1px solid var(--border);border-radius:7px;color:var(--text);font-size:13px;outline:none}
.fg input:focus{border-color:var(--accent)}
.btn{width:100%;padding:10px;background:var(--accent);color:#fff;border:none;border-radius:7px;font-size:14px;font-weight:600;cursor:pointer}
.btn:hover{opacity:.9}
.err{color:var(--red);font-size:12px;margin-bottom:10px;display:none}
#app{display:none}
.sidebar{position:fixed;left:0;top:0;bottom:0;width:210px;background:var(--bg2);border-right:1px solid var(--border);display:flex;flex-direction:column}
.slogo{padding:20px;font-family:var(--mono);font-size:17px;font-weight:700;color:var(--accent);border-bottom:1px solid var(--border)}
.slogo small{color:var(--muted);font-size:10px;display:block;font-weight:400}
nav{flex:1;padding:12px 0}
.ni{padding:9px 18px;cursor:pointer;color:var(--muted);font-size:13px;display:flex;align-items:center;gap:8px;transition:.15s}
.ni:hover,.ni.a{color:var(--text);background:var(--bg3)}
.ni.a{border-left:2px solid var(--accent)}
.suser{padding:14px 18px;border-top:1px solid var(--border);font-size:12px;color:var(--muted)}
.badge{display:inline-block;padding:2px 7px;border-radius:4px;font-size:10px;font-weight:700;background:var(--accent);color:#fff;margin-top:3px}
.badge.Pro{background:#0ea5e9}.badge.Ultimate{background:linear-gradient(90deg,#6c47ff,#ec4899)}
.main{margin-left:210px;padding:28px;min-height:100vh}
.pg{display:none}.pg.a{display:block}
.ptitle{font-size:20px;font-weight:700;margin-bottom:20px}
.srow{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:14px;margin-bottom:24px}
.sc{background:var(--bg2);border:1px solid var(--border);border-radius:9px;padding:18px}
.sl{font-size:10px;color:var(--muted);text-transform:uppercase;letter-spacing:.07em;margin-bottom:6px}
.sv{font-size:26px;font-weight:700;font-family:var(--mono)}
.sv.g{color:var(--green)}.sv.ac{color:var(--accent)}
.tc{background:var(--bg2);border:1px solid var(--border);border-radius:9px;overflow:hidden}
.th{padding:14px 18px;border-bottom:1px solid var(--border);font-size:13px;font-weight:600;display:flex;justify-content:space-between;align-items:center}
table{width:100%;border-collapse:collapse}
th{padding:10px 18px;text-align:left;font-size:10px;font-weight:600;color:var(--muted);text-transform:uppercase;letter-spacing:.07em;border-bottom:1px solid var(--border)}
td{padding:12px 18px;font-size:13px;border-bottom:1px solid var(--border)}
tr:last-child td{border:none}
tr:hover td{background:var(--bg3)}
.dot{display:inline-block;width:7px;height:7px;border-radius:50%;margin-right:5px}
.dot.running{background:var(--green);box-shadow:0 0 5px var(--green)}
.dot.stopped{background:var(--muted)}
.ab{padding:3px 9px;border-radius:4px;font-size:11px;font-weight:600;cursor:pointer;border:none;margin-right:3px}
.ab.s{background:rgba(34,197,94,.15);color:var(--green)}
.ab.d{background:rgba(239,68,68,.15);color:var(--red)}
.ab.c{background:rgba(108,71,255,.15);color:var(--accent)}
.con{background:#000;border:1px solid var(--border);border-radius:8px;padding:14px;font-family:var(--mono);font-size:12px;color:#00ff88;min-height:260px;white-space:pre-wrap;overflow-y:auto}
.tmi{background:var(--bg3);border:1px solid var(--border);border-radius:7px;padding:12px 16px;margin-top:14px;font-size:12px;font-family:var(--mono)}
select{background:var(--bg3);border:1px solid var(--border);border-radius:6px;padding:7px 11px;color:var(--text);font-size:13px;margin-bottom:14px;width:100%}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:12px}
#toast{position:fixed;bottom:20px;right:20px;background:var(--bg2);border:1px solid var(--border);border-radius:8px;padding:11px 16px;font-size:13px;transform:translateY(60px);transition:.2s;z-index:999}
#toast.show{transform:translateY(0)}
#toast.ok{border-color:var(--green);color:var(--green)}
#toast.err{border-color:var(--red);color:var(--red)}
</style>
</head>
<body>
<div id="login">
  <div class="card">
    <div class="logo">Grim<span style="color:#fff">VM</span></div>
    <div class="sub">ArizNodes Team · Project #5</div>
    <div class="err" id="lerr"></div>
    <div class="fg"><label>Email</label><input id="lemail" type="email" placeholder="admin@gmail.com"></div>
    <div class="fg"><label>Password</label><input id="lpass" type="password" placeholder="••••••••"></div>
    <button class="btn" onclick="login()">Sign In</button>
    <div style="text-align:center;margin-top:12px;font-size:12px;color:var(--muted)">
      <a href="#" onclick="showReg()" style="color:var(--accent)">Create account</a>
    </div>
  </div>
</div>

<div id="app">
  <div class="sidebar">
    <div class="slogo">GrimVM<small>Hypervisor Panel #5</small></div>
    <nav>
      <div class="ni a" onclick="pg('dash')">⬛ Dashboard</div>
      <div class="ni" onclick="pg('srv')">🖥 My Servers</div>
      <div class="ni" onclick="pg('con')">⌨ Console</div>
      <div class="ni" onclick="pg('rank')">⭐ Ranks</div>
      <div id="anav" style="display:none"><div class="ni" onclick="pg('adm')">🔐 Admin</div></div>
    </nav>
    <div class="suser">
      <div id="suname">—</div>
      <span class="badge" id="subadge">Newbie</span>
    </div>
  </div>

  <div class="main">
    <div class="pg a" id="pg-dash">
      <div class="ptitle">Dashboard</div>
      <div class="srow">
        <div class="sc"><div class="sl">Your VPS</div><div class="sv ac" id="st-vps">0</div></div>
        <div class="sc"><div class="sl">Running</div><div class="sv g" id="st-run">0</div></div>
        <div class="sc"><div class="sl">Rank</div><div class="sv" id="st-rank">Newbie</div></div>
      </div>
      <div class="tc">
        <div class="th">Recent Servers</div>
        <table><thead><tr><th>Name</th><th>Status</th><th>Node</th><th>Location</th></tr></thead>
        <tbody id="dt"></tbody></table>
      </div>
    </div>

    <div class="pg" id="pg-srv">
      <div class="ptitle">My Servers</div>
      <div class="tc">
        <div class="th">All Servers <span style="font-size:11px;color:var(--muted)">Admins provision VPS</span></div>
        <table><thead><tr><th>UUID</th><th>Name</th><th>Status</th><th>CPU</th><th>RAM</th><th>Actions</th></tr></thead>
        <tbody id="st"></tbody></table>
      </div>
    </div>

    <div class="pg" id="pg-con">
      <div class="ptitle">Console</div>
      <div class="tc" style="padding:18px">
        <select id="csel"><option>— Select VPS —</option></select>
        <div class="con" id="cout">Select a VPS above to view console access.</div>
        <div class="tmi" id="tmi" style="display:none">
          <div><span style="color:var(--muted)">SSH: </span><span id="tssh" style="color:var(--accent)"></span></div>
          <div style="margin-top:5px"><span style="color:var(--muted)">Web: </span><a id="tweb" style="color:var(--green)" target="_blank"></a></div>
        </div>
      </div>
    </div>

    <div class="pg" id="pg-rank">
      <div class="ptitle">Rank System</div>
      <div style="display:grid;gap:14px">
        <div class="tc" style="padding:22px">
          <div style="font-size:15px;font-weight:600;margin-bottom:14px">Current Rank: <span class="badge" id="rdsp">Newbie</span></div>
          <div style="color:var(--muted);font-size:13px;line-height:2">
            <div>🔵 <b style="color:var(--text)">Newbie</b> — Default. 0–1 VPS.</div>
            <div>🔷 <b style="color:#0ea5e9">Pro</b> — 2+ VPS assigned.</div>
            <div>💜 <b style="color:#a855f7">Ultimate</b> — 4+ VPS. Claim exclusive rewards.</div>
          </div>
        </div>
        <div class="tc" style="padding:22px">
          <div style="font-size:14px;font-weight:600;margin-bottom:12px">Claim Reward</div>
          <div style="display:flex;gap:10px">
            <input id="rcode" placeholder="Reward code" style="flex:1;background:var(--bg3);border:1px solid var(--border);border-radius:6px;padding:9px 12px;color:var(--text);font-size:13px">
            <button class="btn" style="width:auto;padding:9px 16px" onclick="claimR()">Claim</button>
          </div>
          <div id="rmsg" style="margin-top:10px;font-size:13px"></div>
        </div>
      </div>
    </div>

    <div class="pg" id="pg-adm">
      <div class="ptitle">Admin Panel</div>
      <div style="display:grid;gap:18px">
        <div class="tc">
          <div class="th">Users</div>
          <table><thead><tr><th>ID</th><th>Username</th><th>Role</th><th>Rank</th><th>VPS</th><th>Status</th><th>Actions</th></tr></thead>
          <tbody id="aut"></tbody></table>
        </div>
        <div class="tc">
          <div class="th">All VPS</div>
          <table><thead><tr><th>UUID</th><th>Name</th><th>Owner</th><th>Status</th><th>Actions</th></tr></thead>
          <tbody id="avt"></tbody></table>
        </div>
        <div class="tc" style="padding:22px">
          <div style="font-size:14px;font-weight:600;margin-bottom:16px">Create VPS</div>
          <div class="grid2">
            <div class="fg"><label>Name</label><input id="vn" placeholder="my-server"></div>
            <div class="fg"><label>Owner ID</label><input id="vo" placeholder="1"></div>
            <div class="fg"><label>Node ID</label><input id="vnd" placeholder="1"></div>
            <div class="fg"><label>Docker Image</label><input id="vi" placeholder="ubuntu:22.04"></div>
            <div class="fg"><label>RAM (MB)</label><input id="vm" placeholder="512"></div>
            <div class="fg"><label>Disk (GB)</label><input id="vd" placeholder="10"></div>
            <div class="fg"><label>CPU Cores</label><input id="vc" placeholder="1"></div>
          </div>
          <button class="btn" style="width:auto;padding:9px 20px" onclick="mkVPS()">Create VPS</button>
        </div>
      </div>
    </div>
  </div>
</div>

<div id="toast"></div>

<script>
const A='/api';
let tok=localStorage.getItem('gvm_tok');
let me=JSON.parse(localStorage.getItem('gvm_me')||'null');
let vlist=[];

async function api(m,p,b){
  const o={method:m,headers:{'Content-Type':'application/json'}};
  if(tok)o.headers['Authorization']='Bearer '+tok;
  if(b)o.body=JSON.stringify(b);
  try{
    const r=await fetch(A+p,o);
    return{ok:r.ok,status:r.status,data:await r.json()};
  }catch(e){
    return{ok:false,data:{error:'Network error: '+e.message}};
  }
}

function toast(msg,t='ok'){
  const el=document.getElementById('toast');
  el.textContent=msg;el.className='show '+t;
  setTimeout(()=>el.className='',3000);
}

function pg(n){
  document.querySelectorAll('.pg').forEach(p=>p.classList.remove('a'));
  document.querySelectorAll('.ni').forEach(i=>i.classList.remove('a'));
  document.getElementById('pg-'+n)?.classList.add('a');
  if(n==='srv')loadSrv();
  if(n==='adm')loadAdm();
  if(n==='con')loadCon();
}

async function login(){
  const e=document.getElementById('lemail').value;
  const p=document.getElementById('lpass').value;
  const{ok,data}=await api('POST','/auth/login',{email:e,password:p});
  if(!ok){
    const el=document.getElementById('lerr');
    el.textContent=data.error||'Login failed';el.style.display='block';return;
  }
  tok=data.token;me=data.user;
  localStorage.setItem('gvm_tok',tok);
  localStorage.setItem('gvm_me',JSON.stringify(me));
  boot();
}

function boot(){
  if(!tok)return;
  document.getElementById('login').style.display='none';
  document.getElementById('app').style.display='block';
  document.getElementById('suname').textContent=me.username;
  const b=document.getElementById('subadge');
  b.textContent=me.rank;b.className='badge '+me.rank;
  document.getElementById('st-rank').textContent=me.rank;
  document.getElementById('rdsp').textContent=me.rank;
  if(['admin','owner'].includes(me.role))
    document.getElementById('anav').style.display='block';
  loadDash();
}

async function loadDash(){
  const{ok,data}=await api('GET','/vps',null);
  if(!ok)return;
  vlist=data.vps||[];
  document.getElementById('st-vps').textContent=vlist.length;
  document.getElementById('st-run').textContent=vlist.filter(v=>v.status==='running').length;
  document.getElementById('dt').innerHTML=vlist.slice(0,5).map(v=>`
    <tr>
      <td>${v.name}</td>
      <td><span class="dot ${v.status}"></span>${v.status}</td>
      <td>${v.node_name||'—'}</td>
      <td>${v.location||'—'}</td>
    </tr>`).join('')||'<tr><td colspan="4" style="color:var(--muted);text-align:center">No VPS assigned.</td></tr>';
}

async function loadSrv(){
  const{ok,data}=await api('GET','/vps',null);
  if(!ok)return;
  vlist=data.vps||[];
  document.getElementById('st').innerHTML=vlist.map(v=>`
    <tr>
      <td style="font-family:var(--mono);font-size:11px">${v.uuid.slice(0,8)}</td>
      <td>${v.name}</td>
      <td><span class="dot ${v.status}"></span>${v.status}</td>
      <td>${v.cpu_cores} vCPU</td>
      <td>${v.memory_mb} MB</td>
      <td>
        <button class="ab s" onclick="pwr('${v.uuid}','start')">▶</button>
        <button class="ab d" onclick="pwr('${v.uuid}','stop')">■</button>
        <button class="ab c" onclick="openCon('${v.uuid}')">⌨</button>
      </td>
    </tr>`).join('')||'<tr><td colspan="6" style="color:var(--muted);text-align:center">No VPS found.</td></tr>';
}

async function pwr(uuid,act){
  const{ok,data}=await api('POST',`/vps/${uuid}/power/${act}`,{});
  toast(ok?data.message:data.error,ok?'ok':'err');
  if(ok)loadSrv();
}

function openCon(uuid){
  pg('con');
  const v=vlist.find(x=>x.uuid===uuid);
  if(!v)return;
  document.getElementById('cout').textContent=
    `Server: ${v.name}\nStatus: ${v.status}\nUUID:   ${uuid}\n\nUse tmate session below for terminal access.`;
  if(v.tmate_session){
    document.getElementById('tmi').style.display='block';
    document.getElementById('tssh').textContent=v.tmate_session;
    const web='https://tmate.io/t/'+v.tmate_session.split('/').pop();
    const a=document.getElementById('tweb');
    a.textContent=web;a.href=web;
  }
}

function loadCon(){
  const s=document.getElementById('csel');
  s.innerHTML='<option>— Select VPS —</option>'+
    vlist.map(v=>`<option value="${v.uuid}">${v.name} (${v.status})</option>`).join('');
  s.onchange=()=>{if(s.selectedIndex>0)openCon(s.value)};
}

async function loadAdm(){
  const[ur,vr]=await Promise.all([
    api('GET','/admin/users',null),
    api('GET','/admin/vps',null)
  ]);
  const users=ur.data.users||[];
  const vpss=vr.data.vps||[];

  document.getElementById('aut').innerHTML=users.map(u=>`
    <tr>
      <td>${u.id}</td><td>${u.username}</td><td>${u.role}</td>
      <td><span class="badge ${u.rank}">${u.rank}</span></td>
      <td>${u.vps_count}</td>
      <td style="color:${u.banned?'var(--red)':'var(--green)'}">${u.banned?'Banned':'Active'}</td>
      <td>
        <button class="ab d" onclick="banU(${u.id})">Ban</button>
        <button class="ab s" onclick="unbanU(${u.id})">Unban</button>
      </td>
    </tr>`).join('');

  document.getElementById('avt').innerHTML=vpss.map(v=>`
    <tr>
      <td style="font-family:var(--mono);font-size:11px">${v.uuid.slice(0,8)}</td>
      <td>${v.name}</td><td>${v.username}</td>
      <td><span class="dot ${v.status}"></span>${v.status}</td>
      <td><button class="ab d" onclick="delVPS('${v.uuid}')">Delete</button></td>
    </tr>`).join('');
}

async function mkVPS(){
  const b={
    name:document.getElementById('vn').value,
    owner_id:parseInt(document.getElementById('vo').value),
    node_id:parseInt(document.getElementById('vnd').value),
    image:document.getElementById('vi').value,
    memory_mb:parseInt(document.getElementById('vm').value),
    disk_gb:parseInt(document.getElementById('vd').value),
    cpu_cores:parseInt(document.getElementById('vc').value),
  };
  const{ok,data}=await api('POST','/admin/vps',b);
  toast(ok?'VPS created: '+data.uuid:data.error,ok?'ok':'err');
  if(ok)loadAdm();
}

async function delVPS(uuid){
  if(!confirm('Delete VPS '+uuid+'?'))return;
  const{ok,data}=await api('DELETE','/admin/vps/'+uuid,null);
  toast(ok?'Deleted':data.error,ok?'ok':'err');
  if(ok)loadAdm();
}

async function banU(id){
  const r=prompt('Ban reason:');if(!r)return;
  const{ok,data}=await api('POST','/admin/users/'+id+'/ban',{reason:r});
  toast(ok?'Banned':data.error,ok?'ok':'err');if(ok)loadAdm();
}

async function unbanU(id){
  const{ok,data}=await api('POST','/admin/users/'+id+'/unban',{});
  toast(ok?'Unbanned':data.error,ok?'ok':'err');if(ok)loadAdm();
}

async function claimR(){
  const c=document.getElementById('rcode').value;
  const{ok,data}=await api('POST','/api/rewards/claim',{code:c});
  const m=document.getElementById('rmsg');
  m.textContent=ok?'✅ '+data.reward.name:'❌ '+(data.message||data.error);
  m.style.color=ok?'var(--green)':'var(--red)';
}

function showReg(){
  const u=prompt('Username:'),e=prompt('Email:'),p=prompt('Password:');
  if(!u||!e||!p)return;
  api('POST','/auth/register',{username:u,email:e,password:p}).then(({ok,data})=>{
    alert(ok?'Account created! Sign in.':'Error: '+data.error);
  });
}

if(tok)boot();
</script>
</body>
</html>
HTML

# ── Composer install ──────────────────────────────────────────
log "Running Composer..."
cd "${APP_DIR}"
COMPOSER_ALLOW_SUPERUSER=1 composer install \
  --no-dev \
  --optimize-autoloader \
  --no-interaction \
  --no-progress 2>&1 | tail -5

# ── Permissions ───────────────────────────────────────────────
log "Setting permissions..."
chown -R www-data:www-data "${APP_DIR}"
chmod -R 755 "${APP_DIR}"
chmod -R 775 "${APP_DIR}/storage"
chmod 600 "${APP_DIR}/.env"

# ── Reload Nginx ──────────────────────────────────────────────
nginx -t 2>/dev/null && svc_reload nginx

# ── Restore policy-rc.d ───────────────────────────────────────
echo '#!/bin/sh
exit 101' > /usr/sbin/policy-rc.d

# ── Health check ──────────────────────────────────────────────
log "Running health check..."
sleep 2
HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${APP_PORT}/ 2>/dev/null || echo "000")

echo ""
echo -e "${CYAN}${BOLD}══════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  GrimVM v2.0 — Install Complete${RESET}"
echo -e "${CYAN}${BOLD}══════════════════════════════════════════${RESET}"
echo ""
echo -e " Panel URL:   ${GREEN}https://${DOMAIN}${RESET}"
echo -e " Local HTTP:  ${YELLOW}http://localhost:${APP_PORT}${RESET}"
echo -e " Admin login: ${YELLOW}admin / admin${RESET}"
echo -e " HTTP check:  ${HTTP}"
echo ""
echo -e " ${BOLD}Cloudflare Tunnel config:${RESET}"
echo -e "   Type: ${CYAN}HTTP${RESET}"
echo -e "   URL:  ${CYAN}localhost:${APP_PORT}${RESET}"
echo ""
echo -e " GitHub: https://github.com/Vasplayz90OG/GrimVM--5"
echo -e " Copyright Reserved 2026 ArizNodes Team"
echo -e "${CYAN}${BOLD}══════════════════════════════════════════${RESET}"
