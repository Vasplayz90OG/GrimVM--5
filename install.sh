#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# GrimVM #5
# Author: Vasplayz90 • ArizNodes Team
# License: MIT
# Copyright: © 2026 ArizNodes Team - Reserved
# ============================================================

GRIM_VERSION="0.1.0"
INSTALL_DIR="/opt/grimvm"
DATA_DIR="${INSTALL_DIR}/data"
BACKEND_DIR="${INSTALL_DIR}/backend"
FRONTEND_DIR="${INSTALL_DIR}/frontend"
DOCKER_DIR="${INSTALL_DIR}/docker"
NGINX_DIR="${INSTALL_DIR}/nginx"
ENV_FILE="${INSTALL_DIR}/.env"
SERVICE_FILE="/etc/systemd/system/grimvm.service"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[GRIMVM]${NC} $1"
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

die() {
    error "$1"
    exit 1
}

trap 'error "Installation failed at line $LINENO."' ERR

clear || true

cat <<'BANNER'
============================================================
                         GRIM VM
                 ArizNodes Virtualization
============================================================
 Project      : GrimVM #5
 Author       : Vasplayz90 • ArizNodes Team
 License      : MIT
 Copyright    : © 2026 ArizNodes Team - Reserved
============================================================
BANNER

# ------------------------------------------------------------
# Root check
# ------------------------------------------------------------

if [[ "${EUID}" -ne 0 ]]; then
    die "Run this installer as root: sudo bash install.sh"
fi

# ------------------------------------------------------------
# OS check
# ------------------------------------------------------------

source /etc/os-release

OS_ID="${ID:-unknown}"
OS_VERSION="${VERSION_ID:-unknown}"

case "${OS_ID}" in
    ubuntu)
        case "${OS_VERSION}" in
            22.04|24.04|26.04)
                log "Supported Ubuntu version detected: ${OS_VERSION}"
                ;;
            *)
                die "Unsupported Ubuntu version: ${OS_VERSION}. Use Ubuntu 22.04, 24.04 or 26.04."
                ;;
        esac
        ;;
    debian)
        if [[ "${OS_VERSION}" != "13" ]]; then
            die "Use Debian 13 for a supported Debian installation."
        fi
        log "Supported Debian version detected: ${OS_VERSION}"
        ;;
    *)
        die "Unsupported operating system. Use Ubuntu or Debian 13."
        ;;
esac

ARCH="$(dpkg --print-architecture)"

if [[ "${ARCH}" != "amd64" && "${ARCH}" != "arm64" ]]; then
    die "This installer currently supports amd64 and arm64."
fi

log "Architecture: ${ARCH}"

# ------------------------------------------------------------
# Basic packages
# ------------------------------------------------------------

log "Updating package index..."

export DEBIAN_FRONTEND=noninteractive

apt-get update -y

apt-get install -y \
    ca-certificates \
    curl \
    wget \
    git \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    nginx \
    certbot \
    python3 \
    python3-venv \
    python3-pip \
    openssl \
    jq \
    unzip \
    ufw

# ------------------------------------------------------------
# Docker
# ------------------------------------------------------------

if command -v docker >/dev/null 2>&1; then
    log "Docker already installed."
else
    log "Installing Docker from the official Docker repository..."

    install -m 0755 -d /etc/apt/keyrings

    if [[ "${OS_ID}" == "ubuntu" ]]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
            -o /etc/apt/keyrings/docker.asc

        chmod a+r /etc/apt/keyrings/docker.asc

        cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    else
        curl -fsSL https://download.docker.com/linux/debian/gpg \
            -o /etc/apt/keyrings/docker.asc

        chmod a+r /etc/apt/keyrings/docker.asc

        cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    fi

    apt-get update -y

    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
fi

systemctl enable docker
systemctl start docker

docker version >/dev/null

log "Docker is ready."

# ------------------------------------------------------------
# Create directories
# ------------------------------------------------------------

log "Creating GrimVM directory structure..."

mkdir -p \
    "${INSTALL_DIR}" \
    "${DATA_DIR}" \
    "${BACKEND_DIR}/routes" \
    "${FRONTEND_DIR}/css" \
    "${FRONTEND_DIR}/js" \
    "${DOCKER_DIR}/ubuntu" \
    "${DOCKER_DIR}/debian" \
    "${NGINX_DIR}" \
    "${DATA_DIR}/backups"

# ------------------------------------------------------------
# Generate secrets
# ------------------------------------------------------------

