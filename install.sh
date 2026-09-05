#!/usr/bin/env bash
# ============================================================
#  GrimVM Panel — Master Installer
#  Author:  Vasplayz90 • ArizNodes Team
#  Project: #5
#  License: MIT
#  Copyright: Reserved 2026 Team • ArizNodes
#  GitHub:  https://github.com/Vasplayz90OG/GrimVM--5
# ============================================================
set -euo pipefail

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${GREEN}[GrimVM]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()  { echo -e "${RED}[ERR]${RESET}   $*"; exit 1; }

# ── Banner ───────────────────────────────────────────────────
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
echo -e " ${BOLD}GrimVM Panel — Project #5${RESET}"
echo -e " Author: Vasplayz90 • ArizNodes Team"
echo -e " License: MIT | Copyright Reserved 2026 ArizNodes"
echo -e " GitHub: https://github.com/Vasplayz90OG/GrimVM--5"
echo -e " ─────────────────────────────────────────────────"
echo ""

# ── OS Check ─────────────────────────────────────────────────
if [[ ! -f /etc/os-release ]]; then err "Cannot detect OS."; fi
source /etc/os-release
if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
  err "GrimVM requires Ubuntu 22.04+ or Debian 11+. Detected: $ID"
fi
log "OS check passed: $PRETTY_NAME"

# ── Root check ───────────────────────────────────────────────
[[ $EUID -ne 0 ]] && err "Run as root: sudo bash install.sh"

# ── Gather input ─────────────────────────────────────────────
echo -e "${BOLD}Configuration${RESET}"
read -rp " Domain (e.g. panel.yourdomain.com): " DOMAIN
read -rp " Admin email (for SSL cert): "         ADMIN_EMAIL
read -rp " MySQL root password:                 " -s MYSQL_ROOT_PASS; echo
read -rp " GrimVM DB password:                  " -s DB_PASS; echo
read -rp " Admin username:                      " ADMIN_USER
read -rp " Admin password:                      " -s ADMIN_PASS; echo
read -rp " Admin email:                         " ADMIN_EMAIL_ACCT

APP_DIR="/var/www/grimvm"
DB_NAME="grimvm"
DB_USER="grimvm_user"

log "Starting installation..."

# ── System update ────────────────────────────────────────────
log "Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq

# ── Install dependencies ──────────────────────────────────────
log "Installing dependencies..."
apt-get install -y -qq \
  curl wget git unzip tar \
  nginx \
  mysql-server \
  certbot python3-certbot-nginx \
  nodejs npm \
  docker.io docker-compose \
  ufw fail2ban \
  redis-server \
  php8.2 php8.2-fpm php8.2-mysql php8.2-mbstring \
  php8.2-xml php8.2-curl php8.2-zip php8.2-bcmath \
  php8.2-gd php8.2-redis php8.2-cli \
  composer

# ── Enable services ───────────────────────────────────────────
log "Enabling system services..."
systemctl enable --now nginx mysql docker redis-server php8.2-fpm

# ── Firewall ──────────────────────────────────────────────────
log "Configuring UFW firewall..."
ufw --force enable
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 2222/tcp   # tmate SSH relay
ufw reload

# ── MySQL setup ───────────────────────────────────────────────
log "Configuring MySQL..."
mysql -u root <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASS}';
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# ── SSL Certificate ───────────────────────────────────────────
log "Obtaining SSL certificate for ${DOMAIN}..."
# Temporary nginx config for certbot
cat > /etc/nginx/sites-available/grimvm-temp <<NGINX
server {
    listen 80;
    server_name ${DOMAIN};
    root /var/www/html;
    location / { try_files \$uri \$uri/ =404; }
}
NGINX
ln -sf /etc/nginx/sites-available/grimvm-temp /etc/nginx/sites-enabled/grimvm-temp
nginx -t && systemctl reload nginx
certbot certonly --nginx -d "${DOMAIN}" --email "${ADMIN_EMAIL}" --agree-tos --non-interactive
rm /etc/nginx/sites-enabled/grimvm-temp

# ── Application directory ─────────────────────────────────────
log "Creating application structure..."
mkdir -p "${APP_DIR}"/{public,app,config,storage,routes,resources,database,scripts,docker}
mkdir -p "${APP_DIR}"/storage/{logs,sessions,cache,backups}
mkdir -p "${APP_DIR}"/public/{css,js,img,fonts}
mkdir -p "${APP_DIR}"/resources/{views,lang}
mkdir -p "${APP_DIR}"/app/{Controllers,Models,Middleware,Services}

# ── Write all application files ───────────────────────────────
log "Writing application files..."

# ── .env ─────────────────────────────────────────────────────
cat > "${APP_DIR}/.env" <<ENV
APP_NAME=GrimVM
APP_ENV=production
APP_URL=https://${DOMAIN}
APP_SECRET=$(openssl rand -hex 32)

DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=${DB_NAME}
DB_USERNAME=${DB_USER}
DB_PASSWORD=${DB_PASS}

REDIS_HOST=127.0.0.1
REDIS_PORT=6379

SESSION_DRIVER=redis
CACHE_DRIVER=redis

ADMIN_EMAIL=${ADMIN_EMAIL_ACCT}
ADMIN_USER=${ADMIN_USER}

MAIL_MAILER=smtp
MAIL_FROM_ADDRESS=noreply@${DOMAIN}

DOCKER_SOCKET=/var/run/docker.sock
TMATE_SERVER=ssh.tmate.io

# Limits
MAX_VPS_PER_NODE=50
VPS_DELETE_DAILY_LIMIT=20
ENV

