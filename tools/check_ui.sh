#!/usr/bin/env bash
# Réindexe les classes puis vérifie que chaque écran se construit et respecte
# les invariants de mise en page. À lancer après toute modification d'UI.
set -u
GODOT="${GODOT:-/c/Users/dark7/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
cd "$(dirname "$0")/.."
timeout 200 "$GODOT" --headless --path . --editor --quit 2>&1 \
  | grep -E "SCRIPT ERROR|Parse Error|Failed to load|at: GDScript" | head -40
echo "--- ecrans ---"
timeout 200 "$GODOT" --headless --path . --script res://tools/ui_check.gd 2>&1 | tail -45