if [[ ! -f "${ENV_FILE}" ]]; then

    APP_SECRET="$(openssl rand -hex 32)"
    DB_ROOT_PASSWORD="$(openssl rand -hex 24)"
    DB_PASSWORD="$(openssl rand -hex 24)"

    read -r -p "Panel domain (example: panel.example.com): " DOMAIN

    if [[ -z "${DOMAIN}" ]]; then
        DOMAIN="localhost"
    fi

    read -r -p "Admin username [admin]: " ADMIN_USERNAME
    ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"

    while true; do
        read -r -s -p "Admin password: " ADMIN_PASSWORD
        echo

        if [[ ${#ADMIN_PASSWORD} -lt 8 ]]; then
            warn "Password must contain at least 8 characters."
            continue
        fi

        read -r -s -p "Confirm admin password: " ADMIN_PASSWORD_CONFIRM
        echo

        if [[ "${ADMIN_PASSWORD}" != "${ADMIN_PASSWORD_CONFIRM}" ]]; then
            warn "Passwords do not match."
            continue
        fi

        break
    done

    read -r -p "Admin email: " ADMIN_EMAIL

    cat >"${ENV_FILE}" <<EOF
GRIM_VERSION=${GRIM_VERSION}

GRIM_DOMAIN=${DOMAIN}

APP_SECRET=${APP_SECRET}

MYSQL_HOST=127.0.0.1
MYSQL_PORT=3307
MYSQL_DATABASE=grimvm
MYSQL_USER=grimvm
MYSQL_PASSWORD=${DB_PASSWORD}
MYSQL_ROOT_PASSWORD=${DB_ROOT_PASSWORD}

ADMIN_USERNAME=${ADMIN_USERNAME}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
ADMIN_EMAIL=${ADMIN_EMAIL}

GRIM_VPS_NETWORK=grimvm_vps
EOF

    chmod 600 "${ENV_FILE}"

else
    log "Existing GrimVM environment detected."
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

# ------------------------------------------------------------
# Docker network
# ------------------------------------------------------------

if ! docker network inspect "${GRIM_VPS_NETWORK}" >/dev/null 2>&1; then
    log "Creating GrimVM VPS network..."
    docker network create "${GRIM_VPS_NETWORK}"
fi

# ------------------------------------------------------------
# MySQL Docker Compose
# ------------------------------------------------------------

log "Creating MySQL configuration..."

cat >"${INSTALL_DIR}/docker-compose.yml" <<EOF
services:

  mysql:
    image: mysql:8.4
    container_name: grimvm_mysql
    restart: unless-stopped

    environment:
      MYSQL_ROOT_PASSWORD: "${MYSQL_ROOT_PASSWORD}"
      MYSQL_DATABASE: "${MYSQL_DATABASE}"
      MYSQL_USER: "${MYSQL_USER}"
      MYSQL_PASSWORD: "${MYSQL_PASSWORD}"

    ports:
      - "127.0.0.1:${MYSQL_PORT}:3306"

    volumes:
      - grimvm_mysql:/var/lib/mysql

    command:
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci

volumes:
  grimvm_mysql:
EOF

docker compose -f "${INSTALL_DIR}/docker-compose.yml" up -d

log "Waiting for MySQL..."

for i in {1..60}; do
    if docker exec grimvm_mysql \
        mysqladmin ping \
        -h 127.0.0.1 \
        -u root \
        "-p${MYSQL_ROOT_PASSWORD}" \
        --silent >/dev/null 2>&1; then
        break
    fi

    sleep 2
done

if ! docker exec grimvm_mysql \
    mysqladmin ping \
    -h 127.0.0.1 \
    -u root \
    "-p${MYSQL_ROOT_PASSWORD}" \
    --silent >/dev/null 2>&1; then
    die "MySQL failed to start."
fi

log "MySQL is ready."

# ------------------------------------------------------------
# Python requirements
# ------------------------------------------------------------

log "Creating Python virtual environment..."

python3 -m venv "${BACKEND_DIR}/venv"

"${BACKEND_DIR}/venv/bin/pip" install --upgrade pip

cat >"${BACKEND_DIR}/requirements.txt" <<'EOF'
fastapi==0.116.1
uvicorn[standard]==0.35.0
SQLAlchemy==2.0.43
PyMySQL==1.1.1
PyJWT==2.10.1
docker==7.1.0
python-multipart==0.0.20
email-validator==2.2.0
EOF

"${BACKEND_DIR}/venv/bin/pip" install -r "${BACKEND_DIR}/requirements.txt"

# ------------------------------------------------------------
# Database
# ------------------------------------------------------------

cat >"${BACKEND_DIR}/database.py" <<'PY'
import os

from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker


MYSQL_HOST = os.getenv("MYSQL_HOST", "127.0.0.1")
MYSQL_PORT = os.getenv("MYSQL_PORT", "3307")
MYSQL_DATABASE = os.getenv("MYSQL_DATABASE", "grimvm")
MYSQL_USER = os.getenv("MYSQL_USER", "grimvm")
MYSQL_PASSWORD = os.getenv("MYSQL_PASSWORD", "")

DATABASE_URL = (
    f"mysql+pymysql://{MYSQL_USER}:{MYSQL_PASSWORD}"
    f"@{MYSQL_HOST}:{MYSQL_PORT}/{MYSQL_DATABASE}"
)

engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    pool_recycle=280,
)

SessionLocal = sessionmaker(
    bind=engine,
    autoflush=False,
    autocommit=False,
)

Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
PY

# ------------------------------------------------------------
# Models
# ------------------------------------------------------------

cat >"${BACKEND_DIR}/models.py" <<'PY'
from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
)

from sqlalchemy.orm import Mapped, mapped_column

from database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)

    username: Mapped[str] = mapped_column(
        String(64),
        unique=True,
        nullable=False,
    )

    email: Mapped[str] = mapped_column(
        String(255),
        unique=True,
        nullable=False,
    )

    password_hash: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
    )

    role: Mapped[str] = mapped_column(
        String(32),
        default="user",
        nullable=False,
    )

    rank: Mapped[str] = mapped_column(
        String(32),
        default="newbie",
        nullable=False,
    )

    banned: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
        nullable=False,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        nullable=False,
    )


class VPS(Base):
    __tablename__ = "vps"

    id: Mapped[int] = mapped_column(
        Integer,
        primary_key=True,
    )

    uuid: Mapped[str] = mapped_column(
        String(64),
        unique=True,
        nullable=False,
    )

    name: Mapped[str] = mapped_column(
        String(128),
        nullable=False,
    )

    owner_id: Mapped[int] = mapped_column(
        ForeignKey("users.id"),
        nullable=False,
    )

    node: Mapped[str] = mapped_column(
        String(128),
        default="node-1",
        nullable=False,
    )

    image: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
    )

    container_id: Mapped[str | None] = mapped_column(
        String(128),
        nullable=True,
    )

    cpu: Mapped[int] = mapped_column(
        Integer,
        default=1,
        nullable=False,
    )

    ram_mb: Mapped[int] = mapped_column(
        Integer,
        default=1024,
        nullable=False,
    )

    disk_gb: Mapped[int] = mapped_column(
        Integer,
        default=10,
        nullable=False,
    )

    status: Mapped[str] = mapped_column(
        String(32),
        default="stopped",
        nullable=False,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        nullable=False,
    )


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id: Mapped[int] = mapped_column(
        Integer,
        primary_key=True,
    )

    actor_id: Mapped[int | None] = mapped_column(
        Integer,
        nullable=True,
    )

    action: Mapped[str] = mapped_column(
        String(128),
        nullable=False,
    )

    target: Mapped[str | None] = mapped_column(
        String(255),
        nullable=True,
    )

    details: Mapped[str | None] = mapped_column(
        Text,
        nullable=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        nullable=False,
    )
PY

# ------------------------------------------------------------
# Authentication helpers
# ------------------------------------------------------------

cat >"${BACKEND_DIR}/security.py" <<'PY'
import hashlib
import hmac
import os

import jwt


SECRET = os.getenv("APP_SECRET", "")
ALGORITHM = "HS256"


def hash_password(password: str) -> str:
    salt = os.urandom(16)

    derived = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode(),
        salt,
        310000,
    )

    return (
        "pbkdf2_sha256$310000$"
        + salt.hex()
        + "$"
        + derived.hex()
    )


def verify_password(password: str, stored: str) -> bool:
    try:
        method, iterations, salt_hex, hash_hex = stored.split("$")

        if method != "pbkdf2_sha256":
            return False

        derived = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode(),
            bytes.fromhex(salt_hex),
            int(iterations),
        )

        return hmac.compare_digest(
            derived.hex(),
            hash_hex,
        )

    except Exception:
        return False


def create_token(user_id: int) -> str:
    return jwt.encode(
        {
            "user_id": user_id,
        },
        SECRET,
        algorithm=ALGORITHM,
    )


def decode_token(token: str) -> dict:
    return jwt.decode(
        token,
        SECRET,
        algorithms=[ALGORITHM],
    )
PY

# ------------------------------------------------------------
# Docker manager
# ------------------------------------------------------------

cat >"${BACKEND_DIR}/docker_manager.py" <<'PY'
import os
import uuid

import docker


NETWORK_NAME = os.getenv(
    "GRIM_VPS_NETWORK",
    "grimvm_vps",
)

