#!/usr/bin/env bash
# Uninstall Redpanda from a non-NixOS Linux system.
# Usage: sudo ./scripts/uninstall.sh [--purge]
#
# Without --purge: stops service, removes binary symlink and systemd unit.
# With    --purge: also removes config (/etc/redpanda), data (/var/lib/redpanda),
#                  and the redpanda user/group.

set -euo pipefail

PURGE=false
if [[ "${1:-}" == "--purge" ]]; then
  PURGE=true
fi

if [[ $EUID -ne 0 ]]; then
  echo "Error: this script must be run as root (use sudo)." >&2
  exit 1
fi

# --- Stop service -------------------------------------------------------------

if systemctl is-active --quiet redpanda 2>/dev/null; then
  echo "Stopping Redpanda..."
  systemctl stop redpanda
fi

if systemctl is-enabled --quiet redpanda 2>/dev/null; then
  echo "Disabling Redpanda service..."
  systemctl disable redpanda
fi

# --- Remove systemd unit ------------------------------------------------------

if [[ -f /etc/systemd/system/redpanda.service ]]; then
  echo "Removing systemd service..."
  rm -f /etc/systemd/system/redpanda.service
  systemctl daemon-reload
fi

# --- Remove binary symlink ----------------------------------------------------

if [[ -L /usr/local/bin/redpanda ]]; then
  echo "Removing /usr/local/bin/redpanda symlink..."
  rm -f /usr/local/bin/redpanda
fi

# --- Purge (optional) ---------------------------------------------------------

if $PURGE; then
  echo "Purging configuration and data..."

  if [[ -d /etc/redpanda ]]; then
    echo "  Removing /etc/redpanda/"
    rm -rf /etc/redpanda
  fi

  if [[ -d /var/lib/redpanda ]]; then
    echo "  Removing /var/lib/redpanda/"
    rm -rf /var/lib/redpanda
  fi

  if id redpanda &>/dev/null; then
    echo "  Removing user 'redpanda'..."
    userdel redpanda 2>/dev/null || true
  fi

  if getent group redpanda &>/dev/null; then
    echo "  Removing group 'redpanda'..."
    groupdel redpanda 2>/dev/null || true
  fi

  echo "Purge complete."
else
  echo ""
  echo "Configuration and data preserved:"
  echo "  /etc/redpanda/redpanda.yaml"
  echo "  /var/lib/redpanda/"
  echo ""
  echo "To also remove config, data, and the redpanda user:"
  echo "  sudo ./scripts/uninstall.sh --purge"
fi

echo ""
echo "Redpanda has been uninstalled."
