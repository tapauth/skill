#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_DIR="${1:-}"

die() { echo "FATAL: $*" >&2; exit 1; }

[ -n "$DEST_DIR" ] || die "usage: bash scripts/stage-clawhub.sh <dest-dir>"
[ "$DEST_DIR" != "/" ] || die "refusing to stage into /"
[ -f "$SKILL_DIR/SKILL.md" ] || die "SKILL.md not found in $SKILL_DIR"
[ -f "$SKILL_DIR/SKILL-OPENCLAW.md" ] || die "SKILL-OPENCLAW.md not found in $SKILL_DIR"

rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR"

# Publish the full package, then replace the generic skill instructions with
# the OpenClaw-specific variant that ClawHub users should receive.
cp -R "$SKILL_DIR"/* "$DEST_DIR/"
rm -f "$DEST_DIR/scripts/stage-clawhub.sh" "$DEST_DIR/scripts/lint-clawhub-package.sh"
cp "$DEST_DIR/SKILL-OPENCLAW.md" "$DEST_DIR/SKILL.md"
rm "$DEST_DIR/SKILL-OPENCLAW.md"

grep -q "OpenClaw Secrets Manager" "$DEST_DIR/SKILL.md" \
  || die "staged SKILL.md does not contain OpenClaw-specific content"
