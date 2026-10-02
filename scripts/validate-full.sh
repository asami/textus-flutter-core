#!/usr/bin/env bash
set -euo pipefail

# Run from the package root; Flutter manages only its normal build/dependency caches.
cd -- "$(dirname -- "$0")/.."
flutter analyze
flutter test
