#!/usr/bin/env bash
set -euo pipefail

if (( $# > 1 )) || [[ -n "${1-}" && "$1" != "--setup" ]]; then
  printf 'Uso: bash scripts/start-web.sh [--setup]\n' >&2
  exit 2
fi

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

cd -- "$repo_dir/mobile"
flutter build web --no-web-resources-cdn --no-wasm-dry-run

cd -- "$repo_dir/backend"
if [[ "${1-}" == "--setup" ]]; then
  npm ci
  npm run migrate
fi

exec npm run start:web
