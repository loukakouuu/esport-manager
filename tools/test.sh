#!/usr/bin/env bash
# Cycle de test : reindexation des classes globales puis execution headless.
#   bash tools/test.sh          -> lance la suite de tests
#   bash tools/test.sh smoke    -> lance le script de fumee
set -u
GODOT="${GODOT:-/c/Users/dark7/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="res://tools/run_tests.gd"
[ "${1:-}" = "smoke" ] && SCRIPT="res://tools/smoke.gd"
"$GODOT" --headless --path "$PROJECT_DIR" --editor --quit >/dev/null 2>&1
timeout 180 "$GODOT" --headless --path "$PROJECT_DIR" --script "$SCRIPT" 2>&1 \
  | grep -v -E "RID allocations|PagedAllocator|Unreferenced static string|wait_to_finish|A Thread object"