client = docker.from_env()


def ensure_network():
    try:
        client.networks.get(NETWORK_NAME)
    except docker.errors.NotFound:
        client.networks.create(
            NETWORK_NAME,
            driver="bridge",
        )


def create_vps(
    name: str,
    image: str,
    cpu: int,
    ram_mb: int,
    disk_gb: int,
):
    ensure_network()

    vps_uuid = str(uuid.uuid4())

    container_name = (
        "grimvm_"
        + vps_uuid.replace("-", "")[:16]
    )

    mem_limit = f"{ram_mb}m"

    nano_cpus = cpu * 1_000_000_000

    container = client.containers.run(
        image=image,
        name=container_name,
        hostname=name,
        command=[
            "/bin/bash",
            "-c",
            "while true; do sleep 3600; done",
        ],
        detach=True,
        stdin_open=True,
        tty=True,
        mem_limit=mem_limit,
        nano_cpus=nano_cpus,
        network=NETWORK_NAME,
        restart_policy={
            "Name": "unless-stopped"
        },
        labels={
            "com.ariznodes.grimvm": "true",
            "com.ariznodes.grimvm.uuid": vps_uuid,
        },
    )

    return {
        "uuid": vps_uuid,
        "container_id": container.id,
        "container_name": container_name,
    }


def start(container_id: str):
    client.containers.get(container_id).start()


def stop(container_id: str):
    client.containers.get(container_id).stop()


def restart(container_id: str):
    client.containers.get(container_id).restart()


def remove(container_id: str):
    container = client.containers.get(container_id)

    container.remove(
        force=True,
    )


def status(container_id: str):
    container = client.containers.get(container_id)

    container.reload()

    return container.status
PY

# ------------------------------------------------------------
# FastAPI application
# ------------------------------------------------------------

cat >"${BACKEND_DIR}/app.py" <<'PY'
import os
from pathlib import Path

from fastapi import (
    Depends,
    FastAPI,
    Header,
    HTTPException,
)

from fastapi.middleware.cors import CORSMiddleware

from pydantic import BaseModel

from sqlalchemy import func
from sqlalchemy.orm import Session

from database import Base, engine, get_db
from docker_manager import (
    create_vps,
    restart,
    start,
    status,
    stop,
    remove,
)
from models import AuditLog, User, VPS
from security import (
    create_token,
    decode_token,
    hash_password,
    verify_password,
)


app = FastAPI(
    title="GrimVM API",
    version=os.getenv(
        "GRIM_VERSION",
        "0.1.0",
    ),
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

Base.metadata.create_all(bind=engine)


class RegisterRequest(BaseModel):
    username: str
    email: str
    password: str


class LoginRequest(BaseModel):
    username: str
    password: str


class CreateVPSRequest(BaseModel):
    owner_id: int
    name: str
    image: str = "ubuntu:24.04"
    cpu: int = 1
    ram_mb: int = 1024
    disk_gb: int = 10


def current_user(
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
):
    if not authorization:
        raise HTTPException(
            status_code=401,
            detail="Missing authorization token",
        )

    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=401,
            detail="Invalid authorization header",
        )

    token = authorization[7:]

    try:
        payload = decode_token(token)
        user_id = int(payload["user_id"])
    except Exception:
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired token",
        )

    user = db.get(User, user_id)

    if not user:
        raise HTTPException(
            status_code=401,
            detail="User not found",
        )

    if user.banned:
        raise HTTPException(
            status_code=403,
            detail="Account banned",
        )

    return user


def admin_required(
    user=Depends(current_user),
):
    if user.role != "admin":
        raise HTTPException(
            status_code=403,
            detail="Administrator access required",
        )

    return user


def write_audit(
    db: Session,
    actor_id: int | None,
    action: str,
    target: str | None = None,
    details: str | None = None,
):
    db.add(
        AuditLog(
            actor_id=actor_id,
            action=action,
            target=target,
            details=details,
        )
    )

    db.commit()


@app.get("/api/health")
def health():
    return {
        "status": "online",
        "name": "GrimVM",
        "version": os.getenv(
            "GRIM_VERSION",
            "0.1.0",
        ),
    }


@app.post("/api/auth/register")
def register(
    request: RegisterRequest,
    db: Session = Depends(get_db),
):
    username = request.username.strip()
    email = request.email.strip().lower()

    if len(username) < 3:
        raise HTTPException(
            status_code=400,
            detail="Username must contain at least 3 characters",
        )

    if len(request.password) < 8:
        raise HTTPException(
            status_code=400,
            detail="Password must contain at least 8 characters",
        )

    if db.query(User).filter(
        func.lower(User.username) == username.lower()
    ).first():
        raise HTTPException(
            status_code=409,
            detail="Username already exists",
        )

    if db.query(User).filter(
        func.lower(User.email) == email.lower()
    ).first():
        raise HTTPException(
            status_code=409,
            detail="Email already exists",
        )

    user = User(
        username=username,
        email=email,
        password_hash=hash_password(
            request.password
        ),
        role="user",
        rank="newbie",
    )

    db.add(user)
    db.commit()
    db.refresh(user)

    write_audit(
        db,
        user.id,
        "REGISTER",
        f"user:{user.id}",
    )

    return {
        "message": "Account created",
        "user_id": user.id,
    }


@app.post("/api/auth/login")
def login(
    request: LoginRequest,
    db: Session = Depends(get_db),
):
    user = db.query(User).filter(
        func.lower(User.username)
        == request.username.lower()
    ).first()

    if not user:
        raise HTTPException(
            status_code=401,
            detail="Invalid username or password",
        )

    if user.banned:
        raise HTTPException(
            status_code=403,
            detail="Account banned",
        )

    if not verify_password(
        request.password,
        user.password_hash,
    ):
        raise HTTPException(
            status_code=401,
            detail="Invalid username or password",
        )

    token = create_token(user.id)

    return {
        "token": token,
        "user": {
            "id": user.id,
            "username": user.username,
            "role": user.role,
            "rank": user.rank,
        },
    }


@app.get("/api/me")
def me(
    user=Depends(current_user),
):
    return {
        "id": user.id,
        "username": user.username,
        "email": user.email,
        "role": user.role,
        "rank": user.rank,
    }


@app.get("/api/vps")
def list_vps(
    user=Depends(current_user),
    db: Session = Depends(get_db),
):
    if user.role == "admin":
        vps_list = db.query(VPS).all()
    else:
        vps_list = db.query(VPS).filter(
            VPS.owner_id == user.id
        ).all()

    results = []

    for item in vps_list:

        live_status = item.status

        if item.container_id:
            try:
                live_status = status(
                    item.container_id
                )
            except Exception:
                live_status = "unknown"

        results.append({
            "id": item.id,
            "uuid": item.uuid,
            "name": item.name,
            "owner_id": item.owner_id,
            "node": item.node,
            "image": item.image,
            "cpu": item.cpu,
            "ram_mb": item.ram_mb,
            "disk_gb": item.disk_gb,
            "status": live_status,
            "created_at": item.created_at.isoformat(),
        })

    return results


