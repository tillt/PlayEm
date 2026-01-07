#!/usr/bin/env bash
set -euo pipefail

# Run clang-format over Objective-C sources in the repo.
# Set CLANG_FORMAT_BIN to override the formatter executable path.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLANG_FORMAT_BIN="${CLANG_FORMAT_BIN:-clang-format}"

if ! command -v "$CLANG_FORMAT_BIN" >/dev/null 2>&1; then
    echo "clang-format not found. Set CLANG_FORMAT_BIN to a valid binary." >&2
    exit 1
fi

prune_dirs=(
    "$ROOT/.git"
    "$ROOT/DerivedData"
    "$ROOT/ThirdParty"
    "$ROOT/dmg"
)

prune_expr=()
for dir in "${prune_dirs[@]}"; do
    prune_expr+=(-path "$dir" -prune -o)
done

find "$ROOT" \
    "${prune_expr[@]}" \
    \( -name "*.h" -o -name "*.hpp" -o -name "*.m" -o -name "*.mm" \) \
    -print0 |
    xargs -0 "$CLANG_FORMAT_BIN" -i
