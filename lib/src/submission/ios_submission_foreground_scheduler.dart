import 'package:flutter/foundation.dart';

import 'foreground_submission_scheduler.dart';

typedef IosSubmissionResourcesOpener = ForegroundSubmissionResourcesOpener;

/// Existing native public entry with unchanged iOS-only admission.
final class IosSubmissionForegroundScheduler
    extends ForegroundSubmissionScheduler {
  IosSubmissionForegroundScheduler({
    required super.openResources,
    super.binding,
    super.networkAllowed,
    super.now,
  });
  @override
  bool get isPlatformSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
}
