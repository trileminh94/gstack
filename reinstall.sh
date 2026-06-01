#!/usr/bin/env bash
# Rebuild skill docs and reinstall to local Claude, Pi agent, and/or a remote host.
#
# Usage:
#   ./reinstall.sh                  # local Claude only
#   ./reinstall.sh --pi             # local Claude + Pi agent
#   ./reinstall.sh --pi-only        # Pi agent only (skip Claude)
#   ./reinstall.sh user@pi          # local + rsync to remote host (any user@host)
#   ./reinstall.sh --pi user@pi     # local + Pi + remote
#   ./reinstall.sh --remote-only user@pi  # skip local, remote only

set -e

GSTACK_DIR="$(cd "$(dirname "$0")" && pwd)"
REMOTE=""
LOCAL=1
PI=0

# Parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --remote-only) LOCAL=0; shift ;;
    --pi) PI=1; shift ;;
    --pi-only) PI=1; LOCAL=0; shift ;;
    -*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *) REMOTE="$1"; shift ;;
  esac
done

# ── 1. Regenerate skill docs from updated templates ──────────────────────────
echo "→ Regenerating skill docs..."
cd "$GSTACK_DIR"
bun run gen:skill-docs -q 2>/dev/null || bun run gen:skill-docs

# ── 2. Local install (Claude Code) ──────────────────────────────────────────
if [ "$LOCAL" -eq 1 ]; then
  CLAUDE_GSTACK="$HOME/.claude/skills/gstack"

  if [ -d "$CLAUDE_GSTACK" ] && [ ! -L "$CLAUDE_GSTACK" ]; then
    # Installed copy is a real directory (separate from this repo).
    # setup's symlink guard won't replace it — sync generated files directly.
    echo "→ Syncing SKILL.md files to $CLAUDE_GSTACK ..."
    rsync -a --include="*/" --include="SKILL.md" --include="sections/" --include="sections/*.md" \
      --exclude="*" "$GSTACK_DIR/" "$CLAUDE_GSTACK/"
    echo "✓ Local (Claude) install done. Skills live at $CLAUDE_GSTACK"
  else
    # ~/.claude/skills/gstack is a symlink to this repo — changes are already live.
    echo "→ Re-linking skills to ~/.claude/skills/ ..."
    "$GSTACK_DIR/setup" -q --no-plan-tune-hooks 2>/dev/null || "$GSTACK_DIR/setup" -q
    echo "✓ Local (Claude) install done. Skills live at ~/.claude/skills/"
  fi
fi

# ── 3. Pi agent install ────────────────────────────────────────────────────
if [ "$PI" -eq 1 ]; then
  PI_GSTACK="$HOME/.pi/agent/gstack-pi"

  if [ ! -d "$PI_GSTACK" ]; then
    echo "⚠ Pi agent gstack-pi directory not found at $PI_GSTACK"
    echo "  Install pi-gstack first with:   pi install npm:pi-gstack"
    echo "  Then run reinstall.sh again."
  else
    PI_REPO="$PI_GSTACK/repo"
    PI_SKILLS="$PI_GSTACK/skills"

    echo "→ Syncing repo to Pi agent at $PI_REPO ..."
    mkdir -p "$PI_REPO"
    rsync -az --delete \
      --exclude='.git' \
      --exclude='node_modules' \
      --exclude='browse/dist' \
      --exclude='design/dist' \
      --exclude='make-pdf/dist' \
      --exclude='.agents' \
      --exclude='.claude' \
      --exclude='.factory' \
      --exclude='.opencode' \
      --exclude='.kiro' \
      --exclude='.slate' \
      --exclude='.cursor' \
      --exclude='.codex' \
      --exclude='*.test.ts' \
      --exclude='test/' \
      "$GSTACK_DIR/" "$PI_REPO/"

    # Install bun dependencies so the pi adapter can run build/gen steps
    echo "→ Installing bun dependencies in Pi repo ..."
    (cd "$PI_REPO" && bun install --frozen-lockfile 2>/dev/null || bun install)

    # Force pi-gstack to regenerate skills by removing the metadata file.
    # The adapter checks .gstack-pi.json's adapterVersion — deleting it
    # guarantees regeneration on next Pi start or /gstack-sync.
    if [ -f "$PI_SKILLS/.gstack-pi.json" ]; then
      echo "→ Triggering skill regeneration for Pi ..."
      rm -f "$PI_SKILLS/.gstack-pi.json"
    fi

    echo "✓ Pi agent install done."
    echo "  Skills will regenerate on next Pi start (or run /gstack-sync inside Pi)"
  fi
fi

# ── 4. Remote install (SSH host) ─────────────────────────────────────────────
if [ -n "$REMOTE" ]; then
  REMOTE_DIR="${GSTACK_REMOTE_DIR:-~/gstack}"
  echo "→ Syncing to $REMOTE:$REMOTE_DIR ..."

  rsync -az --delete \
    --exclude='.git' \
    --exclude='node_modules' \
    --exclude='browse/dist' \
    --exclude='design/dist' \
    --exclude='make-pdf/dist' \
    --exclude='.agents' \
    --exclude='.factory' \
    --exclude='.opencode' \
    --exclude='*.test.ts' \
    --exclude='test/' \
    "$GSTACK_DIR/" "$REMOTE:$REMOTE_DIR/"

  echo "→ Running setup on $REMOTE ..."
  ssh "$REMOTE" "cd $REMOTE_DIR && (command -v bun >/dev/null 2>&1 || curl -fsSL https://bun.sh/install | bash -s -- --version 1.3.10) && bun install --frozen-lockfile 2>/dev/null || bun install && bun run build && ./setup -q --no-plan-tune-hooks"

  echo "✓ Remote install done on $REMOTE:$REMOTE_DIR"
fi
