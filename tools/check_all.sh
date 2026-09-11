#!/usr/bin/env bash
# Verification complete : tests unitaires, ecrans, saison, equilibrage marche.
#   bash tools/check_all.sh
set -u
GODOT="${GODOT:-/c/Users/dark7/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FILTER='RID allocations|PagedAllocator|Unreferenced static string|wait_to_finish|A Thread object'

echo "== Reindexation des classes globales =="
"$GODOT" --headless --path "$PROJECT_DIR" --editor --quit >/dev/null 2>&1

echo "== Tests unitaires =="
timeout 360 "$GODOT" --headless --path "$PROJECT_DIR" --script res://tools/run_tests.gd 2>&1 | grep -v -E "$FILTER"
UNIT=$?

echo "== Construction des ecrans =="
timeout 360 "$GODOT" --headless --path "$PROJECT_DIR" --script res://tools/ui_check.gd 2>&1 | grep -v -E "$FILTER"

echo "== Saison complete =="
timeout 300 "$GODOT" --headless --path "$PROJECT_DIR" --script res://tools/season.gd 2>&1 | grep -v -E "$FILTER"

echo "== Negociation (equilibrage) =="
timeout 240 "$GODOT" --headless --path "$PROJECT_DIR" --script res://tools/negotiation_probe.gd 2>&1 | grep -v -E "$FILTER"
