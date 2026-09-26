#!/usr/bin/env bash
# Android native "Terminal" app (AVF). Thin wrapper over setup-debian.sh.
# Same options; default is --dry-run. See ./setup-debian.sh --help.
set -Eeuo pipefail
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup-debian.sh" --target avf "$@"
