#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 [--python-venv] <command:package> [command:package ...]" >&2
  exit 1
fi

CHECK_PYTHON_VENV=0
CHECKS=()

for arg in "$@"; do
  case "$arg" in
    --python-venv)
      CHECK_PYTHON_VENV=1
      ;;
    *)
      CHECKS+=("$arg")
      ;;
  esac
done

if [ "${#CHECKS[@]}" -eq 0 ]; then
  echo "No command checks provided." >&2
  exit 1
fi

MISSING_PKGS=()

add_pkg() {
  local pkg="$1"
  for existing in "${MISSING_PKGS[@]}"; do
    if [ "$existing" = "$pkg" ]; then
      return
    fi
  done
  MISSING_PKGS+=("$pkg")
}

for item in "${CHECKS[@]}"; do
  if [[ "$item" != *:* ]]; then
    echo "Invalid check '$item'. Expected format command:package." >&2
    exit 1
  fi

  cmd="${item%%:*}"
  pkg="${item#*:}"

  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing tool: $cmd (package: $pkg)"
    add_pkg "$pkg"
  fi
done

if [ "$CHECK_PYTHON_VENV" -eq 1 ]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Missing tool: python3 (required for venv check)"
    add_pkg "python3"
    echo "Missing module: venv (package: python3-venv)"
    add_pkg "python3-venv"
  elif ! python3 -m venv --help >/dev/null 2>&1; then
    echo "Missing module: venv (package: python3-venv)"
    add_pkg "python3-venv"
  fi
fi

if [ "${#MISSING_PKGS[@]}" -gt 0 ]; then
  apt-get update
  apt-get install -y "${MISSING_PKGS[@]}"
fi