# ── composer.json ────────────────────────────────────────────
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
    "ext-redis": "*",
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
-- GrimVM Schema
-- Copyright Reserved 2026 ArizNodes Team

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
  `id`           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `uuid`         CHAR(36) UNIQUE NOT NULL,
  `name`         VARCHAR(128) NOT NULL,
  `owner_id`     BIGINT UNSIGNED NOT NULL,
  `node_id`      BIGINT UNSIGNED NOT NULL,
  `container_id` VARCHAR(128),
  `image`        VARCHAR(255) NOT NULL,
  `memory_mb`    INT NOT NULL,
  `disk_gb`      INT NOT NULL,
  `cpu_cores`    INT NOT NULL,
  `status`       ENUM('running','stopped','suspended','deleted') DEFAULT 'stopped',
  `tmate_session` VARCHAR(255),
  `sftp_port`    INT,
  `console_port` INT,
  `created_at`   DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`owner_id`) REFERENCES `users`(`id`),
  FOREIGN KEY (`node_id`)  REFERENCES `nodes`(`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `eggs` (
  `id`          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `name`        VARCHAR(128) NOT NULL,
  `docker_image` VARCHAR(255) NOT NULL,
  `startup_cmd` TEXT,
  `env_vars`    JSON,
  `description` TEXT,
  `author`      VARCHAR(128),
  `active`      TINYINT DEFAULT 1,
  `created_at`  DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mounts` (
  `id`          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `name`        VARCHAR(128) NOT NULL,
  `source`      VARCHAR(512) NOT NULL,
  `target`      VARCHAR(512) NOT NULL,
  `read_only`   TINYINT DEFAULT 0,
  `created_at`  DATETIME DEFAULT CURRENT_TIMESTAMP
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
mysql -u root -p"${MYSQL_ROOT_PASS}" "${DB_NAME}" < "${APP_DIR}/database/schema.sql"
log "Schema loaded."

# ── public/index.php — entry point ────────────────────────────
cat > "${APP_DIR}/public/index.php" <<'PHP'
<?php
declare(strict_types=1);

define('GRIMVM_ROOT', dirname(__DIR__));
define('GRIMVM_VERSION', '1.0.0');
define('GRIMVM_AUTHOR', 'Vasplayz90 • ArizNodes Team');

require GRIMVM_ROOT . '/vendor/autoload.php';

use DI\ContainerBuilder;
use Slim\Factory\AppFactory;
use GrimVM\Middleware\SessionMiddleware;
use GrimVM\Middleware\AuthMiddleware;
use GrimVM\Middleware\RateLimitMiddleware;

// Load env
$dotenv = Dotenv\Dotenv::createImmutable(GRIMVM_ROOT);
$dotenv->load();

// Container
$builder = new ContainerBuilder();
$builder->addDefinitions(GRIMVM_ROOT . '/config/container.php');
$container = $builder->build();

// App
AppFactory::setContainer($container);
$app = AppFactory::create();

$app->addErrorMiddleware(
    $_ENV['APP_ENV'] !== 'production',
    true,
    true
);

$app->add(new RateLimitMiddleware($container->get('redis')));
$app->add(new SessionMiddleware());

// Routes
require GRIMVM_ROOT . '/routes/web.php';
require GRIMVM_ROOT . '/routes/api.php';
require GRIMVM_ROOT . '/routes/admin.php';

$app->run();
PHP

# ── config/container.php ──────────────────────────────────────
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
    'db' => function() {
        return new DatabaseService(
            $_ENV['DB_HOST'],
            $_ENV['DB_DATABASE'],
            $_ENV['DB_USERNAME'],
            $_ENV['DB_PASSWORD']
        );
    },
    'docker' => function() {
        return new DockerService($_ENV['DOCKER_SOCKET']);
    },
    'tmate' => function() {
        return new TmateService($_ENV['TMATE_SERVER']);
    },
    'rank' => function($c) {
        return new RankService($c->get('db'));
    },
    'audit' => function($c) {
        return new AuditService($c->get('db'));
    },
    'redis' => function() {
        $r = new Redis();
        $r->connect($_ENV['REDIS_HOST'], (int)$_ENV['REDIS_PORT']);
        return $r;
    },
    'logger' => function() {
        $log = new Logger('grimvm');
        $log->pushHandler(new StreamHandler(GRIMVM_ROOT . '/storage/logs/app.log', Logger::DEBUG));
        return $log;
    },
];
PHP

# ── app/Services/DatabaseService.php ─────────────────────────
cat > "${APP_DIR}/app/Services/DatabaseService.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Services;

class DatabaseService
{
    private \PDO $pdo;

    public function __construct(string $host, string $db, string $user, string $pass)
    {
        $dsn = "mysql:host={$host};dbname={$db};charset=utf8mb4";
        $this->pdo = new \PDO($dsn, $user, $pass, [
            \PDO::ATTR_ERRMODE            => \PDO::ERRMODE_EXCEPTION,
            \PDO::ATTR_DEFAULT_FETCH_MODE => \PDO::FETCH_ASSOC,
            \PDO::ATTR_EMULATE_PREPARES   => false,
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
        return $this->query($sql, $params)->fetch() ?: null;
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

    public function getPdo(): \PDO { return $this->pdo; }
}
PHP

# ── app/Services/DockerService.php ───────────────────────────
cat > "${APP_DIR}/app/Services/DockerService.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Services;

class DockerService
{
    private string $socket;
    private string $apiBase = 'http://localhost/v1.43';

    public function __construct(string $socket)
    {
        $this->socket = $socket;
    }

    private function request(string $method, string $path, array $body = []): array
    {
        $ch = curl_init();
        $url = $this->apiBase . $path;

        curl_setopt_array($ch, [
            CURLOPT_UNIX_SOCKET_PATH => $this->socket,
            CURLOPT_URL              => $url,
            CURLOPT_RETURNTRANSFER   => true,
            CURLOPT_HTTPHEADER       => ['Content-Type: application/json'],
        ]);

        if ($method === 'POST') {
            curl_setopt($ch, CURLOPT_POST, true);
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body));
        } elseif ($method === 'DELETE') {
            curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'DELETE');
        }

        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($response === false) {
            throw new \RuntimeException('Docker socket request failed');
        }

        return ['code' => $httpCode, 'body' => json_decode($response, true) ?? []];
    }

    public function createContainer(array $config): string
    {
        $payload = [
            'Image'        => $config['image'],
            'Hostname'     => $config['name'],
            'Memory'       => $config['memory_mb'] * 1024 * 1024,
            'NanoCpus'     => $config['cpu_cores'] * 1_000_000_000,
            'Env'          => $config['env'] ?? [],
            'Cmd'          => $config['cmd'] ?? [],
            'AttachStdin'  => true,
            'AttachStdout' => true,
            'AttachStderr' => true,
            'OpenStdin'    => true,
            'Tty'          => true,
            'HostConfig'   => [
                'Memory'       => $config['memory_mb'] * 1024 * 1024,
                'NanoCpus'     => $config['cpu_cores'] * 1_000_000_000,
                'DiskQuota'    => $config['disk_gb'] * 1024 * 1024 * 1024,
                'RestartPolicy' => ['Name' => 'unless-stopped'],
                'Binds'        => $config['mounts'] ?? [],
                'PublishAllPorts' => true,
            ],
            'Labels' => [
                'grimvm.managed'  => 'true',
                'grimvm.uuid'     => $config['uuid'],
                'grimvm.owner'    => (string)$config['owner_id'],
            ],
        ];

        $result = $this->request('POST', '/containers/create?name=grimvm_' . $config['uuid'], $payload);

        if ($result['code'] !== 201) {
            throw new \RuntimeException('Failed to create container: ' . json_encode($result['body']));
        }

        return $result['body']['Id'];
    }

    public function startContainer(string $id): bool
    {
        $result = $this->request('POST', "/containers/{$id}/start");
        return in_array($result['code'], [204, 304]);
    }

    public function stopContainer(string $id): bool
    {
        $result = $this->request('POST', "/containers/{$id}/stop");
        return in_array($result['code'], [204, 304]);
    }

    public function deleteContainer(string $id, bool $force = true): bool
    {
        $qs = $force ? '?force=true' : '';
        $result = $this->request('DELETE', "/containers/{$id}{$qs}");
        return $result['code'] === 204;
    }

    public function getContainerStats(string $id): array
    {
        $result = $this->request('GET', "/containers/{$id}/stats?stream=false");
        return $result['body'];
    }

    public function listContainers(bool $all = false): array
    {
        $qs = $all ? '?all=true&filters=' . urlencode(json_encode(['label' => ['grimvm.managed=true']])) : '';
        $result = $this->request('GET', "/containers/json{$qs}");
        return $result['body'];
    }

    public function execCommand(string $id, array $cmd): array
    {
        $execCreate = $this->request('POST', "/containers/{$id}/exec", [
            'AttachStdout' => true,
            'AttachStderr' => true,
            'Cmd'          => $cmd,
        ]);
        $execId = $execCreate['body']['Id'];
        return $this->request('POST', "/exec/{$execId}/start", ['Detach' => false, 'Tty' => false]);
    }
}
PHP

# ── app/Services/TmateService.php ────────────────────────────
cat > "${APP_DIR}/app/Services/TmateService.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Services;

class TmateService
{
    private string $tmateServer;

    public function __construct(string $tmateServer)
    {
        $this->tmateServer = $tmateServer;
    }

    public function createSession(string $containerId, string $vpsUuid): array
    {
        // Installs tmate inside container and starts session
        // Returns SSH and web session URLs
        $sessionName = 'grimvm-' . substr($vpsUuid, 0, 8);

        $script = implode(' && ', [
            'apt-get update -qq',
            'apt-get install -y -qq tmate',
            "tmate -S /tmp/{$sessionName}.sock new-session -d -s {$sessionName}",
            "tmate -S /tmp/{$sessionName}.sock wait tmate-ready",
            "tmate -S /tmp/{$sessionName}.sock display -p '#{tmate_ssh}' > /tmp/{$sessionName}_ssh.txt",
            "tmate -S /tmp/{$sessionName}.sock display -p '#{tmate_web}' > /tmp/{$sessionName}_web.txt",
        ]);

        // Execute inside Docker container
        $dockerCmd = "docker exec {$containerId} bash -c " . escapeshellarg($script);
        exec($dockerCmd, $output, $code);

        $sshSession = trim(shell_exec("docker exec {$containerId} cat /tmp/{$sessionName}_ssh.txt") ?? '');
        $webSession = trim(shell_exec("docker exec {$containerId} cat /tmp/{$sessionName}_web.txt") ?? '');

        return [
            'ssh' => $sshSession,
            'web' => $webSession,
            'session_name' => $sessionName,
        ];
    }

    public function killSession(string $containerId, string $vpsUuid): bool
    {
        $sessionName = 'grimvm-' . substr($vpsUuid, 0, 8);
        $cmd = "docker exec {$containerId} tmate -S /tmp/{$sessionName}.sock kill-session 2>/dev/null";
        exec($cmd, $output, $code);
        return $code === 0;
    }
}
PHP

# ── app/Services/RankService.php ─────────────────────────────
cat > "${APP_DIR}/app/Services/RankService.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Services;

class RankService
{
    private DatabaseService $db;

    // Rank thresholds
    private const RANKS = [
        'Newbie'   => 0,
        'Pro'      => 2,
        'Ultimate' => 4,
    ];

    public function __construct(DatabaseService $db)
    {
        $this->db = $db;
    }

    public function recalculate(int $userId): string
    {
        $user = $this->db->fetch('SELECT vps_count FROM users WHERE id = ?', [$userId]);
        if (!$user) return 'Newbie';

        $count = (int)$user['vps_count'];
        $newRank = 'Newbie';

        foreach (self::RANKS as $rank => $threshold) {
            if ($count >= $threshold) {
                $newRank = $rank;
            }
        }

        $this->db->execute(
            'UPDATE users SET rank = ? WHERE id = ?',
            [$newRank, $userId]
        );

        return $newRank;
    }

    public function getRankThresholds(): array
    {
        return self::RANKS;
    }

    public function claimReward(int $userId, string $code): array
    {
        $user   = $this->db->fetch('SELECT rank FROM users WHERE id = ?', [$userId]);
        $reward = $this->db->fetch('SELECT * FROM rewards WHERE code = ? AND claimed_by IS NULL', [$code]);

        if (!$reward) {
            return ['success' => false, 'message' => 'Invalid or already claimed code.'];
        }

        if ($user['rank'] !== $reward['rank_req'] && $user['rank'] !== 'Ultimate') {
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

# ── app/Services/AuditService.php ────────────────────────────
cat > "${APP_DIR}/app/Services/AuditService.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Services;

class AuditService
{
    private DatabaseService $db;
    private const DELETE_LIMIT = 20;

    public function __construct(DatabaseService $db)
    {
        $this->db = $db;
    }

    public function log(int $userId, string $action, string $target = '', string $ip = ''): void
    {
        $this->db->execute(
            'INSERT INTO audit_log (user_id, action, target, ip) VALUES (?, ?, ?, ?)',
            [$userId, $action, $target, $ip]
        );
    }

    /**
     * Check if admin exceeded daily delete limit.
     * Auto-bans if over threshold.
     */
    public function checkDeleteLimit(int $adminId): array
    {
        $today = date('Y-m-d');
        $count = (int)$this->db->fetch(
            'SELECT COUNT(*) as c FROM delete_log WHERE admin_id = ? AND DATE(deleted_at) = ?',
            [$adminId, $today]
        )['c'];

        if ($count >= self::DELETE_LIMIT) {
            // Auto-ban the admin
            $this->db->execute(
                'UPDATE users SET banned = 1, ban_reason = ? WHERE id = ?',
                ['Automated: Exceeded daily VPS deletion limit (' . self::DELETE_LIMIT . ')', $adminId]
            );
            return ['allowed' => false, 'reason' => 'Daily deletion limit exceeded. Account suspended.'];
        }

        return ['allowed' => true, 'count' => $count, 'limit' => self::DELETE_LIMIT];
    }

    public function logDelete(int $adminId, string $vpsUuid): void
    {
        $this->db->execute(
            'INSERT INTO delete_log (admin_id, vps_uuid) VALUES (?, ?)',
            [$adminId, $vpsUuid]
        );
    }

    public function getAuditLog(int $limit = 100): array
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

# ── app/Models/User.php ───────────────────────────────────────
cat > "${APP_DIR}/app/Models/User.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Models;

use GrimVM\Services\DatabaseService;

class User
{
    private DatabaseService $db;

    public function __construct(DatabaseService $db)
    {
        $this->db = $db;
    }

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
            'INSERT INTO users (username, email, password, role) VALUES (?, ?, ?, ?)',
            [
                $data['username'],
                $data['email'],
                password_hash($data['password'], PASSWORD_BCRYPT, ['cost' => 12]),
                $data['role'] ?? 'member',
            ]
        );
    }

    public function ban(int $id, string $reason, string $ip = ''): void
    {
        $this->db->execute(
            'UPDATE users SET banned = 1, ban_reason = ?, ban_ip = ? WHERE id = ?',
            [$reason, $ip, $id]
        );
    }

    public function unban(int $id): void
    {
        $this->db->execute(
            'UPDATE users SET banned = 0, ban_reason = NULL, ban_ip = NULL WHERE id = ?',
            [$id]
        );
    }

    public function mute(int $id, int $minutes): void
    {
        $until = date('Y-m-d H:i:s', strtotime("+{$minutes} minutes"));
        $this->db->execute(
            'UPDATE users SET muted_until = ? WHERE id = ?',
            [$until, $id]
        );
    }

    public function generateToken(int $id): string
    {
        $token = bin2hex(random_bytes(32));
        $this->db->execute('UPDATE users SET api_token = ? WHERE id = ?', [$token, $id]);
        return $token;
    }

    public function all(): array
    {
        return $this->db->fetchAll('SELECT id,username,email,role,rank,vps_count,banned,created_at FROM users ORDER BY created_at DESC');
    }
}
PHP

# ── app/Models/VPS.php ───────────────────────────────────────
cat > "${APP_DIR}/app/Models/VPS.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Models;

use GrimVM\Services\DatabaseService;

class VPS
{
    private DatabaseService $db;

    public function __construct(DatabaseService $db)
    {
        $this->db = $db;
    }

    public function find(string $uuid): ?array
    {
        return $this->db->fetch('SELECT * FROM vps WHERE uuid = ?', [$uuid]);
    }

    public function findById(int $id): ?array
    {
        return $this->db->fetch('SELECT * FROM vps WHERE id = ?', [$id]);
    }

    public function forUser(int $userId): array
    {
        return $this->db->fetchAll(
            'SELECT v.*, n.name as node_name, n.location FROM vps v 
             JOIN nodes n ON n.id = v.node_id 
             WHERE v.owner_id = ? AND v.status != "deleted" ORDER BY v.created_at DESC',
            [$userId]
        );
    }

    public function all(): array
    {
        return $this->db->fetchAll(
            'SELECT v.*, u.username, n.name as node_name 
             FROM vps v 
             JOIN users u ON u.id = v.owner_id 
             JOIN nodes n ON n.id = v.node_id 
             WHERE v.status != "deleted" ORDER BY v.created_at DESC'
        );
    }

    public function create(array $data): string
    {
        $uuid = sprintf('%04x%04x-%04x-%04x-%04x-%04x%04x%04x',
            mt_rand(0, 0xffff), mt_rand(0, 0xffff),
            mt_rand(0, 0xffff),
            mt_rand(0, 0x0fff) | 0x4000,
            mt_rand(0, 0x3fff) | 0x8000,
            mt_rand(0, 0xffff), mt_rand(0, 0xffff), mt_rand(0, 0xffff)
        );

        $this->db->insert(
            'INSERT INTO vps (uuid,name,owner_id,node_id,image,memory_mb,disk_gb,cpu_cores) 
             VALUES (?,?,?,?,?,?,?,?)',
            [
                $uuid,
                $data['name'],
                $data['owner_id'],
                $data['node_id'],
                $data['image'],
                $data['memory_mb'],
                $data['disk_gb'],
                $data['cpu_cores'],
            ]
        );

        return $uuid;
    }

    public function updateStatus(string $uuid, string $status): void
    {
        $this->db->execute('UPDATE vps SET status = ? WHERE uuid = ?', [$status, $uuid]);
    }

    public function updateContainer(string $uuid, string $containerId, ?string $tmate = null): void
    {
        $this->db->execute(
            'UPDATE vps SET container_id = ?, tmate_session = ? WHERE uuid = ?',
            [$containerId, $tmate, $uuid]
        );
    }
}
PHP

# ── app/Controllers/AuthController.php ───────────────────────
cat > "${APP_DIR}/app/Controllers/AuthController.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Controllers;

use GrimVM\Models\User;
use GrimVM\Services\AuditService;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;
use Firebase\JWT\JWT;
use Firebase\JWT\Key;

class AuthController
{
    public function __construct(
        private User $userModel,
        private AuditService $audit
    ) {}

    public function login(Request $req, Response $res): Response
    {
        $body  = (array)$req->getParsedBody();
        $email = trim($body['email'] ?? '');
        $pass  = $body['password'] ?? '';

        $user = $this->userModel->findByEmail($email);

        if (!$user || !password_verify($pass, $user['password'])) {
            return $this->json($res, ['error' => 'Invalid credentials'], 401);
        }

        if ($user['banned']) {
            return $this->json($res, ['error' => 'Account suspended: ' . $user['ban_reason']], 403);
        }

        $token = JWT::encode([
            'sub'  => $user['id'],
            'role' => $user['role'],
            'rank' => $user['rank'],
            'iat'  => time(),
            'exp'  => time() + 86400 * 7, // 7 days
        ], $_ENV['APP_SECRET'], 'HS256');

        $this->audit->log($user['id'], 'login', '', $req->getServerParams()['REMOTE_ADDR'] ?? '');

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

    public function register(Request $req, Response $res): Response
    {
        $body = (array)$req->getParsedBody();

        $username = trim($body['username'] ?? '');
        $email    = trim($body['email'] ?? '');
        $pass     = $body['password'] ?? '';

        if (!$username || !$email || !$pass) {
            return $this->json($res, ['error' => 'All fields required'], 400);
        }

        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            return $this->json($res, ['error' => 'Invalid email'], 400);
        }

        if (strlen($pass) < 8) {
            return $this->json($res, ['error' => 'Password too short (min 8)'], 400);
        }

        try {
            $id = $this->userModel->create([
                'username' => $username,
                'email'    => $email,
                'password' => $pass,
            ]);
        } catch (\PDOException $e) {
            return $this->json($res, ['error' => 'Username or email already exists'], 409);
        }

        return $this->json($res, ['message' => 'Account created', 'id' => $id], 201);
    }

    private function json(Response $res, array $data, int $code = 200): Response
    {
        $res->getBody()->write(json_encode($data));
        return $res->withHeader('Content-Type', 'application/json')->withStatus($code);
    }
}
PHP

# ── app/Controllers/VPSController.php ────────────────────────
cat > "${APP_DIR}/app/Controllers/VPSController.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Controllers;

use GrimVM\Models\VPS;
use GrimVM\Models\User;
use GrimVM\Services\DockerService;
use GrimVM\Services\TmateService;
use GrimVM\Services\RankService;
use GrimVM\Services\AuditService;
use GrimVM\Services\DatabaseService;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

class VPSController
{
    public function __construct(
        private VPS            $vpsModel,
        private User           $userModel,
        private DockerService  $docker,
        private TmateService   $tmate,
        private RankService    $rank,
        private AuditService   $audit,
        private DatabaseService $db
    ) {}

    /** Admin only — create a VPS and assign to user */
    public function create(Request $req, Response $res): Response
    {
        $admin = $req->getAttribute('auth_user');
        if (!in_array($admin['role'], ['admin', 'owner'])) {
            return $this->json($res, ['error' => 'Forbidden'], 403);
        }

        $body = (array)$req->getParsedBody();
        $required = ['name', 'owner_id', 'node_id', 'image', 'memory_mb', 'disk_gb', 'cpu_cores'];
        foreach ($required as $f) {
            if (empty($body[$f])) {
                return $this->json($res, ['error' => "Missing field: {$f}"], 400);
            }
        }

        // Assign owner
        $owner = $this->userModel->find((int)$body['owner_id']);
        if (!$owner) {
            return $this->json($res, ['error' => 'Owner not found'], 404);
        }

        // Create VPS record
        $uuid = $this->vpsModel->create([
            'name'       => $body['name'],
            'owner_id'   => (int)$body['owner_id'],
            'node_id'    => (int)$body['node_id'],
            'image'      => $body['image'],
            'memory_mb'  => (int)$body['memory_mb'],
            'disk_gb'    => (int)$body['disk_gb'],
            'cpu_cores'  => (int)$body['cpu_cores'],
        ]);

        // Create Docker container
        $containerId = $this->docker->createContainer([
            'uuid'       => $uuid,
            'name'       => 'grimvm_' . $uuid,
            'image'      => $body['image'],
            'memory_mb'  => (int)$body['memory_mb'],
            'disk_gb'    => (int)$body['disk_gb'],
            'cpu_cores'  => (int)$body['cpu_cores'],
            'owner_id'   => (int)$body['owner_id'],
            'mounts'     => $body['mounts'] ?? [],
            'env'        => $body['env'] ?? [],
        ]);

        $this->docker->startContainer($containerId);

        // Create tmate session
        $tmateSession = $this->tmate->createSession($containerId, $uuid);

        $this->vpsModel->updateContainer($uuid, $containerId, $tmateSession['ssh']);
        $this->vpsModel->updateStatus($uuid, 'running');

        // Update owner VPS count + rank
        $this->db->execute(
            'UPDATE users SET vps_count = vps_count + 1 WHERE id = ?',
            [(int)$body['owner_id']]
        );
        $newRank = $this->rank->recalculate((int)$body['owner_id']);

        $this->audit->log($admin['id'], 'vps_create', $uuid, $req->getServerParams()['REMOTE_ADDR'] ?? '');

        return $this->json($res, [
            'uuid'          => $uuid,
            'container_id'  => $containerId,
            'tmate_ssh'     => $tmateSession['ssh'],
            'tmate_web'     => $tmateSession['web'],
            'owner_new_rank' => $newRank,
        ], 201);
    }

    /** Admin only — delete a VPS with daily limit enforcement */
    public function delete(Request $req, Response $res, array $args): Response
    {
        $admin = $req->getAttribute('auth_user');
        if (!in_array($admin['role'], ['admin', 'owner'])) {
            return $this->json($res, ['error' => 'Forbidden'], 403);
        }

        $limit = $this->audit->checkDeleteLimit($admin['id']);
        if (!$limit['allowed']) {
            return $this->json($res, ['error' => $limit['reason']], 429);
        }

        $vps = $this->vpsModel->find($args['uuid']);
        if (!$vps) {
            return $this->json($res, ['error' => 'VPS not found'], 404);
        }

        if ($vps['container_id']) {
            $this->tmate->killSession($vps['container_id'], $vps['uuid']);
            $this->docker->stopContainer($vps['container_id']);
            $this->docker->deleteContainer($vps['container_id']);
        }

        $this->vpsModel->updateStatus($vps['uuid'], 'deleted');

        // Decrement owner count and recalc rank
        $this->db->execute(
            'UPDATE users SET vps_count = GREATEST(vps_count - 1, 0) WHERE id = ?',
            [$vps['owner_id']]
        );
        $this->rank->recalculate((int)$vps['owner_id']);

        $this->audit->logDelete($admin['id'], $vps['uuid']);
        $this->audit->log($admin['id'], 'vps_delete', $vps['uuid'], $req->getServerParams()['REMOTE_ADDR'] ?? '');

        return $this->json($res, ['message' => 'VPS deleted', 'uuid' => $vps['uuid']]);
    }

    /** Power controls — start / stop / restart */
    public function power(Request $req, Response $res, array $args): Response
    {
        $user   = $req->getAttribute('auth_user');
        $action = $args['action'];
        $vps    = $this->vpsModel->find($args['uuid']);

        if (!$vps) {
            return $this->json($res, ['error' => 'VPS not found'], 404);
        }

        // Owner or admin can control power
        if ($vps['owner_id'] !== $user['id'] && !in_array($user['role'], ['admin', 'owner'])) {
            return $this->json($res, ['error' => 'Forbidden'], 403);
        }

        switch ($action) {
            case 'start':
                $this->docker->startContainer($vps['container_id']);
                $this->vpsModel->updateStatus($vps['uuid'], 'running');
                break;
            case 'stop':
                $this->docker->stopContainer($vps['container_id']);
                $this->vpsModel->updateStatus($vps['uuid'], 'stopped');
                break;
            case 'restart':
                $this->docker->stopContainer($vps['container_id']);
                $this->docker->startContainer($vps['container_id']);
                $this->vpsModel->updateStatus($vps['uuid'], 'running');
                break;
            default:
                return $this->json($res, ['error' => 'Invalid action'], 400);
        }

        $this->audit->log($user['id'], "vps_{$action}", $vps['uuid'], $req->getServerParams()['REMOTE_ADDR'] ?? '');

        return $this->json($res, ['message' => "VPS {$action} successful"]);
    }

    /** Get all VPS for the authenticated user */
    public function list(Request $req, Response $res): Response
    {
        $user = $req->getAttribute('auth_user');
        $list = $this->vpsModel->forUser($user['id']);
        return $this->json($res, ['vps' => $list]);
    }

    /** Admin: get all VPS */
    public function adminList(Request $req, Response $res): Response
    {
        $admin = $req->getAttribute('auth_user');
        if (!in_array($admin['role'], ['admin', 'owner'])) {
            return $this->json($res, ['error' => 'Forbidden'], 403);
        }
        return $this->json($res, ['vps' => $this->vpsModel->all()]);
    }

    private function json(Response $res, array $data, int $code = 200): Response
    {
        $res->getBody()->write(json_encode($data));
        return $res->withHeader('Content-Type', 'application/json')->withStatus($code);
    }
}
PHP

# ── app/Controllers/AdminController.php ──────────────────────
cat > "${APP_DIR}/app/Controllers/AdminController.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Controllers;

use GrimVM\Models\User;
use GrimVM\Services\AuditService;
use GrimVM\Services\DatabaseService;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

class AdminController
{
    public function __construct(
        private User $userModel,
        private AuditService $audit,
        private DatabaseService $db
    ) {}

    public function banUser(Request $req, Response $res, array $args): Response
    {
        $admin  = $req->getAttribute('auth_user');
        $body   = (array)$req->getParsedBody();
        $reason = $body['reason'] ?? 'No reason given';
        $ip     = $body['ip'] ?? '';

        $this->userModel->ban((int)$args['id'], $reason, $ip);
        $this->audit->log($admin['id'], 'ban_user', $args['id'], $req->getServerParams()['REMOTE_ADDR'] ?? '');

        return $this->json($res, ['message' => 'User banned']);
    }

    public function unbanUser(Request $req, Response $res, array $args): Response
    {
        $admin = $req->getAttribute('auth_user');
        $this->userModel->unban((int)$args['id']);
        $this->audit->log($admin['id'], 'unban_user', $args['id'], $req->getServerParams()['REMOTE_ADDR'] ?? '');
        return $this->json($res, ['message' => 'User unbanned']);
    }

    public function muteUser(Request $req, Response $res, array $args): Response
    {
        $admin   = $req->getAttribute('auth_user');
        $body    = (array)$req->getParsedBody();
        $minutes = (int)($body['minutes'] ?? 60);

        $this->userModel->mute((int)$args['id'], $minutes);
        $this->audit->log($admin['id'], 'mute_user', $args['id'], $req->getServerParams()['REMOTE_ADDR'] ?? '');

        return $this->json($res, ['message' => "User muted for {$minutes} minutes"]);
    }

    public function listUsers(Request $req, Response $res): Response
    {
        return $this->json($res, ['users' => $this->userModel->all()]);
    }

    public function getSettings(Request $req, Response $res): Response
    {
        $rows = $this->db->fetchAll('SELECT * FROM settings');
        $settings = array_column($rows, 'value', 'key');
        return $this->json($res, ['settings' => $settings]);
    }

    public function updateSetting(Request $req, Response $res, array $args): Response
    {
        $admin = $req->getAttribute('auth_user');
        $body  = (array)$req->getParsedBody();
        $value = $body['value'] ?? '';

        $this->db->execute(
            'INSERT INTO settings (`key`, `value`) VALUES (?,?) ON DUPLICATE KEY UPDATE `value` = ?',
            [$args['key'], $value, $value]
        );
        $this->audit->log($admin['id'], 'setting_update', $args['key']);

        return $this->json($res, ['message' => 'Setting updated']);
    }

    public function getAuditLog(Request $req, Response $res): Response
    {
        return $this->json($res, ['log' => $this->audit->getAuditLog(200)]);
    }

    // Node management
    public function createNode(Request $req, Response $res): Response
    {
        $admin = $req->getAttribute('auth_user');
        $body  = (array)$req->getParsedBody();

        $id = $this->db->insert(
            'INSERT INTO nodes (name, location, ip, port, memory_mb, disk_gb, cpu_cores) VALUES (?,?,?,?,?,?,?)',
            [
                $body['name'],
                $body['location'],
                $body['ip'],
                (int)($body['port'] ?? 2222),
                (int)$body['memory_mb'],
                (int)$body['disk_gb'],
                (int)$body['cpu_cores'],
            ]
        );

        $this->audit->log($admin['id'], 'node_create', (string)$id);
        return $this->json($res, ['message' => 'Node created', 'id' => $id], 201);
    }

    public function listNodes(Request $req, Response $res): Response
    {
        $nodes = $this->db->fetchAll('SELECT * FROM nodes ORDER BY created_at DESC');
        return $this->json($res, ['nodes' => $nodes]);
    }

    private function json(Response $res, array $data, int $code = 200): Response
    {
        $res->getBody()->write(json_encode($data));
        return $res->withHeader('Content-Type', 'application/json')->withStatus($code);
    }
}
PHP

# ── app/Middleware/AuthMiddleware.php ─────────────────────────
cat > "${APP_DIR}/app/Middleware/AuthMiddleware.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Middleware;

use Firebase\JWT\JWT;
use Firebase\JWT\Key;
use Firebase\JWT\ExpiredException;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use Slim\Psr7\Response;

class AuthMiddleware implements MiddlewareInterface
{
    private string $requiredRole;

    public function __construct(string $requiredRole = 'member')
    {
        $this->requiredRole = $requiredRole;
    }

    public function process(ServerRequestInterface $req, RequestHandlerInterface $handler): ResponseInterface
    {
        $authHeader = $req->getHeaderLine('Authorization');

        if (!str_starts_with($authHeader, 'Bearer ')) {
            return $this->unauthorized('Missing token');
        }

        $token = substr($authHeader, 7);

        try {
            $decoded = JWT::decode($token, new Key($_ENV['APP_SECRET'], 'HS256'));
        } catch (ExpiredException) {
            return $this->unauthorized('Token expired');
        } catch (\Throwable) {
            return $this->unauthorized('Invalid token');
        }

        $roleHierarchy = ['member' => 0, 'admin' => 1, 'owner' => 2];
        $userLevel     = $roleHierarchy[$decoded->role] ?? 0;
        $requiredLevel = $roleHierarchy[$this->requiredRole] ?? 0;

        if ($userLevel < $requiredLevel) {
            return $this->forbidden('Insufficient permissions');
        }

        $req = $req->withAttribute('auth_user', [
            'id'   => $decoded->sub,
            'role' => $decoded->role,
            'rank' => $decoded->rank,
        ]);

        return $handler->handle($req);
    }

    private function unauthorized(string $msg): ResponseInterface
    {
        $res = new Response(401);
        $res->getBody()->write(json_encode(['error' => $msg]));
        return $res->withHeader('Content-Type', 'application/json');
    }

    private function forbidden(string $msg): ResponseInterface
    {
        $res = new Response(403);
        $res->getBody()->write(json_encode(['error' => $msg]));
        return $res->withHeader('Content-Type', 'application/json');
    }
}
PHP

# ── app/Middleware/SessionMiddleware.php ──────────────────────
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
                'samesite' => 'Strict',
            ]);
            session_start();
        }
        return $handler->handle($req);
    }
}
PHP

