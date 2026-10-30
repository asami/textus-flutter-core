/// Public library entry point for Textus Flutter Core.
///
/// Import this library to use domain-independent capture contracts and the
/// provisional development-only Display protocol and Presentation Context.
/// Local material and opaque document storage is durable on IO platforms;
/// unsupported platforms expose the same API and throw UnsupportedError.
library;

// Original audio runtime, strict PCM and append-only transcript contracts.
export 'src/audio/audio_capture.dart';
export 'src/audio/audio_capture_service.dart';
export 'src/audio/audio_transcript.dart';
export 'src/audio/audio_transcript_codec.dart';
export 'src/audio/android_audio_provider.dart';
export 'src/audio/pcm_wave_audio.dart';

// Domain-independent capture values and contracts.
export 'src/capture/capture_identifiers.dart';
export 'src/capture/capture_item.dart';
export 'src/capture/capture_material.dart';
export 'src/capture/capture_profile.dart';
export 'src/capture/capture_session.dart';
export 'src/capture/generated_draft.dart';
export 'src/capture/generated_draft_service.dart';
export 'src/capture/text_revision_comparison.dart';
export 'src/capture/gemini_nano_generated_draft_provider.dart';
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
export 'src/capture/image_region.dart';
export 'src/capture/image_region_processing.dart';
export 'src/capture/image_region_workspace.dart';
export 'src/capture/image_region_workspace_codec.dart';

// Provisional development-only Display protocol and Presentation Context.
export 'src/display/separated_display_regions.dart';
export 'src/display/side_by_side_display_regions.dart';
export 'src/display/display_protocol.dart';
export 'src/display/cncf_display_read.dart';
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

// Durable explicit submission intent, resumable checkpoints and borrowed ports.
export 'src/submission/submission_request.dart';
export 'src/submission/registered_material_submission.dart';
export 'src/submission/registered_material_submission_codec.dart';
export 'src/submission/registered_material_handoff_store.dart';
export 'src/submission/registered_material_handoff_service.dart';
export 'src/submission/tkl_material_delivery.dart';
export 'src/submission/tkl_original_content.dart';
export 'src/submission/tkl_material_delivery_http_client.dart';
export 'src/submission/submission_record.dart';
export 'src/submission/submission_transfer_status.dart';
export 'src/submission/submission_codec.dart';
export 'src/submission/submission_queue_store.dart';
export 'src/submission/sqlite_submission_queue_store.dart';
export 'src/submission/submission_adapters.dart';
export 'src/submission/submission_service.dart';
export 'src/submission/submission_connections.dart';
export 'src/submission/drive_submission_storage_adapter.dart';
export 'src/submission/http_submission_transport.dart';
export 'src/submission/submission_configuration.dart';
export 'src/submission/submission_reference_access.dart';
export 'src/submission/android_submission_configuration.dart';
export 'src/submission/submission_run_lifetime.dart';
export 'src/submission/submission_background_resources.dart';
export 'src/submission/submission_background_runner.dart';
export 'src/submission/android_submission_background.dart';

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
export 'src/capture/structured_candidates.dart';
