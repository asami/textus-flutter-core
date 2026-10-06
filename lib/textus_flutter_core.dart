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
