#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
exec julia --threads=2 --project=. viewer.jl --setup "$@"
