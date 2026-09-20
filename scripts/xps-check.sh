#!/usr/bin/env bash
set -euo pipefail
printf 'Omarchy version: '
omarchy-version || true
printf '\nHyprland:\n'
hyprctl version || true
printf '\nTheme:\n'
cat "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/current/theme.name" 2>/dev/null || true
printf '\nQt runtime:\n'
pacman -Q qt6-base qt6-declarative qt6-wayland || true
printf '\nTask Manager:\n'
pacman -Q omarchy-task-manager || true
printf '\nComplete the interactive XPS checklist in README.md. This script only collects versions.\n'