# ── app/Middleware/RateLimitMiddleware.php ────────────────────
cat > "${APP_DIR}/app/Middleware/RateLimitMiddleware.php" <<'PHP'
<?php
declare(strict_types=1);
namespace GrimVM\Middleware;

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use Redis;
use Slim\Psr7\Response;

class RateLimitMiddleware implements MiddlewareInterface
{
    private const WINDOW = 60;     // 60 seconds
    private const LIMIT  = 120;    // 120 req / min

    public function __construct(private Redis $redis) {}

    public function process(ServerRequestInterface $req, RequestHandlerInterface $handler): ResponseInterface
    {
        $ip  = $req->getServerParams()['REMOTE_ADDR'] ?? 'unknown';
        $key = "rl:{$ip}";

        $current = $this->redis->incr($key);
        if ($current === 1) {
            $this->redis->expire($key, self::WINDOW);
        }

        if ($current > self::LIMIT) {
            $res = new Response(429);
            $res->getBody()->write(json_encode(['error' => 'Rate limit exceeded']));
            return $res
                ->withHeader('Content-Type', 'application/json')
                ->withHeader('Retry-After', (string)self::WINDOW);
        }

        return $handler->handle($req);
    }
}
PHP

# ── routes/web.php ────────────────────────────────────────────
cat > "${APP_DIR}/routes/web.php" <<'PHP'
<?php
use Slim\Routing\RouteCollectorProxy;

