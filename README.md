# Textus Flutter Core

`textus_flutter_core` is a reusable Flutter package for domain-independent
capture-runtime contracts. It intentionally contains no Editing Studio, Book,
or KnowledgeHub domain types.

This repository is a Flutter **package**, not a Flutter application. It has no
`main.dart` or platform-app scaffold. Consumer applications own application
startup, navigation, and iOS/Android builds.

## Requirements

- Flutter 3.47.4 or later
- Dart 3.13.3 or later

## Install in a consumer during local development

```yaml
dependencies:
  textus_flutter_core:
    path: ../textus-flutter-core
```

Import only the package's public entry point:

```dart
import 'package:textus_flutter_core/textus_flutter_core.dart';
```

Do not import future `lib/src/` implementation files directly.

## Development

```sh
flutter pub get
flutter analyze
flutter test
```

Library-level validation runs in this repository. iOS/Android device and
consumer smoke tests run from an explicitly admitted Flutter consumer app.

## Package layout

```text
lib/textus_flutter_core.dart  public API entry point
lib/src/                      internal implementation, added with the first API
test/                         package unit and widget tests
docs/                         Phase and architecture records
```

If Textus Flutter Core later owns native platform code rather than depending on
an existing Flutter plugin, that capability should be introduced as a Flutter
plugin package with an example consumer—not as an application scaffold or an
SBT subproject.