@app.post("/api/admin/vps")
def create_admin_vps(
    request: CreateVPSRequest,
    admin=Depends(admin_required),
    db: Session = Depends(get_db),
):
    owner = db.get(User, request.owner_id)

    if not owner:
        raise HTTPException(
            status_code=404,
            detail="Owner user does not exist",
        )

    if request.cpu < 1 or request.cpu > 32:
        raise HTTPException(
            status_code=400,
            detail="CPU must be between 1 and 32",
        )

    if request.ram_mb < 256 or request.ram_mb > 131072:
        raise HTTPException(
            status_code=400,
            detail="RAM must be between 256 and 131072 MB",
        )

    if request.disk_gb < 1 or request.disk_gb > 2048:
        raise HTTPException(
            status_code=400,
            detail="Disk must be between 1 and 2048 GB",
        )

    allowed_images = {
        "ubuntu:24.04",
        "ubuntu:22.04",
        "debian:13",
        "debian:12",
        "alpine:latest",
    }

    if request.image not in allowed_images:
        raise HTTPException(
            status_code=400,
            detail="Image not allowed",
        )

    owner_vps_count = db.query(VPS).filter(
        VPS.owner_id == owner.id
    ).count()

    if owner.rank == "newbie":
        max_vps = 2
    elif owner.rank == "pro":
        max_vps = 4
    else:
        max_vps = 10

    if owner_vps_count >= max_vps:
        raise HTTPException(
            status_code=400,
            detail=(
                f"User rank {owner.rank} "
                f"allows a maximum of {max_vps} VPS"
            ),
        )

    try:
        created = create_vps(
            name=request.name,
            image=request.image,
            cpu=request.cpu,
            ram_mb=request.ram_mb,
            disk_gb=request.disk_gb,
        )
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Docker creation failed: {exc}",
        )

    vps = VPS(
        uuid=created["uuid"],
        name=request.name,
        owner_id=owner.id,
        node="node-1",
        image=request.image,
        container_id=created["container_id"],
        cpu=request.cpu,
        ram_mb=request.ram_mb,
        disk_gb=request.disk_gb,
        status="running",
    )

    db.add(vps)
    db.commit()
    db.refresh(vps)

    write_audit(
        db,
        admin.id,
        "CREATE_VPS",
        f"vps:{vps.id}",
        f"owner={owner.id}",
    )

    return {
        "message": "VPS created",
        "vps": {
            "id": vps.id,
            "uuid": vps.uuid,
            "container_id": vps.container_id,
        },
    }


@app.post("/api/vps/{vps_id}/start")
def start_vps(
    vps_id: int,
    user=Depends(current_user),
    db: Session = Depends(get_db),
):
    vps = db.get(VPS, vps_id)

    if not vps:
        raise HTTPException(
            status_code=404,
            detail="VPS not found",
        )

    if user.role != "admin" and vps.owner_id != user.id:
        raise HTTPException(
            status_code=403,
            detail="Access denied",
        )

    if not vps.container_id:
        raise HTTPException(
            status_code=400,
            detail="Container does not exist",
        )

    try:
        start(vps.container_id)
        vps.status = "running"
        db.commit()
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc),
        )

    write_audit(
        db,
        user.id,
        "START_VPS",
        f"vps:{vps.id}",
    )

    return {"message": "VPS started"}


@app.post("/api/vps/{vps_id}/stop")
def stop_vps(
    vps_id: int,
    user=Depends(current_user),
    db: Session = Depends(get_db),
):
    vps = db.get(VPS, vps_id)

    if not vps:
        raise HTTPException(
            status_code=404,
            detail="VPS not found",
        )

    if user.role != "admin" and vps.owner_id != user.id:
        raise HTTPException(
            status_code=403,
            detail="Access denied",
        )

    try:
        stop(vps.container_id)
        vps.status = "stopped"
        db.commit()
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc),
        )

    write_audit(
        db,
        user.id,
        "STOP_VPS",
        f"vps:{vps.id}",
    )

    return {"message": "VPS stopped"}


@app.post("/api/vps/{vps_id}/restart")
def restart_vps(
    vps_id: int,
    user=Depends(current_user),
    db: Session = Depends(get_db),
):
    vps = db.get(VPS, vps_id)

    if not vps:
        raise HTTPException(
            status_code=404,
            detail="VPS not found",
        )

    if user.role != "admin" and vps.owner_id != user.id:
        raise HTTPException(
            status_code=403,
            detail="Access denied",
        )

    try:
        restart(vps.container_id)
        vps.status = "running"
        db.commit()
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc),
        )

    write_audit(
        db,
        user.id,
        "RESTART_VPS",
        f"vps:{vps.id}",
    )

    return {"message": "VPS restarted"}


@app.delete("/api/admin/vps/{vps_id}")
def delete_vps(
    vps_id: int,
    admin=Depends(admin_required),
    db: Session = Depends(get_db),
):
    vps = db.get(VPS, vps_id)

    if not vps:
        raise HTTPException(
            status_code=404,
            detail="VPS not found",
        )

    try:
        if vps.container_id:
            remove(vps.container_id)
    except Exception:
        pass

    write_audit(
        db,
        admin.id,
        "DELETE_VPS",
        f"vps:{vps.id}",
        f"owner={vps.owner_id}",
    )

    db.delete(vps)
    db.commit()

    return {
        "message": "VPS deleted"
    }


@app.get("/api/admin/users")
def admin_users(
    admin=Depends(admin_required),
    db: Session = Depends(get_db),
):
    users = db.query(User).all()

    return [
        {
            "id": user.id,
            "username": user.username,
            "email": user.email,
            "role": user.role,
            "rank": user.rank,
            "banned": user.banned,
            "created_at": user.created_at.isoformat(),
        }
        for user in users
    ]


@app.post("/api/admin/users/{user_id}/ban")
def ban_user(
    user_id: int,
    admin=Depends(admin_required),
    db: Session = Depends(get_db),
):
    user = db.get(User, user_id)

    if not user:
        raise HTTPException(
            status_code=404,
            detail="User not found",
        )

    if user.id == admin.id:
        raise HTTPException(
            status_code=400,
            detail="You cannot ban yourself",
        )

    user.banned = True
    db.commit()

    write_audit(
        db,
        admin.id,
        "BAN_USER",
        f"user:{user.id}",
    )

    return {"message": "User banned"}


@app.post("/api/admin/users/{user_id}/unban")
def unban_user(
    user_id: int,
    admin=Depends(admin_required),
    db: Session = Depends(get_db),
):
    user = db.get(User, user_id)

    if not user:
        raise HTTPException(
            status_code=404,
            detail="User not found",
        )

    user.banned = False
    db.commit()

    write_audit(
        db,
        admin.id,
        "UNBAN_USER",
        f"user:{user.id}",
    )

    return {"message": "User unbanned"}


