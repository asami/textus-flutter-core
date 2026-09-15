# Textus Flutter Core — Project Initial Setup

Date: 2026-09-15

Status: Phase 1 setup baseline

## Purpose

Phase 1の最初に`textus-flutter-core`を再利用可能なFlutter package/libraryとしてbootstrapする。

これはFlutter applicationではなく、NICT Editing Studio App等から利用される共通Flutter client foundationである。

## Technology baseline

- Language: Dart
- Framework/runtime ecosystem: Flutter
- Artifact type: reusable Flutter package
- Initial runtime targets: iOS / Android consumers
- Future compatibility: Flutter Web / Desktopを不必要に排除しない
- Initial consumer: `KnowledgeHubProject/nict-editing-studio-app`

Flutter / Dart SDK constraintはconsumerと揃え、stable toolchainを基準にCodexが実環境確認後に固定する。

## Initial creation

Flutter package scaffoldを使用する。

Conceptual command:

```text
flutter create --template=package ...
```

repository名は`textus-flutter-core`だが、Dart package名はDart naming conventionに従い`textus_flutter_core`を基本候補とする。

## Initial repository shape

```text
textus-flutter-core/
  pubspec.yaml
  analysis_options.yaml
  lib/
    textus_flutter_core.dart
    src/
      capture/
      application/
      repository/
      sync/
      integration/
  test/
  docs/
    notes/
    journal/
    phase/
  README.md
```

Phase 1 setup時点では空directoryを大量に作る必要はなく、最初のpublic APIに必要な範囲で作成する。

## Public API policy

consumerは原則`package:textus_flutter_core/textus_flutter_core.dart`等のpublic entry pointを利用し、`src/`内部へ直接依存しない。

Phase 1で最初に公開する候補:

- CaptureSession skeleton
- CaptureItem skeleton
- CaptureProfile contract
- repository / submit abstraction skeleton

実際のdomain shapeは既存notes/phaseのTMR-02/TMR-03で確定する。

## Dependency policy

Core packageなので依存packageを増やしすぎない。

Camera等のdevice-specific packageは必要性が明確になったstageで追加し、pure model / contract layerがplatform pluginに引きずられない構成を優先する。

KnowledgeHub / Editing Studio固有packageへ依存しない。

## Generated Dart relationship

Cozy Phase 55で生成されるDart model/API contractを将来利用できる境界を保つ。

生成物をCore内部へ手作業コピーする前提にせず、generated package / source-setの取り込み方法をPhase 55とのintegration時に決める。

## Quality baseline

- `flutter analyze`
- `flutter test`
- package import smoke test
- consumer application compile smoke

package自身にiOS/Android app scaffoldは不要。実機確認はconsumer appを通して行う。

## README

- package purpose
- supported Flutter/Dart constraint
- install/dependency example
- public API policy
- analyze/test commands
- Editing Studio Appでのlocal development method

を記載する。

## Setup acceptance

- Flutter packageとしてclean build/analyzeできる
- unit testが実行できる
- public library entry pointが存在する
- `nict-editing-studio-app`からdependency/importできる
- KnowledgeHub / Book固有依存がない
- Phase 1 Capture Runtime実装を開始できるskeletonになっている
