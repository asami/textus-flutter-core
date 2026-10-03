# Flutter/Dart naming rules

- Status: Active.
- Owner: textus-flutter-core maintainer.
- Update rule: follow Effective Dart and the repository's configured Flutter analyzer rules. Any deliberate departure requires an explicit maintainer decision.

## Scope and precedence

Apply these rules to Dart source and executable specifications in textus-flutter-core. These language-specific rules take precedence over the generic CNCF naming fallback for private members, local variables and local helpers. Other CNCF architecture, documentation, executable-specification and acceptance requirements continue to apply.

## Naming

- Types, enums and named extensions use `UpperCamelCase`, for example `DisplaySession`.
- Functions, methods, fields, parameters, locals and local helpers use `lowerCamelCase`, for example `clockCalls`.
- New constants and enum values use `lowerCamelCase`, for example `defaultTimeout`; preserve an existing generated or externally required name.
- Private library and class members use a leading underscore followed by the normal name, for example `_notificationDepth`. Privacy is library-scoped in Dart.
- Ordinary locals, parameters and local helper functions do not receive leading or trailing underscores. An unused callback parameter may use the Dart wildcard `_`.
- Packages, directories, Dart files and import prefixes use `lowercase_with_underscores`, for example `display_session.dart`.
- Preserve names required by an overridden API and serialized/public schema keys.

Use a function declaration when binding a local function to a name, for example `void listener() {}`. Keep the configured `package:flutter_lints/flutter.yaml` rules enabled; do not add analyzer exclusions or ignore directives to accommodate the generic CNCF fallback.

Executable specifications retain their observable behavior, expectation strength, grouping and adjacent Given/When/Then clauses. These rules grant no API, schema, fixture, runtime, test or Phase acceptance waiver.

## Adoption and references

Adopted on 2026-10-03 through the owning Phase 4 user's instruction, 「この方針で行きましょう。」, following the explanation of Flutter/Dart's official naming rules. This records the language convention; Phase 4 still requires its independent review and final validation.

- [Effective Dart: Style](https://dart.dev/effective-dart/style)
- [Local identifiers](https://dart.dev/tools/linter-rules/no_leading_underscores_for_local_identifiers)
- [Local function declarations](https://dart.dev/tools/linter-rules/prefer_function_declarations_over_variables)
