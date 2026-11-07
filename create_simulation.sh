#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
LOG_FILE="$(pwd)/simulation_setup.log"
echo "[Create_Simulation] Khoi dong luc $(date)" >> "$LOG_FILE" 2>&1
exec julia --threads=2 --project=. simulation_setup.jl --setup
