#!/usr/bin/env bash
set -euo pipefail

PKG_DIR="${1:-}"

die() { echo "FATAL: $*" >&2; exit 1; }

[ -n "$PKG_DIR" ] || die "usage: bash scripts/lint-clawhub-package.sh <staged-package-dir>"
[ -d "$PKG_DIR" ] || die "directory not found: $PKG_DIR"

scan_markdown_file() {
  local file="$1"
  awk -v file="$file" '
    BEGIN { in_shell = 0; bad = 0 }
    /^```(bash|sh|shell)[[:space:]]*$/ { in_shell = 1; next }
    /^```/ { in_shell = 0; next }
    !in_shell { next }
    {
      if ($0 ~ /TOKEN=\$\(/) {
        print file ":" NR ": token capture into a shell variable is forbidden in the published OpenClaw package" > "/dev/stderr"
        bad = 1
        next
      }
      if ($0 ~ /\$\([^)]*(tapauth|scripts\/tapauth\.sh)[^)]*\)/) {
        print file ":" NR ": inline command substitution with TapAuth is forbidden in the published OpenClaw package" > "/dev/stderr"
        bad = 1
        next
      }
      if ($0 ~ /(^|[[:space:]])TAPAUTH_HOME=.*tapauth\.sh[[:space:]].*--token/ ||
          $0 ~ /(^|[[:space:]])(\/[^[:space:]]*tapauth\.sh|scripts\/tapauth\.sh|tapauth\.sh)[[:space:]].*--token/) {
        print file ":" NR ": direct shell execution of tapauth.sh --token is forbidden in the published OpenClaw package" > "/dev/stderr"
        bad = 1
      }
    }
    END { exit bad ? 1 : 0 }
  ' "$file"
}

exit_code=0

for file in "$PKG_DIR/README.md" "$PKG_DIR/SKILL.md" "$PKG_DIR"/references/*.md; do
  [ -f "$file" ] || continue
  scan_markdown_file "$file" || exit_code=1
done

if [ "$exit_code" -eq 0 ]; then
  echo "ClawHub package lint passed." >&2
else
  echo "ClawHub package lint failed." >&2
fi

exit "$exit_code"