@app.get("/api/admin/audit")
def audit_logs(
    admin=Depends(admin_required),
    db: Session = Depends(get_db),
):
    logs = db.query(AuditLog).order_by(
        AuditLog.id.desc()
    ).limit(200).all()

    return [
        {
            "id": item.id,
            "actor_id": item.actor_id,
            "action": item.action,
            "target": item.target,
            "details": item.details,
            "created_at": item.created_at.isoformat(),
        }
        for item in logs
    ]
PY

# ------------------------------------------------------------
# Bootstrap admin
# ------------------------------------------------------------

cat >"${BACKEND_DIR}/bootstrap_admin.py" <<'PY'
import os
import sys

from database import Base, SessionLocal, engine
from models import User
from security import hash_password


Base.metadata.create_all(bind=engine)

db = SessionLocal()

username = os.getenv("ADMIN_USERNAME", "admin")
password = os.getenv("ADMIN_PASSWORD", "")
email = os.getenv(
    "ADMIN_EMAIL",
    "admin@example.com",
)

existing = db.query(User).filter(
    User.username == username
).first()

if existing:
    existing.role = "admin"
    existing.rank = "ultimate"

    if password:
        existing.password_hash = hash_password(password)

    existing.email = email

    db.commit()

    print(
        f"GrimVM admin updated: {username}"
    )

else:
    user = User(
        username=username,
        email=email,
        password_hash=hash_password(password),
        role="admin",
        rank="ultimate",
    )

    db.add(user)
    db.commit()

    print(
        f"GrimVM admin created: {username}"
    )

db.close()
PY

# ------------------------------------------------------------
# Frontend - index
# ------------------------------------------------------------

cat >"${FRONTEND_DIR}/index.html" <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta
        name="viewport"
        content="width=device-width, initial-scale=1"
    >

    <title>GrimVM</title>

    <link
        rel="stylesheet"
        href="/css/grim.css"
    >
</head>

<body>

<nav class="navbar">
    <div class="brand">
        GRIM<span>VM</span>
    </div>

    <div>
        <a href="/">Home</a>
        <a href="/login.html">Login</a>
    </div>
</nav>

<main class="hero">

    <section class="hero-card">

        <div class="badge">
            ARIZNODES • GRIMVM #5
        </div>

        <h1>
            Powerful virtualization.
            <br>
            <span>Simple control.</span>
        </h1>

        <p>
            GrimVM is a Docker-based virtualization
            management panel built by the ArizNodes Team.
        </p>

        <div class="actions">
            <a
                class="button primary"
                href="/login.html"
            >
                Open Panel
            </a>
        </div>

    </section>

    <section class="stats">

        <div class="stat">
            <strong id="apiStatus">...</strong>
            <span>API</span>
        </div>

        <div class="stat">
            <strong>Docker</strong>
            <span>VPS Engine</span>
        </div>

        <div class="stat">
            <strong>MySQL</strong>
            <span>Database</span>
        </div>

        <div class="stat">
            <strong>HTTPS</strong>
            <span>Secure Gateway</span>
        </div>

    </section>

</main>

<script>
fetch("/api/health")
    .then(response => response.json())
    .then(data => {
        document.getElementById("apiStatus").innerText = "ONLINE";
    })
    .catch(() => {
        document.getElementById("apiStatus").innerText = "OFFLINE";
    });
</script>

</body>
</html>
HTML

# ------------------------------------------------------------
# Login page
# ------------------------------------------------------------

cat >"${FRONTEND_DIR}/login.html" <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>

<meta charset="UTF-8">

<meta
    name="viewport"
    content="width=device-width, initial-scale=1"
>

<title>GrimVM Login</title>

<link
    rel="stylesheet"
    href="/css/grim.css"
>

</head>

<body>

<div class="center">

    <div class="login-card">

        <div class="brand large">
            GRIM<span>VM</span>
        </div>

        <h2>Sign in</h2>

        <p class="muted">
            Access your GrimVM account.
        </p>

        <input
            id="username"
            placeholder="Username"
        >

        <input
            id="password"
            type="password"
            placeholder="Password"
        >

        <button
            class="button primary full"
            onclick="login()"
        >
            Login
        </button>

        <p id="result"></p>

    </div>

</div>

<script>

async function login() {

    const username =
        document.getElementById("username").value;

    const password =
        document.getElementById("password").value;

    const response = await fetch(
        "/api/auth/login",
        {
            method: "POST",
            headers: {
                "Content-Type":
                    "application/json"
            },
            body: JSON.stringify({
                username,
                password
            })
        }
    );

    const data = await response.json();

    if (!response.ok) {
        document.getElementById(
            "result"
        ).innerText = data.detail;

        return;
    }

    localStorage.setItem(
        "grim_token",
        data.token
    );

    window.location =
        "/dashboard.html";
}

</script>

</body>
</html>
HTML

# ------------------------------------------------------------
# Dashboard
# ------------------------------------------------------------

cat >"${FRONTEND_DIR}/dashboard.html" <<'HTML'
<!DOCTYPE html>
<html lang="en">

<head>

<meta charset="UTF-8">

<meta
    name="viewport"
    content="width=device-width, initial-scale=1"
>

<title>GrimVM Dashboard</title>

<link
    rel="stylesheet"
    href="/css/grim.css"
>

</head>

<body>

<header class="topbar">

    <div class="brand">
        GRIM<span>VM</span>
    </div>

    <div>
        <span id="username"></span>

        <button
            class="small-button"
            onclick="logout()"
        >
            Logout
        </button>
    </div>

</header>

<div class="layout">

    <aside class="sidebar">

        <a class="active">Dashboard</a>
        <a>My VPS</a>
        <a>Console</a>
        <a>Backups</a>
        <a>Network</a>
        <a>Settings</a>

        <a
            id="adminLink"
            href="/admin.html"
            style="display:none"
        >
            Admin Panel
        </a>

    </aside>

    <main class="content">

        <div class="page-title">
            <h1>Dashboard</h1>
            <p>Manage your GrimVM resources.</p>
        </div>

        <section class="cards">

            <div class="card">
                <span>VPS</span>
                <strong id="vpsCount">0</strong>
            </div>

            <div class="card">
                <span>Rank</span>
                <strong id="rank">Newbie</strong>
            </div>

            <div class="card">
                <span>Status</span>
                <strong>Online</strong>
            </div>

        </section>

        <section class="panel">

            <div class="panel-header">
                <h2>My VPS</h2>
            </div>

            <div id="vpsList"></div>

        </section>

    </main>

</div>

<script src="/js/dashboard.js"></script>

</body>
</html>
HTML

# ------------------------------------------------------------
# Admin page
# ------------------------------------------------------------

cat >"${FRONTEND_DIR}/admin.html" <<'HTML'
<!DOCTYPE html>
<html lang="en">

