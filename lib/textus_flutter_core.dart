/// Public library entry point for Textus Flutter Core.
///
/// Import this library to use domain-independent capture contracts and the
/// provisional development-only Display protocol and Presentation Context.
/// Local material and opaque document storage is durable on IO platforms;
/// unsupported platforms expose the same API and throw UnsupportedError.
library;

// Domain-independent capture values and contracts.
export 'src/capture/capture_identifiers.dart';
export 'src/capture/capture_item.dart';
export 'src/capture/capture_material.dart';
export 'src/capture/capture_profile.dart';
export 'src/capture/capture_session.dart';
export 'src/capture/photo_capture.dart';
export 'src/capture/recognition_operation_context.dart';
export 'src/capture/camera_service.dart';
export 'src/capture/image_picker_camera_provider.dart';
export 'src/capture/mlkit_image_recognition_provider.dart';
export 'src/capture/gemini_nano_image_recognition_provider.dart';
export 'src/capture/recognition_configuration.dart';
export 'src/capture/image_recognition_service.dart';
export 'src/capture/recognition_report.dart';
export 'src/capture/recognition_report_codec.dart';
export 'src/capture/recognition_repository.dart';
export 'src/capture/photo_capture_service.dart';

// Provisional development-only Display protocol and Presentation Context.
export 'src/display/separated_display_regions.dart';
export 'src/display/side_by_side_display_regions.dart';
export 'src/display/display_protocol.dart';
export 'src/display/presentation_context.dart';
export 'src/display/display_transport.dart';
export 'src/display/scripted_display_transport.dart';
export 'src/display/display_prototype_fixture.dart';
export 'src/display/fixture_display_source.dart';
export 'src/display/display_session.dart';

// Consumer repository contracts and local durable persistence.
export 'src/repository/capture_repository.dart';
export 'src/repository/local_capture_store.dart';
export 'src/repository/file_capture_store.dart';

// Generic settings runtime and independent desired recognition configuration.
export 'src/settings/setting_definition.dart';
export 'src/settings/settings_registry.dart';
export 'src/settings/settings_snapshot.dart';
export 'src/settings/settings_record.dart';
export 'src/settings/settings_service.dart';
export 'src/settings/settings_storage.dart';
export 'src/settings/settings_lifecycle_controller.dart';
export 'src/settings/local_settings_storage.dart';
export 'src/settings/recognition_settings.dart';
