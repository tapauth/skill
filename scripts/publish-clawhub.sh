#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# publish-clawhub.sh — Publish TapAuth skill to ClawHub (OpenClaw registry)
#
# Swaps SKILL-OPENCLAW.md → SKILL.md before publishing so OpenClaw agents
# get the secrets-manager-first documentation instead of the generic version.
#
# Usage:
#   bash scripts/publish-clawhub.sh [--dry-run]
#   bash scripts/publish-clawhub.sh --version 1.0.2
#   bash scripts/publish-clawhub.sh --version 1.0.2 --changelog "Fixed exec provider config"
###############################################################################

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Argument parsing --------------------------------------------------------
DRY_RUN="false"
VERSION=""
CHANGELOG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY_RUN="true"; shift ;;
    --version)
      [[ $# -lt 2 ]] && { echo "FATAL: --version requires a value"; exit 1; }
      VERSION="$2"; shift 2 ;;
    --changelog)
      [[ $# -lt 2 ]] && { echo "FATAL: --changelog requires a value"; exit 1; }
      CHANGELOG="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# --- Validate ----------------------------------------------------------------
if [[ ! -f "$SKILL_DIR/SKILL-OPENCLAW.md" ]]; then
  echo "FATAL: SKILL-OPENCLAW.md not found in $SKILL_DIR"
  exit 1
fi

if [[ ! -f "$SKILL_DIR/SKILL.md" ]]; then
  echo "FATAL: SKILL.md not found in $SKILL_DIR"
  exit 1
fi

if [[ ! -f "$SKILL_DIR/scripts/stage-clawhub.sh" ]]; then
  echo "FATAL: stage-clawhub.sh not found in $SKILL_DIR/scripts"
  exit 1
fi

if [[ ! -f "$SKILL_DIR/scripts/lint-clawhub-package.sh" ]]; then
  echo "FATAL: lint-clawhub-package.sh not found in $SKILL_DIR/scripts"
  exit 1
fi

if [[ "$DRY_RUN" != "true" ]] && ! command -v clawhub &>/dev/null; then
  echo "FATAL: clawhub CLI not found. Install it first."
  exit 1
fi

# --- Build staging directory -------------------------------------------------
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Staging skill for ClawHub..."
echo "  Source: $SKILL_DIR"
echo "  Staging: $TMP_DIR"

bash "$SKILL_DIR/scripts/stage-clawhub.sh" "$TMP_DIR"
bash "$SKILL_DIR/scripts/lint-clawhub-package.sh" "$TMP_DIR"
echo "  Prepared publish artifact"

# Verify the swap worked
if grep -q "OpenClaw Secrets Manager" "$TMP_DIR/SKILL.md"; then
  echo "  Verified: SKILL.md contains OpenClaw-specific content"
else
  echo "WARNING: SKILL.md may not contain expected OpenClaw content"
fi

# --- Publish or dry-run ------------------------------------------------------
if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo "[DRY RUN] Would publish to ClawHub:"
  echo "  Slug: tapauth"
  echo "  Version: ${VERSION:-<from skill.json>}"
  echo "  Files:"
  find "$TMP_DIR" -type f | sed "s|$TMP_DIR/||" | sort | sed 's/^/    /'
  echo ""
  echo "  SKILL.md first 5 lines:"
  head -5 "$TMP_DIR/SKILL.md" | sed 's/^/    /'
  echo ""
  echo "[DRY RUN] No changes made."
else
  echo ""
  echo "Publishing to ClawHub..."

  PUBLISH_ARGS=(clawhub publish "$TMP_DIR/" --slug tapauth --name "TapAuth")
  [[ -n "$VERSION" ]] && PUBLISH_ARGS+=(--version "$VERSION")
  [[ -n "$CHANGELOG" ]] && PUBLISH_ARGS+=(--changelog "$CHANGELOG")

  "${PUBLISH_ARGS[@]}"

  echo ""
  echo "Published to ClawHub."
fi