<head>

<meta charset="UTF-8">

<meta
    name="viewport"
    content="width=device-width, initial-scale=1"
>

<title>GrimVM Admin</title>

<link
    rel="stylesheet"
    href="/css/grim.css"
>

</head>

<body>

<header class="topbar">

    <div class="brand">
        GRIM<span>VM</span>
    </div>

    <a href="/dashboard.html">
        Dashboard
    </a>

</header>

<div class="layout">

<aside class="sidebar">

    <a class="active">
        Admin Dashboard
    </a>

    <a>
        Users
    </a>

    <a>
        VPS
    </a>

    <a>
        Nodes
    </a>

    <a>
        Locations
    </a>

    <a>
        Eggs
    </a>

    <a>
        Mounts
    </a>

    <a>
        Backups
    </a>

    <a>
        Extensions
    </a>

    <a>
        Security
    </a>

    <a>
        Ranks
    </a>

    <a>
        Audit Logs
    </a>

    <a>
        Settings
    </a>

</aside>

<main class="content">

    <div class="page-title">

        <h1>Admin Panel</h1>

        <p>
            Control GrimVM nodes, users and VPS.
        </p>

    </div>

    <section class="cards">

        <div class="card">
            <span>Users</span>
            <strong id="usersCount">0</strong>
        </div>

        <div class="card">
            <span>VPS</span>
            <strong id="vpsCount">0</strong>
        </div>

        <div class="card">
            <span>Node</span>
            <strong>ONLINE</strong>
        </div>

    </section>

    <section class="panel">

        <div class="panel-header">

            <h2>Create VPS</h2>

        </div>

        <div class="form-grid">

            <input
                id="owner"
                placeholder="Owner User ID"
            >

            <input
                id="name"
                placeholder="VPS Name"
            >

            <select id="image">

                <option value="ubuntu:24.04">
                    Ubuntu 24.04
                </option>

                <option value="ubuntu:22.04">
                    Ubuntu 22.04
                </option>

                <option value="debian:13">
                    Debian 13
                </option>

                <option value="debian:12">
                    Debian 12
                </option>

                <option value="alpine:latest">
                    Alpine
                </option>

            </select>

            <input
                id="cpu"
                type="number"
                value="1"
                min="1"
                max="32"
                placeholder="CPU"
            >

            <input
                id="ram"
                type="number"
                value="1024"
                min="256"
                placeholder="RAM MB"
            >

            <input
                id="disk"
                type="number"
                value="10"
                min="1"
                placeholder="Disk GB"
            >

        </div>

        <button
            class="button primary"
            onclick="createVPS()"
        >
            Create VPS
        </button>

        <p id="createResult"></p>

    </section>

    <section class="panel">

        <div class="panel-header">
            <h2>Users</h2>
        </div>

        <div id="usersList"></div>

    </section>

    <section class="panel">

        <div class="panel-header">
            <h2>VPS</h2>
        </div>

        <div id="vpsList"></div>

    </section>

</main>

</div>

<script>

const token =
    localStorage.getItem("grim_token");

if (!token) {
    window.location =
        "/login.html";
}

const headers = {
    "Authorization":
        "Bearer " + token
};

async function verifyAdmin() {

    const response = await fetch(
        "/api/me",
        { headers }
    );

    if (!response.ok) {
        window.location =
            "/login.html";

        return;
    }

    const user =
        await response.json();

    if (user.role !== "admin") {
        window.location =
            "/dashboard.html";
    }
}

async function loadUsers() {

    const response = await fetch(
        "/api/admin/users",
        { headers }
    );

    if (!response.ok) return;

    const users =
        await response.json();

    document.getElementById(
        "usersCount"
    ).innerText = users.length;

    const box =
        document.getElementById(
            "usersList"
        );

    box.innerHTML = "";

    users.forEach(user => {

        const row =
            document.createElement("div");

        row.className = "list-row";

        row.innerHTML = `
            <div>
                <strong>${user.username}</strong>
                <span>
                    ID ${user.id} •
                    ${user.rank} •
                    ${user.email}
                </span>
            </div>

            <button
                class="small-button"
                onclick="toggleBan(${user.id}, ${user.banned})"
            >
                ${user.banned ? "Unban" : "Ban"}
            </button>
        `;

        box.appendChild(row);

    });
}

async function toggleBan(id, banned) {

    const route =
        banned
        ? `/api/admin/users/${id}/unban`
        : `/api/admin/users/${id}/ban`;

    await fetch(
        route,
        {
            method: "POST",
            headers
        }
    );

    loadUsers();
}

async function loadVPS() {

    const response = await fetch(
        "/api/vps",
        { headers }
    );

    if (!response.ok) return;

    const vps =
        await response.json();

    document.getElementById(
        "vpsCount"
    ).innerText = vps.length;

    const box =
        document.getElementById(
            "vpsList"
        );

    box.innerHTML = "";

    vps.forEach(item => {

        const row =
            document.createElement("div");

        row.className = "list-row";

        row.innerHTML = `
            <div>
                <strong>${item.name}</strong>
                <span>
                    ID ${item.id} •
                    Owner ${item.owner_id} •
                    ${item.status}
                </span>
            </div>

            <button
                class="small-button danger"
                onclick="deleteVPS(${item.id})"
            >
                Delete
            </button>
        `;

        box.appendChild(row);

    });
}

async function createVPS() {

    const result =
        document.getElementById(
            "createResult"
        );

    const body = {
        owner_id: Number(
            document.getElementById(
                "owner"
            ).value
        ),

        name:
            document.getElementById(
                "name"
            ).value,

        image:
            document.getElementById(
                "image"
            ).value,

        cpu: Number(
            document.getElementById(
                "cpu"
            ).value
        ),

        ram_mb: Number(
            document.getElementById(
                "ram"
            ).value
        ),

        disk_gb: Number(
            document.getElementById(
                "disk"
            ).value
        )
    };

    const response = await fetch(
        "/api/admin/vps",
        {
            method: "POST",

            headers: {
                ...headers,
                "Content-Type":
                    "application/json"
            },

            body: JSON.stringify(body)
        }
    );

    const data =
        await response.json();

    if (!response.ok) {
        result.innerText =
            data.detail || "Failed";

        return;
    }

    result.innerText =
        "VPS created successfully.";

    loadVPS();
}

async function deleteVPS(id) {

    if (
        !confirm(
            "Delete this VPS?"
        )
    ) return;

    await fetch(
        `/api/admin/vps/${id}`,
        {
            method: "DELETE",
            headers
        }
    );

    loadVPS();
}

verifyAdmin();
loadUsers();
loadVPS();

</script>

</body>
</html>
HTML

# ------------------------------------------------------------
# Dashboard JS
# ------------------------------------------------------------

cat >"${FRONTEND_DIR}/js/dashboard.js" <<'JS'
const token =
    localStorage.getItem("grim_token");

