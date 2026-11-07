@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:web/web.dart' as web;
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  test('actual file input reads selected content and handles cancel without camera or microphone access', () async {
    // Given the real browser file adapter, suppress only the OS picker dialog.
    final prototype = (web.window.getProperty<JSObject>(
      'HTMLInputElement'.toJS,
    )).getProperty<JSObject>('prototype'.toJS);
    final click = prototype.getProperty<JSFunction>('click'.toJS);
    prototype.setProperty('click'.toJS, (() {}).toJS);
    addTearDown(() => prototype.setProperty('click'.toJS, click));
    final provider = createPlatformMediaInputProvider();
    addTearDown(provider.close);
    // When a real DOM File is selected through the real input change event.
    final bytes = Uint8List.fromList(
      image.encodePng(image.Image(width: 2, height: 2)),
    );
    final pending = provider.importImage();
    final input =
        web.document.querySelector('input[type=file]')! as web.HTMLInputElement;
    final transfer = web.DataTransfer();
    transfer.items.add(
      web.File(
        [bytes.toJS].toJS,
        '表紙.bin',
        web.FilePropertyBag(type: 'application/octet-stream'),
      ),
    );
    input.files = transfer.files;
    input.dispatchEvent(web.Event('change'));
    final selected = await pending;
    // Then actual bytes determine the image type, and the temporary input is removed.
    expect(selected!.bytes, bytes);
    expect(selected.mediaType, 'image/png');
    expect(web.document.querySelector('input[type=file]'), isNull);
    final camera = provider.capabilities[MediaInputAction.cameraCapture]!;
    expect(camera.support, MediaAdapterSupport.unsupported);
    expect(camera.device, MediaDeviceAvailability.unknown);
    // When a later file selection is cancelled, then no image is produced.
    final cancelled = provider.importImage();
    web.document
        .querySelector('input[type=file]')!
        .dispatchEvent(web.Event('cancel'));
    expect(await cancelled, isNull);
  });
}
