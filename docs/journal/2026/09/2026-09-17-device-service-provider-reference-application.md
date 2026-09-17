# Device Service / Provider Architecture and Reference Application

Date: 2026-09-17
Status: active
Scope: Phase 1.1

## Decision

Phase 1.1 establishes the reusable device-runtime foundation of Textus Flutter Core, not merely individual camera/capture functions.

Device-dependent functions follow a common **Service / Provider** architecture:

- **Service** is the stable Textus-facing API and owns Textus/runtime semantics.
- **Provider** is the replaceable SPI that absorbs platform, device, Flutter-plugin, and external-provider differences.
- Provider interfaces remain capability-sized; do not create one monolithic DeviceProvider.

Initial shape:

```text
Capture Runtime / Application
        |
        +-- CameraService -- CameraProvider
        +-- AudioService  -- AudioProvider
        +-- AiService     -- AiProvider
```

Future device capabilities such as OCR, barcode scanning, location, and other sensors should use the same pattern when admitted.

`AiService` owns AI-facing runtime semantics, provider selection/policy, and result normalization. `AiProvider` owns the concrete execution route. This allows Android on-device AI, future iOS on-device AI, cloud AI, and test providers to coexist without exposing a specific AI engine to applications.

Capability discovery and runtime availability should be represented at the Provider boundary so a Service can select an available implementation without the consumer depending on platform details.

## Phase 1.1 Reference Application

Phase 1.1 also introduces a **Reference Application** dedicated to Textus Flutter Core. It is not NICT Editing Studio and is not a disposable sample.

The Reference Application serves as:

- executable usage documentation for the public runtime API;
- iPhone/Android device acceptance harness;
- integration and regression environment for Provider implementations;
- a controlled place to add and validate new device capabilities;
- a future Pixel/on-device-AI experiment surface without coupling experiments to Editing Studio.

The Phase 1.1 reference vertical slice covers camera/image capture, audio recording, text-note input, review/correction/removal/reorder, submit through a stub or application-provided repository integration, and device-capability diagnostics.

`nict-editing-studio-app` remains the first practical external consumer. Its BookCaptureProfile and domain semantics must remain outside Textus Flutter Core.

## AI Boundary in Phase 1.1

Phase 1.1 establishes the `AiService -> AiProvider` architecture and capability/availability boundary, but does not require advanced AI capture workflows.

A later Phase can add concrete Pixel/Android on-device AI and then workflows such as image description, classification, metadata extraction, and suggestion generation. AI output should remain a suggestion until application/runtime review and confirmation; it must not silently become confirmed CaptureSession information.

## Consequences

Camera and audio are the first concrete proof that the Service / Provider architecture works across real devices. AI uses the same architecture rather than becoming a special parallel integration mechanism.

This turns Phase 1.1 into the device-runtime foundation on which Editing Studio, Agriculture, and other domain-specific CaptureProfile consumers can build.