if (!token) {
    window.location =
        "/login.html";
}

const headers = {
    "Authorization":
        "Bearer " + token
};

async function loadDashboard() {

    const meResponse =
        await fetch(
            "/api/me",
            { headers }
        );

    if (!meResponse.ok) {
        logout();
        return;
    }

    const me =
        await meResponse.json();

    document.getElementById(
        "username"
    ).innerText =
        me.username;

    document.getElementById(
        "rank"
    ).innerText =
        me.rank;

    if (me.role === "admin") {
        document.getElementById(
            "adminLink"
        ).style.display =
            "block";
    }

    const vpsResponse =
        await fetch(
            "/api/vps",
            { headers }
        );

    const vps =
        await vpsResponse.json();

    document.getElementById(
        "vpsCount"
    ).innerText =
        vps.length;

    const box =
        document.getElementById(
            "vpsList"
        );

    box.innerHTML = "";

    if (vps.length === 0) {

        box.innerHTML = `
            <div class="empty">
                No VPS has been assigned
                to your account yet.
            </div>
        `;

        return;
    }

    vps.forEach(item => {

        const row =
            document.createElement(
                "div"
            );

        row.className =
            "list-row";

        row.innerHTML = `
            <div>
                <strong>
                    ${item.name}
                </strong>

                <span>
                    ${item.image}
                    • ${item.cpu} CPU
                    • ${item.ram_mb} MB RAM
                    • ${item.status}
                </span>
            </div>

            <div class="button-group">

                <button
                    class="small-button"
                    onclick="vpsAction(${item.id}, 'start')"
                >
                    Start
                </button>

                <button
                    class="small-button"
                    onclick="vpsAction(${item.id}, 'stop')"
                >
                    Stop
                </button>

                <button
                    class="small-button"
                    onclick="vpsAction(${item.id}, 'restart')"
                >
                    Restart
                </button>

            </div>
        `;

        box.appendChild(row);

    });
}

async function vpsAction(id, action) {

    await fetch(
        `/api/vps/${id}/${action}`,
        {
            method: "POST",
            headers
        }
    );

    loadDashboard();
}

function logout() {

    localStorage.removeItem(
        "grim_token"
    );

    window.location =
        "/login.html";
}

loadDashboard();
JS

# ------------------------------------------------------------
# CSS
# ------------------------------------------------------------

cat >"${FRONTEND_DIR}/css/grim.css" <<'CSS'
:root {
    --bg: #08090d;
    --panel: #11131a;
    --panel2: #171a23;
    --border: #262a35;
    --text: #f1f3f7;
    --muted: #8b92a3;
    --accent: #ffffff;
    --danger: #ff4d67;
}

* {
    box-sizing: border-box;
}

body {
    margin: 0;
    background: var(--bg);
    color: var(--text);
    font-family:
        Inter,
        Arial,
        Helvetica,
        sans-serif;
}

a {
    color: inherit;
    text-decoration: none;
}

.navbar,
.topbar {
    height: 72px;
    padding: 0 30px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    border-bottom: 1px solid var(--border);
    background: rgba(8, 9, 13, .95);
}

.brand {
    font-size: 23px;
    font-weight: 900;
    letter-spacing: -1px;
}

.brand span {
    color: #8f96a7;
}

.brand.large {
    font-size: 30px;
    margin-bottom: 20px;
}

.navbar a {
    margin-left: 24px;
    color: var(--muted);
}

.hero {
    max-width: 1100px;
    margin: 70px auto;
    padding: 20px;
}

.hero-card {
    background:
        linear-gradient(
            145deg,
            #151821,
            #0c0e13
        );

    border: 1px solid var(--border);

    border-radius: 24px;

    padding: 70px;
}

.badge {
    display: inline-block;
    border: 1px solid var(--border);
    color: var(--muted);
    padding: 8px 12px;
    border-radius: 999px;
    font-size: 12px;
}

.hero h1 {
    font-size: 62px;
    line-height: 1;
    letter-spacing: -4px;
    margin: 25px 0;
}

.hero h1 span {
    color: var(--muted);
}

.hero p {
    max-width: 650px;
    font-size: 18px;
    color: var(--muted);
    line-height: 1.7;
}

.actions {
    margin-top: 30px;
}

.button {
    border: 0;
    border-radius: 12px;
    padding: 13px 18px;
    font-weight: 700;
    cursor: pointer;
}

.button.primary {
    background: var(--accent);
    color: #08090d;
}

.button.full {
    width: 100%;
}

.stats {
    display: grid;
    grid-template-columns:
        repeat(4, 1fr);
    gap: 15px;
    margin-top: 20px;
}

.stat {
    background: var(--panel);
    border: 1px solid var(--border);
    padding: 20px;
    border-radius: 16px;
}

.stat strong {
    display: block;
    font-size: 20px;
}

.stat span {
    color: var(--muted);
    font-size: 13px;
}

.center {
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 20px;
}

.login-card {
    width: 420px;
    max-width: 100%;
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 20px;
    padding: 35px;
}

.login-card h2 {
    margin-bottom: 6px;
}

.muted {
    color: var(--muted);
}

input,
select {
    width: 100%;
    background: var(--panel2);
    color: var(--text);
    border: 1px solid var(--border);
    padding: 13px;
    border-radius: 10px;
    margin-bottom: 12px;
    outline: none;
}

.layout {
    display: grid;
    grid-template-columns: 230px 1fr;
    min-height: calc(100vh - 72px);
}

.sidebar {
    border-right: 1px solid var(--border);
    padding: 22px 15px;
    background: #0b0d12;
}

.sidebar a {
    display: block;
    padding: 12px;
    margin-bottom: 3px;
    color: var(--muted);
    border-radius: 9px;
}

.sidebar a:hover,
.sidebar a.active {
    background: var(--panel2);
    color: var(--text);
}

.content {
    padding: 30px;
    max-width: 1400px;
    width: 100%;
}

.page-title {
    margin-bottom: 28px;
}

.page-title h1 {
    margin: 0;
    font-size: 34px;
}

.page-title p {
    color: var(--muted);
}

.cards {
    display: grid;
    grid-template-columns:
        repeat(3, 1fr);
    gap: 15px;
    margin-bottom: 20px;
}

.card,
.panel {
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 16px;
}

.card {
    padding: 22px;
}

.card span {
    color: var(--muted);
    display: block;
}

.card strong {
    font-size: 28px;
    margin-top: 8px;
    display: block;
}

.panel {
    padding: 20px;
    margin-bottom: 20px;
}

.panel-header {
    margin-bottom: 18px;
    display: flex;
    justify-content: space-between;
}

.panel-header h2 {
    margin: 0;
}

.list-row {
    padding: 16px;
    border-top: 1px solid var(--border);
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 20px;
}

.list-row strong,
.list-row span {
    display: block;
}

