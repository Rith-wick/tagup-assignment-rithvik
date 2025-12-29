#!/usr/bin/env bash
set -euo pipefail

if ! command -v pwsh >/dev/null 2>&1; then
  echo "Error: pwsh (PowerShell 7+) not found."
  echo "Install PowerShell 7+, then re-run."
  exit 1
fi

pwsh ./run.ps1 "$@"