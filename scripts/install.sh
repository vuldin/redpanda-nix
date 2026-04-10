#!/usr/bin/env bash
# Install Redpanda from a Nix build on any Linux system with systemd.
#
# Usage:
#   sudo ./scripts/install.sh                    # build + install default variant
#   sudo ./scripts/install.sh --variant fips     # build + install FIPS variant
#   sudo ./scripts/install.sh /nix/store/...     # install from an explicit store path
#
# Variants:
#   redpanda  (default)  Official pre-built binary from Cloudsmith deb
#   fips                 Base binary + FIPS 140-2 OpenSSL (BoringCrypto)
#
# Idempotent — safe to re-run after a rebuild to upgrade in place.

set -euo pipefail

# --- Pre-flight checks -------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
  echo "Error: this script must be run as root (use sudo)." >&2
  exit 1
fi

if ! command -v systemctl &>/dev/null; then
  echo "Error: systemd is required. This script does not support non-systemd init systems." >&2
  exit 1
fi

# sudo strips PATH, so nix may not be found. Check standard install locations.
if ! command -v nix &>/dev/null; then
  for p in /nix/var/nix/profiles/default/bin /run/current-system/sw/bin /home/*/.nix-profile/bin; do
    if [[ -x "$p/nix" ]]; then
      export PATH="$p:$PATH"
      break
    fi
  done
fi

# --- Parse arguments ----------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VARIANT=""
STORE_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --variant)
      VARIANT="$2"
      shift 2
      ;;
    --variant=*)
      VARIANT="${1#*=}"
      shift
      ;;
    /*)
      STORE_PATH="$1"
      shift
      ;;
    *)
      echo "Error: unknown argument '$1'" >&2
      echo "Usage: sudo ./scripts/install.sh [--variant <name>] [/nix/store/path]" >&2
      exit 1
      ;;
  esac
done

# --- Resolve store path -------------------------------------------------------

if [[ -n "$STORE_PATH" ]]; then
  # Explicit path given — use it directly
  :
elif [[ -n "$VARIANT" ]]; then
  # Map short names to flake package names
  case "$VARIANT" in
    redpanda|default)  FLAKE_PKG="redpanda" ;;
    fips)              FLAKE_PKG="redpanda-fips" ;;
    *)
      echo "Error: unknown variant '$VARIANT'" >&2
      echo "Valid variants: redpanda (default), fips" >&2
      exit 1
      ;;
  esac

  NIX_FLAGS="--extra-experimental-features nix-command --extra-experimental-features flakes"
  echo "Building .#$FLAKE_PKG..."
  if ! nix $NIX_FLAGS build "$PROJECT_DIR#$FLAKE_PKG" --out-link "$PROJECT_DIR/result" 2>&1; then
    echo "Error: nix build failed." >&2
    exit 1
  fi
  STORE_PATH="$(readlink -f "$PROJECT_DIR/result")"
else
  # No args — use existing result symlink
  if [[ ! -L "$PROJECT_DIR/result" ]]; then
    NIX_FLAGS="--extra-experimental-features nix-command --extra-experimental-features flakes"
    echo "No result symlink found. Building default package..."
    if ! nix $NIX_FLAGS build "$PROJECT_DIR" --out-link "$PROJECT_DIR/result" 2>&1; then
      echo "Error: nix build failed." >&2
      exit 1
    fi
  fi
  STORE_PATH="$(readlink -f "$PROJECT_DIR/result")"
fi

if [[ ! -x "$STORE_PATH/bin/redpanda" ]]; then
  echo "Error: $STORE_PATH/bin/redpanda not found or not executable." >&2
  exit 1
fi

VERSION=$("$STORE_PATH/bin/redpanda" --version 2>&1 | head -1 || echo "unknown")
echo "Installing Redpanda ($VERSION) from $STORE_PATH"

# --- User and group -----------------------------------------------------------

if ! getent group redpanda &>/dev/null; then
  echo "Creating group 'redpanda'..."
  groupadd --system redpanda
fi

if ! id redpanda &>/dev/null; then
  echo "Creating user 'redpanda'..."
  useradd --system --gid redpanda --home-dir /var/lib/redpanda \
    --create-home --shell /usr/sbin/nologin redpanda
fi

# --- Directories --------------------------------------------------------------

echo "Setting up directories..."
mkdir -p /var/lib/redpanda/data
mkdir -p /etc/redpanda
chown -R redpanda:redpanda /var/lib/redpanda
chmod 0750 /var/lib/redpanda

# --- Binary symlink -----------------------------------------------------------

echo "Linking binary to /usr/local/bin/redpanda..."
ln -sf "$STORE_PATH/bin/redpanda" /usr/local/bin/redpanda

# --- Default configuration ----------------------------------------------------

if [[ ! -f /etc/redpanda/redpanda.yaml ]]; then
  echo "Creating default configuration at /etc/redpanda/redpanda.yaml..."
  cat > /etc/redpanda/redpanda.yaml <<'YAML'
# Default Redpanda configuration (single-node, developer mode)
# Edit this file to customize. See: https://docs.redpanda.com/

redpanda:
  data_directory: /var/lib/redpanda/data
  node_id: 0
  developer_mode: true

  rpc_server:
    address: 0.0.0.0
    port: 33145

  kafka_api:
    - address: 0.0.0.0
      port: 9092

  advertised_kafka_api:
    - address: 127.0.0.1
      port: 9092

  admin:
    - address: 0.0.0.0
      port: 9644

  advertised_rpc_api:
    address: 127.0.0.1
    port: 33145

  auto_create_topics_enabled: true

schema_registry:
  schema_registry_api:
    - address: 0.0.0.0
      port: 8081

pandaproxy:
  pandaproxy_api:
    - address: 0.0.0.0
      port: 8082

rpk:
  overprovisioned: true
  coredump_dir: /var/lib/redpanda/coredump
YAML
  chown redpanda:redpanda /etc/redpanda/redpanda.yaml
else
  echo "Configuration already exists at /etc/redpanda/redpanda.yaml (keeping it)."
fi

# --- systemd service ----------------------------------------------------------

echo "Installing systemd service..."
cat > /etc/systemd/system/redpanda.service <<EOF
[Unit]
Description=Redpanda
Documentation=https://docs.redpanda.com/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=redpanda
Group=redpanda
ExecStart=/usr/local/bin/redpanda --redpanda-cfg /etc/redpanda/redpanda.yaml --default-log-level=info

NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictSUIDSGID=true
ReadWritePaths=/var/lib/redpanda

LimitNOFILE=800000
LimitNPROC=8096
LimitMEMLOCK=infinity

Restart=on-failure
RestartSec=10s
OOMScoreAdjust=-950

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# --- Start / restart ----------------------------------------------------------

if systemctl is-active --quiet redpanda; then
  echo "Restarting Redpanda..."
  systemctl restart redpanda
else
  echo "Starting Redpanda..."
  systemctl enable --now redpanda
fi

sleep 3

if systemctl is-active --quiet redpanda; then
  echo ""
  echo "Redpanda is running."
  echo ""
  echo "Listeners:"
  ss -tlnp | grep -E '9092|9644|8081|8082|33145' | awk '{print "  " $4}' || true
  echo ""
  echo "Useful commands:"
  echo "  systemctl status redpanda"
  echo "  journalctl -u redpanda -f"
  echo "  sudo ./scripts/uninstall.sh"
else
  echo ""
  echo "Warning: Redpanda failed to start. Check logs:"
  echo "  journalctl -u redpanda -n 30 --no-pager"
  exit 1
fi
