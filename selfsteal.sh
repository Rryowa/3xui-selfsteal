#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f "build.sh" ]; then
    echo "Error: build.sh not found."
    exit 1
fi

mkdir -p dist
bash build.sh src/selfsteal/main.sh > dist/selfsteal.sh
chmod +x dist/selfsteal.sh

exec dist/selfsteal.sh "$@"