// Public frontend
$app->get('/', function($req, $res) {
    return $res->withHeader('Location', '/dashboard')->withStatus(302);
});

// Serve static panel views (React SPA handles routing)
$app->get('/dashboard[/{path:.*}]', function($req, $res) {
    $html = file_get_contents(GRIMVM_ROOT . '/public/index.html');
    $res->getBody()->write($html);
    return $res->withHeader('Content-Type', 'text/html');
});

$app->get('/admin[/{path:.*}]', function($req, $res) {
    $html = file_get_contents(GRIMVM_ROOT . '/public/admin.html');
    $res->getBody()->write($html);
    return $res->withHeader('Content-Type', 'text/html');
});
PHP

# ── routes/api.php ────────────────────────────────────────────
cat > "${APP_DIR}/routes/api.php" <<'PHP'
<?php
use GrimVM\Controllers\AuthController;
use GrimVM\Controllers\VPSController;
use GrimVM\Middleware\AuthMiddleware;
use Slim\Routing\RouteCollectorProxy;

// Auth routes — public
$app->group('/api/auth', function($group) {
    $group->post('/login',    [AuthController::class, 'login']);
    $group->post('/register', [AuthController::class, 'register']);
});

// Protected member routes
$app->group('/api/vps', function($group) {
    $group->get('',              [VPSController::class, 'list']);
    $group->post('/{uuid}/power/{action}', [VPSController::class, 'power']);
})->add(new AuthMiddleware('member'));