.list-row span {
    color: var(--muted);
    font-size: 13px;
    margin-top: 5px;
}

.button-group {
    display: flex;
    gap: 6px;
}

.small-button {
    background: var(--panel2);
    border: 1px solid var(--border);
    color: var(--text);
    padding: 8px 11px;
    border-radius: 8px;
    cursor: pointer;
}

.small-button.danger {
    color: var(--danger);
}

.empty {
    color: var(--muted);
    padding: 30px;
    text-align: center;
}

.form-grid {
    display: grid;
    grid-template-columns:
        repeat(2, 1fr);
    gap: 10px;
}

@media (max-width: 800px) {

    .layout {
        grid-template-columns: 1fr;
    }

    .sidebar {
        display: none;
    }

    .hero-card {
        padding: 35px;
    }

    .hero h1 {
        font-size: 42px;
    }

    .stats,
    .cards {
        grid-template-columns: 1fr;
    }

    .form-grid {
        grid-template-columns: 1fr;
    }

    .content {
        padding: 18px;
    }

}
CSS

# ------------------------------------------------------------
# Dockerfiles
# ------------------------------------------------------------

cat >"${DOCKER_DIR}/ubuntu/Dockerfile" <<'EOF'
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y \
        bash \
        curl \
        wget \
        sudo \
        nano \
        vim \
        iproute2 \
        iputils-ping \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

CMD ["/bin/bash", "-c", "while true; do sleep 3600; done"]
EOF

cat >"${DOCKER_DIR}/debian/Dockerfile" <<'EOF'
FROM debian:13

RUN apt-get update \
    && apt-get install -y \
        bash \
        curl \
        wget \
        sudo \
        nano \
        vim \
        iproute2 \
        iputils-ping \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

CMD ["/bin/bash", "-c", "while true; do sleep 3600; done"]
EOF

# ------------------------------------------------------------
# Nginx configuration
# ------------------------------------------------------------

cat >"${NGINX_DIR}/grimvm.conf" <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name ${GRIM_DOMAIN};

    root ${FRONTEND_DIR};
    index index.html;

    client_max_body_size 512M;

    location /api/ {
        proxy_pass http://127.0.0.1:8000;

        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default

ln -sf \
    "${NGINX_DIR}/grimvm.conf" \
    /etc/nginx/sites-enabled/grimvm.conf

nginx -t

systemctl enable nginx
systemctl restart nginx

# ------------------------------------------------------------
# Systemd service
# ------------------------------------------------------------

cat >"${SERVICE_FILE}" <<EOF
[Unit]
Description=GrimVM Backend
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=simple
WorkingDirectory=${BACKEND_DIR}

EnvironmentFile=${ENV_FILE}

ExecStart=${BACKEND_DIR}/venv/bin/uvicorn app:app --host 127.0.0.1 --port 8000

Restart=always
RestartSec=5

NoNewPrivileges=false

[Install]
WantedBy=multi-user.target
EOF

# ------------------------------------------------------------
# Prepare database & admin
# ------------------------------------------------------------

log "Creating GrimVM database tables..."

pushd "${BACKEND_DIR}" >/dev/null

set -a
source "${ENV_FILE}"
set +a

"${BACKEND_DIR}/venv/bin/python" bootstrap_admin.py

popd >/dev/null

# ------------------------------------------------------------
# Systemd
# ------------------------------------------------------------

systemctl daemon-reload

systemctl enable grimvm

systemctl restart grimvm

sleep 3

# ------------------------------------------------------------
# HTTPS
# ------------------------------------------------------------

if [[ "${GRIM_DOMAIN}" != "localhost" ]]; then

    echo
    read -r -p \
        "Attempt automatic Let's Encrypt HTTPS setup for ${GRIM_DOMAIN}? [Y/n]: " \
        ENABLE_SSL

    ENABLE_SSL="${ENABLE_SSL:-Y}"

    if [[ "${ENABLE_SSL}" =~ ^[Yy]$ ]]; then

        if [[ -z "${ADMIN_EMAIL:-}" ]]; then
            warn "No admin email supplied; skipping SSL."
        else

            log "Requesting Let's Encrypt certificate..."

            if certbot \
                --nginx \
                --non-interactive \
                --agree-tos \
                --redirect \
                --email "${ADMIN_EMAIL}" \
                -d "${GRIM_DOMAIN}"; then

                log "HTTPS certificate installed successfully."

            else
                warn "Certbot failed. GrimVM is still available over HTTP."
                warn "Make sure DNS points ${GRIM_DOMAIN} to this server and run:"
                warn "sudo certbot --nginx -d ${GRIM_DOMAIN}"
            fi

        fi

    fi

else
    warn "Domain is localhost; HTTPS certificate was skipped."
fi

# ------------------------------------------------------------
# Firewall
# ------------------------------------------------------------

log "Configuring basic firewall..."

ufw allow OpenSSH >/dev/null 2>&1 || true
ufw allow 80/tcp >/dev/null 2>&1 || true
ufw allow 443/tcp >/dev/null 2>&1 || true

echo "y" | ufw enable >/dev/null 2>&1 || true

# ------------------------------------------------------------
# Final health test
# ------------------------------------------------------------

sleep 2

if curl -fsS http://127.0.0.1:8000/api/health >/dev/null; then
    log "Backend health check: OK"
else
    error "Backend health check failed."
    journalctl -u grimvm --no-pager -n 100 || true
    exit 1
fi

# ------------------------------------------------------------
# Finished
# ------------------------------------------------------------

IP_ADDRESS="$(
    hostname -I 2>/dev/null \
    | awk '{print $1}'
)"

echo
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}                  GRIMVM INSTALLED                         ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo
echo "Version       : ${GRIM_VERSION}"
echo "Author        : Vasplayz90 • ArizNodes Team"
echo "Install       : ${INSTALL_DIR}"
echo "Domain        : ${GRIM_DOMAIN}"
echo "Admin user    : ${ADMIN_USERNAME}"
echo
echo "Panel:"
echo "  http://${GRIM_DOMAIN}"
echo
if [[ "${GRIM_DOMAIN}" == "localhost" ]]; then
    echo "Local:"
    echo "  http://127.0.0.1"
else
    echo "Server IP:"
    echo "  http://${IP_ADDRESS}"
fi
echo
echo "Services:"
echo "  Docker      : $(systemctl is-active docker || true)"
echo "  Nginx       : $(systemctl is-active nginx || true)"
echo "  GrimVM API  : $(systemctl is-active grimvm || true)"
echo "  MySQL       : $(docker inspect -f '{{.State.Status}}' grimvm_mysql 2>/dev/null || true)"
echo
echo "Useful commands:"
echo "  systemctl status grimvm"
echo "  journalctl -u grimvm -f"
echo "  systemctl restart grimvm"
echo "  docker ps"
echo "  docker network inspect ${GRIM_VPS_NETWORK}"
echo
echo -e "${GREEN}Installation complete.${NC}"
