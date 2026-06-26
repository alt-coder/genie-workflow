#!/usr/bin/env bash
set -euo pipefail

# install.sh — Deploy genie v1 to ~/.hermes/scripts/
# Usage: ./install.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${HOME}/.hermes/scripts"

echo "Installing genie v1 to ${TARGET}/..."

mkdir -p "${TARGET}/lib/roles" "${TARGET}/lib/team-layouts"

# Core pipeline
for f in genie.sh hermes-spawn.sh hermes-preflight.sh pattern_discovery.sh \
         budget_tracker.py skill_scan.sh merge_goal.sh zettelkasten.sh filter.sh; do
    cp "${SCRIPT_DIR}/${f}" "${TARGET}/${f}"
done

# Dark factory
for f in factory-setup.sh factory-start.sh factory-stop.sh factory-status.sh; do
    cp "${SCRIPT_DIR}/${f}" "${TARGET}/${f}"
done

# Lib
for f in lib/_common.sh lib/_models.sh lib/_roles.sh lib/factory-env.template; do
    cp "${SCRIPT_DIR}/${f}" "${TARGET}/${f}"
done

# Role prompts
for f in "${SCRIPT_DIR}"/lib/roles/*.md; do
    cp "$f" "${TARGET}/lib/roles/"
done

# Team layouts
for f in "${SCRIPT_DIR}"/lib/team-layouts/*.sh; do
    cp "$f" "${TARGET}/lib/team-layouts/"
    chmod +x "${TARGET}/lib/team-layouts/$(basename "$f")"
done

# Make executable
chmod +x "${TARGET}"/*.sh

# Symlink genie command
mkdir -p "${HOME}/.local/bin"
ln -sf "${TARGET}/genie.sh" "${HOME}/.local/bin/genie"

echo "✓ Installed. Run: genie --help"
echo "✓ Dark factory setup: genie factory setup"