// Protected admin routes
$app->group('/api/admin/vps', function($group) {
    $group->post('',             [VPSController::class, 'create']);
    $group->get('',              [VPSController::class, 'adminList']);
    $group->delete('/{uuid}',    [VPSController::class, 'delete']);
})->add(new AuthMiddleware('admin'));
PHP

# ── routes/admin.php ──────────────────────────────────────────
cat > "${APP_DIR}/routes/admin.php" <<'PHP'
<?php
use GrimVM\Controllers\AdminController;
use GrimVM\Middleware\AuthMiddleware;

$app->group('/api/admin', function($group) {
    // Users
    $group->get('/users',             [AdminController::class, 'listUsers']);
    $group->post('/users/{id}/ban',   [AdminController::class, 'banUser']);
    $group->post('/users/{id}/unban', [AdminController::class, 'unbanUser']);
    $group->post('/users/{id}/mute',  [AdminController::class, 'muteUser']);

    // Nodes
    $group->post('/nodes',            [AdminController::class, 'createNode']);
    $group->get('/nodes',             [AdminController::class, 'listNodes']);

    // Settings
    $group->get('/settings',              [AdminController::class, 'getSettings']);
    $group->put('/settings/{key}',        [AdminController::class, 'updateSetting']);

    // Audit log
    $group->get('/audit',             [AdminController::class, 'getAuditLog']);
})->add(new AuthMiddleware('admin'));
PHP

