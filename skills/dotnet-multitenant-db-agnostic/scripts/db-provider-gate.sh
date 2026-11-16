#!/usr/bin/env bash
# Fails when database-provider-specific code appears outside the provider layer / migrations.
# Usage: scripts/db-provider-gate.sh [repo-root]
# Adapt SRC_DIR, the provider-folder glob and the pattern list to your solution.
set -euo pipefail

ROOT_DIR="${1:-$(pwd)}"
SRC_DIR="$ROOT_DIR/backend/src"
ALLOWLIST="$ROOT_DIR/scripts/db-provider-gate.allow"   # optional: one relative path per line
VIOLATIONS="$(mktemp)"
trap 'rm -f "$VIOLATIONS"' EXIT

patterns=(
  'Oracle\.ManagedDataAccess' 'OracleException' 'OracleParameter' 'Npgsql' 'SqlClient'
  'UseOracle' 'UseNpgsql' 'UseSqlServer' 'UseIdentityColumn'
  'SYSDATE' 'FROM[[:space:]]+DUAL' 'GETDATE\(' 'NOW\(\)'
  'HasColumnType\([[:space:]]*"(NVARCHAR2|CLOB|BLOB|bytea|text|nvarchar\(max\))"'
  ':[A-Za-z_][A-Za-z0-9_]*(Id|Name|Size|Value)\b'      # Oracle-style bind parameters in raw SQL
)

args=()
for p in "${patterns[@]}"; do args+=(-e "$p"); done

while IFS= read -r hit; do
  file=${hit%%:*}
  rel=${file#"$ROOT_DIR/"}
  case "$rel" in
    */Migrations/*|*.Migrations.*/*|*/Data/Providers/*) continue ;;   # the only places DB-specific code may live
  esac
  if [[ -f $ALLOWLIST ]] && grep -Fxq "$rel" "$ALLOWLIST"; then continue; fi
  printf '%s\n' "$hit" >> "$VIOLATIONS"
done < <(grep -REn --include='*.cs' "${args[@]}" "$SRC_DIR" || true)

if [[ -s $VIOLATIONS ]]; then
  echo "DB provider gate: move DB-specific code into the provider layer (*/Data/Providers/)" >&2
  sort -u "$VIOLATIONS" >&2
  exit 1
fi
echo "DB provider gate passed."
