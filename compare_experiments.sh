#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
echo "TerraFlux A/B: nhật ký khởi động và lỗi tại comparison_setup.log"
exec julia --threads=2 --project=. compare_experiments.jl --setup "$@" >> comparison_setup.log 2>&1
