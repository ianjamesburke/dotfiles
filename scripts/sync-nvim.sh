#!/bin/bash
# Sync Neovim configuration from a remote machine via SCP.
# Usage: ./sync-nvim.sh <user@host>
# Example: ./sync-nvim.sh ian@192.168.1.10

set -euo pipefail

if [[ -z "${1:-}" ]]; then
  echo "Usage: $0 <user@host>"
  echo "Example: $0 ian@10.0.0.2"
  exit 1
fi

REMOTE="${1}"
REMOTE_PATH="/Users/$(echo "$REMOTE" | cut -d@ -f1)/.config/nvim"
NVIM_CONFIG_DIR="$HOME/.config/nvim"
BACKUP_DIR="$HOME/.config/nvim.backup.$(date +%Y%m%d_%H%M%S)"

if [ -d "$NVIM_CONFIG_DIR" ]; then
  echo "Backing up existing nvim config to $BACKUP_DIR..."
  mv "$NVIM_CONFIG_DIR" "$BACKUP_DIR"
fi

echo "Copying nvim config from ${REMOTE}..."
if scp -r "${REMOTE}:${REMOTE_PATH}" "$HOME/.config/"; then
  echo "Neovim configuration synced successfully."
else
  echo "Error syncing. Check your SSH connection."
  if [ -d "$BACKUP_DIR" ] && [ ! -d "$NVIM_CONFIG_DIR" ]; then
    echo "Restoring backup..."
    mv "$BACKUP_DIR" "$NVIM_CONFIG_DIR"
  fi
  exit 1
fi