# ── Frontend HTML (Dashboard) ─────────────────────────────────
log "Writing frontend dashboard..."
cat > "${APP_DIR}/public/index.html" <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>GrimVM — Dashboard</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap">
  <style>
    :root {
      --bg:       #0a0c10;
      --bg2:      #111420;
      --bg3:      #191c2a;
      --border:   #1e2235;
      --accent:   #6c47ff;
      --accent2:  #4f35cc;
      --green:    #22c55e;
      --red:      #ef4444;
      --yellow:   #f59e0b;
      --text:     #e2e8f0;
      --muted:    #64748b;
      --font:     'Inter', sans-serif;
      --mono:     'JetBrains Mono', monospace;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { background: var(--bg); color: var(--text); font-family: var(--font); min-height: 100vh; }

    /* Login overlay */
    #login-screen {
      position: fixed; inset: 0; z-index: 100;
      background: var(--bg);
      display: flex; align-items: center; justify-content: center;
    }
    .login-card {
      background: var(--bg2);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 40px;
      width: 380px;
    }
    .login-logo {
      font-family: var(--mono);
      font-size: 22px;
      font-weight: 700;
      color: var(--accent);
      margin-bottom: 8px;
    }
    .login-sub { color: var(--muted); font-size: 13px; margin-bottom: 28px; }
    .form-group { margin-bottom: 16px; }
    .form-group label { display: block; font-size: 12px; font-weight: 500; color: var(--muted); margin-bottom: 6px; letter-spacing: .05em; }
    .form-group input {
      width: 100%; padding: 10px 14px;
      background: var(--bg3); border: 1px solid var(--border);
      border-radius: 8px; color: var(--text);
      font-size: 14px; font-family: var(--font);
      outline: none; transition: border-color .15s;
    }
    .form-group input:focus { border-color: var(--accent); }
    .btn {
      width: 100%; padding: 11px;
      background: var(--accent); color: #fff;
      border: none; border-radius: 8px;
      font-size: 14px; font-weight: 600;
      cursor: pointer; transition: background .15s;
    }
    .btn:hover { background: var(--accent2); }
    .login-err { color: var(--red); font-size: 13px; margin-bottom: 12px; display: none; }

    /* Main app layout */
    #app { display: none; }
    .sidebar {
      position: fixed; left: 0; top: 0; bottom: 0; width: 220px;
      background: var(--bg2); border-right: 1px solid var(--border);
      display: flex; flex-direction: column; padding: 24px 0;
    }
    .sidebar-logo {
      padding: 0 20px 24px;
      font-family: var(--mono); font-size: 18px; font-weight: 700; color: var(--accent);
      border-bottom: 1px solid var(--border);
    }
    .sidebar-logo span { color: var(--muted); font-size: 11px; display: block; font-weight: 400; margin-top: 2px; }
    .nav { padding: 16px 0; flex: 1; }
    .nav-item {
      display: flex; align-items: center; gap: 10px;
      padding: 10px 20px; cursor: pointer;
      color: var(--muted); font-size: 13px; font-weight: 500;
      transition: color .15s, background .15s;
    }
    .nav-item:hover, .nav-item.active { color: var(--text); background: var(--bg3); }
    .nav-item.active { border-left: 2px solid var(--accent); }
    .sidebar-user {
      padding: 16px 20px; border-top: 1px solid var(--border);
      font-size: 12px; color: var(--muted);
    }
    .rank-badge {
      display: inline-block; padding: 2px 8px;
      border-radius: 4px; font-size: 10px; font-weight: 600;
      background: var(--accent); color: #fff; margin-top: 4px;
    }
    .rank-badge.Pro { background: #0ea5e9; }
    .rank-badge.Ultimate { background: linear-gradient(90deg, #6c47ff, #ec4899); }

    /* Main content */
    .main { margin-left: 220px; padding: 32px; min-height: 100vh; }
    .page { display: none; }
    .page.active { display: block; }
    .page-title { font-size: 22px; font-weight: 700; margin-bottom: 24px; }

    /* Stats row */
    .stats-row { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 16px; margin-bottom: 28px; }
    .stat-card {
      background: var(--bg2); border: 1px solid var(--border);
      border-radius: 10px; padding: 20px;
    }
    .stat-label { font-size: 11px; color: var(--muted); text-transform: uppercase; letter-spacing: .07em; margin-bottom: 8px; }
    .stat-value { font-size: 28px; font-weight: 700; font-family: var(--mono); }
    .stat-value.green { color: var(--green); }
    .stat-value.accent { color: var(--accent); }

    /* VPS table */
    .card {
      background: var(--bg2); border: 1px solid var(--border);
      border-radius: 10px; overflow: hidden;
    }
    .card-header {
      padding: 16px 20px; border-bottom: 1px solid var(--border);
      font-size: 14px; font-weight: 600; display: flex; align-items: center; justify-content: space-between;
    }
    table { width: 100%; border-collapse: collapse; }
    th {
      padding: 12px 20px; text-align: left;
      font-size: 11px; font-weight: 600; color: var(--muted);
      text-transform: uppercase; letter-spacing: .07em;
      border-bottom: 1px solid var(--border);
    }
    td { padding: 14px 20px; font-size: 13px; border-bottom: 1px solid var(--border); }
    tr:last-child td { border-bottom: none; }
    tr:hover td { background: var(--bg3); }

    .status-dot {
      display: inline-block; width: 8px; height: 8px;
      border-radius: 50%; margin-right: 6px;
    }
    .status-dot.running  { background: var(--green); box-shadow: 0 0 6px var(--green); }
    .status-dot.stopped  { background: var(--muted); }
    .status-dot.suspended { background: var(--yellow); }

    .action-btn {
      padding: 4px 10px; border-radius: 5px; font-size: 11px;
      font-weight: 600; cursor: pointer; border: none; margin-right: 4px;
    }
    .action-btn.start   { background: rgba(34,197,94,.15); color: var(--green); }
    .action-btn.stop    { background: rgba(239,68,68,.15);  color: var(--red); }
    .action-btn.console { background: rgba(108,71,255,.15); color: var(--accent); }

    /* Console panel */
    .console-box {
      background: #000; border: 1px solid var(--border);
      border-radius: 8px; padding: 16px;
      font-family: var(--mono); font-size: 13px; line-height: 1.6;
      color: #00ff88; min-height: 300px; overflow-y: auto;
      white-space: pre-wrap;
    }
    .tmate-info {
      background: var(--bg3); border: 1px solid var(--border);
      border-radius: 8px; padding: 14px 18px; margin-top: 16px;
      font-size: 12px; font-family: var(--mono);
    }
    .tmate-info span { color: var(--muted); }

    #toast {
      position: fixed; bottom: 24px; right: 24px;
      background: var(--bg2); border: 1px solid var(--border);
      border-radius: 8px; padding: 12px 18px;
      font-size: 13px; transform: translateY(80px);
      transition: transform .2s; z-index: 999;
    }
    #toast.show { transform: translateY(0); }
    #toast.ok   { border-color: var(--green); color: var(--green); }
    #toast.err  { border-color: var(--red); color: var(--red); }
  </style>
</head>
<body>

<!-- Login Screen -->
<div id="login-screen">
  <div class="login-card">
    <div class="login-logo">Grim<span style="color:#fff">VM</span></div>
    <div class="login-sub">Hypervisor Panel — ArizNodes Team</div>
    <div class="login-err" id="login-err"></div>
    <div class="form-group"><label>Email</label><input type="email" id="login-email" placeholder="you@example.com"></div>
    <div class="form-group"><label>Password</label><input type="password" id="login-pass" placeholder="••••••••"></div>
    <button class="btn" onclick="doLogin()">Sign In</button>
    <div style="margin-top:14px; text-align:center; font-size:12px; color:var(--muted)">
      No account? <a href="#" onclick="showRegister()" style="color:var(--accent)">Register</a>
    </div>
  </div>
</div>

<!-- Main App -->
<div id="app">
  <div class="sidebar">
    <div class="sidebar-logo">GrimVM <span>Hypervisor Panel #5</span></div>
    <nav class="nav">
      <div class="nav-item active" onclick="showPage('dashboard')">⬛ Dashboard</div>
      <div class="nav-item" onclick="showPage('servers')">🖥 My Servers</div>
      <div class="nav-item" onclick="showPage('console')">⌨ Console</div>
      <div class="nav-item" onclick="showPage('ranks')">⭐ Ranks</div>
      <div id="admin-nav" style="display:none">
        <div class="nav-item" onclick="showPage('admin')">🔐 Admin Panel</div>
      </div>
    </nav>
    <div class="sidebar-user">
      <div id="sidebar-username">—</div>
      <div class="rank-badge" id="sidebar-rank">Newbie</div>
    </div>
  </div>

  <div class="main">
    <!-- Dashboard -->
    <div class="page active" id="page-dashboard">
      <div class="page-title">Dashboard</div>
      <div class="stats-row">
        <div class="stat-card"><div class="stat-label">Your VPS</div><div class="stat-value accent" id="stat-vps">0</div></div>
        <div class="stat-card"><div class="stat-label">Running</div><div class="stat-value green" id="stat-running">0</div></div>
        <div class="stat-card"><div class="stat-label">Rank</div><div class="stat-value" id="stat-rank">Newbie</div></div>
      </div>
      <div class="card">
        <div class="card-header">Recent Servers</div>
        <table><thead><tr><th>Name</th><th>Status</th><th>Node</th><th>Location</th></tr></thead>
        <tbody id="dash-vps-list"></tbody></table>
      </div>
    </div>

    <!-- Servers -->
    <div class="page" id="page-servers">
      <div class="page-title">My Servers</div>
      <div class="card">
        <div class="card-header">
          All Servers
          <span style="font-size:11px;color:var(--muted)">Only admins can provision VPS</span>
        </div>
        <table><thead><tr><th>UUID</th><th>Name</th><th>Status</th><th>CPU</th><th>RAM</th><th>Actions</th></tr></thead>
        <tbody id="server-list"></tbody></table>
      </div>
    </div>

    <!-- Console -->
    <div class="page" id="page-console">
      <div class="page-title">Console</div>
      <div class="card" style="padding:20px;">
        <div style="font-size:13px;color:var(--muted);margin-bottom:12px;">Select a server to view console access.</div>
        <select id="console-vps-select" style="background:var(--bg3);border:1px solid var(--border);border-radius:6px;padding:8px 12px;color:var(--text);font-size:13px;margin-bottom:16px;">
          <option>— Select VPS —</option>
        </select>
        <div class="console-box" id="console-output">Waiting for selection...</div>
        <div class="tmate-info" id="tmate-info" style="display:none">
          <div><span>SSH Access: </span><span id="tmate-ssh" style="color:var(--accent)"></span></div>
          <div style="margin-top:6px"><span>Web Access: </span><span id="tmate-web" style="color:var(--green)"></span></div>
        </div>
      </div>
    </div>

    <!-- Ranks -->
    <div class="page" id="page-ranks">
      <div class="page-title">Rank System</div>
      <div style="display:grid;gap:16px;">
        <div class="card" style="padding:24px;">
          <div style="font-size:16px;font-weight:600;margin-bottom:16px">Current Rank: <span class="rank-badge" id="rank-display">Newbie</span></div>
          <div style="color:var(--muted);font-size:13px;line-height:1.8;">
            <div>🔵 <b>Newbie</b> — Starting rank. 0–1 VPS.</div>
            <div>🔷 <b>Pro</b> — Unlocked at 2 VPS.</div>
            <div>💜 <b>Ultimate</b> — Unlocked at 4 VPS. Claim exclusive rewards.</div>
          </div>
        </div>
        <div class="card" style="padding:24px;">
          <div style="font-size:14px;font-weight:600;margin-bottom:12px">Claim Reward</div>
          <div style="display:flex;gap:10px;">
            <input id="reward-code" placeholder="Enter reward code" style="flex:1;background:var(--bg3);border:1px solid var(--border);border-radius:6px;padding:9px 14px;color:var(--text);font-size:13px;">
            <button class="btn" style="width:auto;padding:9px 18px" onclick="claimReward()">Claim</button>
          </div>
          <div id="reward-msg" style="margin-top:10px;font-size:13px;"></div>
        </div>
      </div>
    </div>

    <!-- Admin Panel -->
    <div class="page" id="page-admin">
      <div class="page-title">Admin Panel</div>
      <div style="display:grid;gap:20px;">
        <div class="card">
          <div class="card-header">All Users</div>
          <table><thead><tr><th>ID</th><th>Username</th><th>Role</th><th>Rank</th><th>VPS</th><th>Status</th><th>Actions</th></tr></thead>
          <tbody id="admin-user-list"></tbody></table>
        </div>
        <div class="card">
          <div class="card-header">All VPS</div>
          <table><thead><tr><th>UUID</th><th>Name</th><th>Owner</th><th>Status</th><th>Actions</th></tr></thead>
          <tbody id="admin-vps-list"></tbody></table>
        </div>
        <div class="card" style="padding:24px;">
          <div style="font-size:14px;font-weight:600;margin-bottom:16px;">Create VPS</div>
          <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;">
            <div class="form-group"><label>VPS Name</label><input id="vps-name" placeholder="my-server"></div>
            <div class="form-group"><label>Owner ID</label><input id="vps-owner" placeholder="User ID"></div>
            <div class="form-group"><label>Node ID</label><input id="vps-node" placeholder="1"></div>
            <div class="form-group"><label>Docker Image</label><input id="vps-image" placeholder="ubuntu:22.04"></div>
            <div class="form-group"><label>RAM (MB)</label><input id="vps-mem" placeholder="512"></div>
            <div class="form-group"><label>Disk (GB)</label><input id="vps-disk" placeholder="10"></div>
            <div class="form-group"><label>CPU Cores</label><input id="vps-cpu" placeholder="1"></div>
          </div>
          <button class="btn" style="margin-top:8px;width:auto;padding:10px 24px" onclick="createVPS()">Create VPS</button>
        </div>
      </div>
    </div>
  </div>
</div>

<div id="toast"></div>

<script>
const API = '/api';
let authToken = localStorage.getItem('gvm_token');
let currentUser = JSON.parse(localStorage.getItem('gvm_user') || 'null');
let vpsList = [];

async function api(method, path, body) {
  const opts = { method, headers: { 'Content-Type': 'application/json' } };
  if (authToken) opts.headers['Authorization'] = 'Bearer ' + authToken;
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(API + path, opts);
  return { ok: res.ok, status: res.status, data: await res.json() };
}

function toast(msg, type = 'ok') {
  const t = document.getElementById('toast');
  t.textContent = msg; t.className = 'show ' + type;
  setTimeout(() => t.className = '', 3000);
}

function showPage(name) {
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
  document.getElementById('page-' + name)?.classList.add('active');
  if (name === 'servers') loadServers();
  if (name === 'admin') loadAdmin();
  if (name === 'console') loadConsoleSelect();
}

async function doLogin() {
  const email = document.getElementById('login-email').value;
  const pass  = document.getElementById('login-pass').value;
  const { ok, data } = await api('POST', '/auth/login', { email, password: pass });
  if (!ok) {
    const el = document.getElementById('login-err');
    el.textContent = data.error; el.style.display = 'block'; return;
  }
  authToken = data.token;
  currentUser = data.user;
  localStorage.setItem('gvm_token', authToken);
  localStorage.setItem('gvm_user', JSON.stringify(currentUser));
  boot();
}

function boot() {
  if (!authToken) return;
  document.getElementById('login-screen').style.display = 'none';
  document.getElementById('app').style.display = 'block';
  document.getElementById('sidebar-username').textContent = currentUser.username;
  document.getElementById('sidebar-rank').textContent = currentUser.rank;
  document.getElementById('sidebar-rank').className = 'rank-badge ' + currentUser.rank;
  document.getElementById('stat-rank').textContent = currentUser.rank;
  document.getElementById('rank-display').textContent = currentUser.rank;
  if (['admin','owner'].includes(currentUser.role)) {
    document.getElementById('admin-nav').style.display = 'block';
  }
  loadDashboard();
}

async function loadDashboard() {
  const { ok, data } = await api('GET', '/vps', null);
  if (!ok) return;
  vpsList = data.vps || [];
  document.getElementById('stat-vps').textContent = vpsList.length;
  document.getElementById('stat-running').textContent = vpsList.filter(v => v.status === 'running').length;
  const tbody = document.getElementById('dash-vps-list');
  tbody.innerHTML = vpsList.slice(0,5).map(v => \`
    <tr>
      <td>\${v.name}</td>
      <td><span class="status-dot \${v.status}"></span>\${v.status}</td>
      <td>\${v.node_name || '—'}</td>
      <td>\${v.location || '—'}</td>
    </tr>
  \`).join('') || '<tr><td colspan="4" style="color:var(--muted);text-align:center">No VPS assigned yet.</td></tr>';
}

async function loadServers() {
  const { ok, data } = await api('GET', '/vps', null);
  if (!ok) return;
  vpsList = data.vps || [];
  const tbody = document.getElementById('server-list');
  tbody.innerHTML = vpsList.map(v => \`
    <tr>
      <td style="font-family:var(--mono);font-size:11px">\${v.uuid.slice(0,8)}</td>
      <td>\${v.name}</td>
      <td><span class="status-dot \${v.status}"></span>\${v.status}</td>
      <td>\${v.cpu_cores} vCPU</td>
      <td>\${v.memory_mb} MB</td>
      <td>
        <button class="action-btn start"  onclick="power('\${v.uuid}','start')">▶ Start</button>
        <button class="action-btn stop"   onclick="power('\${v.uuid}','stop')">■ Stop</button>
        <button class="action-btn console" onclick="openConsole('\${v.uuid}')">⌨ Console</button>
      </td>
    </tr>
  \`).join('') || '<tr><td colspan="6" style="color:var(--muted);text-align:center">No VPS found.</td></tr>';
}

async function power(uuid, action) {
  const { ok, data } = await api('POST', \`/vps/\${uuid}/power/\${action}\`, {});
  toast(ok ? data.message : data.error, ok ? 'ok' : 'err');
  if (ok) loadServers();
}

function openConsole(uuid) {
  showPage('console');
  const vps = vpsList.find(v => v.uuid === uuid);
  if (!vps) return;
  document.getElementById('console-output').textContent = \`Connected to: \${vps.name}\\nStatus: \${vps.status}\\nUUID: \${uuid}\\n\\nUse the tmate session below to access the terminal.\`;
  if (vps.tmate_session) {
    document.getElementById('tmate-info').style.display = 'block';
    document.getElementById('tmate-ssh').textContent = vps.tmate_session;
    document.getElementById('tmate-web').textContent = 'https://tmate.io/t/' + vps.tmate_session.split('/').pop();
  }
}

function loadConsoleSelect() {
  const sel = document.getElementById('console-vps-select');
  sel.innerHTML = '<option>— Select VPS —</option>' + vpsList.map(v =>
    \`<option value="\${v.uuid}">\${v.name} (\${v.status})</option>\`
  ).join('');
  sel.onchange = () => { if (sel.value !== '— Select VPS —') openConsole(sel.value); };
}

async function loadAdmin() {
  const [usersRes, vpsRes] = await Promise.all([
    api('GET', '/admin/users', null),
    api('GET', '/admin/vps', null),
  ]);

  const users = usersRes.data.users || [];
  const vps   = vpsRes.data.vps || [];

  document.getElementById('admin-user-list').innerHTML = users.map(u => \`
    <tr>
      <td>\${u.id}</td>
      <td>\${u.username}</td>
      <td>\${u.role}</td>
      <td><span class="rank-badge \${u.rank}">\${u.rank}</span></td>
      <td>\${u.vps_count}</td>
      <td style="color:\${u.banned ? 'var(--red)' : 'var(--green)'}">\${u.banned ? 'Banned' : 'Active'}</td>
      <td>
        <button class="action-btn stop" onclick="banUser(\${u.id})">Ban</button>
        <button class="action-btn start" onclick="unbanUser(\${u.id})">Unban</button>
      </td>
    </tr>
  \`).join('');

  document.getElementById('admin-vps-list').innerHTML = vps.map(v => \`
    <tr>
      <td style="font-family:var(--mono);font-size:11px">\${v.uuid.slice(0,8)}</td>
      <td>\${v.name}</td>
      <td>\${v.username}</td>
      <td><span class="status-dot \${v.status}"></span>\${v.status}</td>
      <td><button class="action-btn stop" onclick="deleteVPS('\${v.uuid}')">Delete</button></td>
    </tr>
  \`).join('');
}

async function createVPS() {
  const body = {
    name:       document.getElementById('vps-name').value,
    owner_id:   parseInt(document.getElementById('vps-owner').value),
    node_id:    parseInt(document.getElementById('vps-node').value),
    image:      document.getElementById('vps-image').value,
    memory_mb:  parseInt(document.getElementById('vps-mem').value),
    disk_gb:    parseInt(document.getElementById('vps-disk').value),
    cpu_cores:  parseInt(document.getElementById('vps-cpu').value),
  };
  const { ok, data } = await api('POST', '/admin/vps', body);
  toast(ok ? 'VPS created: ' + data.uuid : data.error, ok ? 'ok' : 'err');
  if (ok) loadAdmin();
}

async function deleteVPS(uuid) {
  if (!confirm('Delete VPS ' + uuid + '?')) return;
  const { ok, data } = await api('DELETE', '/admin/vps/' + uuid, null);
  toast(ok ? 'Deleted' : data.error, ok ? 'ok' : 'err');
  if (ok) loadAdmin();
}

async function banUser(id) {
  const reason = prompt('Ban reason:');
  if (!reason) return;
  const { ok, data } = await api('POST', '/admin/users/' + id + '/ban', { reason });
  toast(ok ? 'User banned' : data.error, ok ? 'ok' : 'err');
  if (ok) loadAdmin();
}

async function unbanUser(id) {
  const { ok, data } = await api('POST', '/admin/users/' + id + '/unban', {});
  toast(ok ? 'User unbanned' : data.error, ok ? 'ok' : 'err');
  if (ok) loadAdmin();
}

async function claimReward() {
  const code = document.getElementById('reward-code').value;
  const { ok, data } = await api('POST', '/api/rewards/claim', { code });
  document.getElementById('reward-msg').textContent = ok ? '✅ ' + data.reward.name : '❌ ' + data.message;
  document.getElementById('reward-msg').style.color = ok ? 'var(--green)' : 'var(--red)';
}

function showRegister() {
  const email = prompt('Email:');
  const user  = prompt('Username:');
  const pass  = prompt('Password:');
  if (!email || !user || !pass) return;
  api('POST', '/auth/register', { email, username: user, password: pass }).then(({ok, data}) => {
    if (ok) { alert('Account created! Sign in now.'); }
    else     { alert('Error: ' + data.error); }
  });
}

// Boot on load
if (authToken) boot();
</script>
</body>
</html>
HTML

# ── Nginx config ──────────────────────────────────────────────
log "Writing Nginx configuration..."
cat > /etc/nginx/sites-available/grimvm <<NGINX
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache   shared:SSL:10m;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy strict-origin-when-cross-origin;

    root ${APP_DIR}/public;
    index index.php index.html;

    client_max_body_size 64M;

    location /api {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_read_timeout 300;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location ~ /\.ht { deny all; }
    location ~ /\.env { deny all; }

    access_log /var/log/nginx/grimvm_access.log;
    error_log  /var/log/nginx/grimvm_error.log;
}
NGINX

ln -sf /etc/nginx/sites-available/grimvm /etc/nginx/sites-enabled/grimvm
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# ── PHP-FPM pool ──────────────────────────────────────────────
log "Configuring PHP-FPM pool..."
cat > /etc/php/8.2/fpm/pool.d/grimvm.conf <<INI
[grimvm]
user = www-data
group = www-data
listen = /var/run/php/php8.2-fpm.sock
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 25
pm.start_servers = 5
pm.min_spare_servers = 3
pm.max_spare_servers = 10
pm.max_requests = 500
php_admin_value[error_log] = ${APP_DIR}/storage/logs/php-fpm.log
php_admin_flag[log_errors] = on
php_value[upload_max_filesize] = 64M
php_value[post_max_size] = 64M
INI

systemctl restart php8.2-fpm

# ── Composer install ──────────────────────────────────────────
log "Installing PHP dependencies via Composer..."
cd "${APP_DIR}"
composer install --no-dev --optimize-autoloader --no-interaction

# ── Permissions ───────────────────────────────────────────────
log "Setting permissions..."
chown -R www-data:www-data "${APP_DIR}"
chmod -R 755 "${APP_DIR}"
chmod -R 775 "${APP_DIR}/storage"
chmod 600 "${APP_DIR}/.env"

# Add www-data to docker group
usermod -aG docker www-data

# ── Seed admin user ───────────────────────────────────────────
log "Creating admin account..."
HASHED_PASS=$(php -r "echo password_hash('${ADMIN_PASS}', PASSWORD_BCRYPT, ['cost'=>12]);")
mysql -u root -p"${MYSQL_ROOT_PASS}" "${DB_NAME}" <<SQL
INSERT INTO users (username, email, password, role, rank)
VALUES ('${ADMIN_USER}', '${ADMIN_EMAIL_ACCT}', '${HASHED_PASS}', 'owner', 'Ultimate')
ON DUPLICATE KEY UPDATE role='owner';
SQL

# Seed a sample node
mysql -u root -p"${MYSQL_ROOT_PASS}" "${DB_NAME}" <<SQL
INSERT INTO nodes (name, location, ip, port, memory_mb, disk_gb, cpu_cores)
VALUES ('Node-01', 'US-East', '127.0.0.1', 2222, 8192, 100, 4);
SQL

# Seed default eggs
mysql -u root -p"${MYSQL_ROOT_PASS}" "${DB_NAME}" <<SQL
INSERT INTO eggs (name, docker_image, startup_cmd, description, author) VALUES
  ('Ubuntu 22.04',   'ubuntu:22.04',          '/bin/bash', 'Ubuntu 22.04 LTS', 'ArizNodes'),
  ('Debian 12',      'debian:12',              '/bin/bash', 'Debian Bookworm',  'ArizNodes'),
  ('Alpine Linux',   'alpine:3.19',            '/bin/sh',   'Alpine Linux',     'ArizNodes'),
  ('Node.js 20',     'node:20-alpine',         'node',      'Node.js 20 LTS',   'ArizNodes'),
  ('Python 3.12',    'python:3.12-slim',       'python3',   'Python 3.12',      'ArizNodes'),
  ('Minecraft Java', 'itzg/minecraft-server',  '',          'Minecraft Java',   'ArizNodes');
SQL

# ── Fail2ban for Nginx ────────────────────────────────────────
log "Configuring Fail2ban..."
cat > /etc/fail2ban/jail.d/grimvm.conf <<F2B
[nginx-http-auth]
enabled = true
[nginx-botsearch]
enabled = true
maxretry = 2
bantime  = 86400
[nginx-limit-req]
enabled = true
F2B
systemctl restart fail2ban

# ── Systemd service ───────────────────────────────────────────
log "Creating systemd service..."
cat > /etc/systemd/system/grimvm.service <<UNIT
[Unit]
Description=GrimVM Panel
After=network.target mysql.service nginx.service redis.service
Wants=mysql.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecStop=/bin/true

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable grimvm

# ── Auto-renewal for SSL ──────────────────────────────────────
(crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet && systemctl reload nginx") | crontab -

# ── Final banner ──────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  GrimVM Installed Successfully!${RESET}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${RESET}"
echo ""
echo -e " Panel URL:    ${CYAN}https://${DOMAIN}${RESET}"
echo -e " Admin Panel:  ${CYAN}https://${DOMAIN}/admin${RESET}"
echo -e " Admin User:   ${YELLOW}${ADMIN_USER}${RESET}"
echo -e " Admin Email:  ${YELLOW}${ADMIN_EMAIL_ACCT}${RESET}"
echo ""
echo -e " Install cmd:"
echo -e " ${BOLD}bash <(curl -s https://raw.githubusercontent.com/Vasplayz90OG/GrimVM--5/main/install.sh)${RESET}"
echo ""
echo -e " GitHub: https://github.com/Vasplayz90OG/GrimVM--5"
echo -e " Copyright Reserved 2026 ArizNodes Team | MIT License"
echo ""
