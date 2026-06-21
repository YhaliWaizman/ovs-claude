#!/bin/bash
# Linux systemd setup for autonomous agent runner
# Usage: bash scripts/linux/install.sh

set -e

# ─── Detect paths ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOME_DIR="$HOME"
CONFIG_DIR="$HOME_DIR/.config/systemd/user"

echo "[setup] Repository path: $REPO"
echo "[setup] Config path: $CONFIG_DIR"
echo "[setup] User: $(whoami)"

# ─── Verify prerequisites ─────────────────────────────────────────────────────

if [[ ! -f "$REPO/pc-server/dist/index.js" ]]; then
  echo "[setup] ✗ pc-server not built. Run: cd pc-server && npm install && npm run build"
  exit 1
fi

if [[ ! -f "$REPO/bot/dist/index.js" ]]; then
  echo "[setup] ✗ bot not built. Run: cd bot && npm install && npm run build"
  exit 1
fi

if [[ ! -f "$REPO/bot/.env" ]]; then
  echo "[setup] ✗ bot/.env not found. Create it with TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID"
  exit 1
fi

# ─── Create systemd config directory ───────────────────────────────────────────

mkdir -p "$CONFIG_DIR"

# ─── Generate and install unit files with actual paths ───────────────────────

echo "[setup] Installing systemd units..."

# Helper function to install a unit with path substitution
install_unit() {
  local template="$1"
  local target="$2"
  local name=$(basename "$target")
  
  sed "s|%REPO%|$REPO|g; s|%HOME%|$HOME_DIR|g" "$template" > "$target"
  echo "[setup]   ✓ $name"
}

install_unit "$SCRIPT_DIR/pc-server.service" "$CONFIG_DIR/pc-server.service"
install_unit "$SCRIPT_DIR/bot.service" "$CONFIG_DIR/bot.service"
install_unit "$SCRIPT_DIR/session-trigger.service" "$CONFIG_DIR/session-trigger.service"
install_unit "$SCRIPT_DIR/session-trigger.timer" "$CONFIG_DIR/session-trigger.timer"

# ─── Reload and enable ─────────────────────────────────────────────────────────

echo "[setup] Reloading systemd..."
systemctl --user daemon-reload

echo "[setup] Enabling services..."
systemctl --user enable pc-server.service
systemctl --user enable bot.service
systemctl --user enable session-trigger.timer

echo "[setup] Starting services..."
systemctl --user start pc-server.service
systemctl --user start bot.service
systemctl --user start session-trigger.timer

# ─── Enable lingering so services run while you're logged off ─────────────────

echo "[setup] Enabling lingering (services run while logged off)..."
loginctl enable-linger

# ─── Status ───────────────────────────────────────────────────────────────────

echo ""
echo "[setup] ✓ Setup complete!"
echo ""
echo "Service status:"
systemctl --user status pc-server.service --no-pager || true
systemctl --user status bot.service --no-pager || true
systemctl --user list-timers session-trigger.timer --no-pager || true
echo ""
echo "View logs: journalctl --user -u pc-server -f"
echo "View logs: journalctl --user -u bot -f"
