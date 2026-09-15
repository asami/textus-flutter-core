#!/usr/bin/env bash

set -euo pipefail

flutter analyze
flutter test
flutter test test/textus_flutter_core_test.dart
