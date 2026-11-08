import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'folder_parser.dart';

const folderPickSupported = true;

/// Диалог выбора папки через `<input type=file webkitdirectory>`; пустой список при отмене.
Future<List<PickedFile>> pickFolder() {
  final completer = Completer<List<PickedFile>>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true;
  input.setAttribute('webkitdirectory', '');

  input.addEventListener(
    'change',
    ((web.Event _) {
      final files = input.files;
      final out = <PickedFile>[];
      if (files != null) {
        for (var i = 0; i < files.length; i++) {
          final file = files.item(i)!;
          final rel = file.webkitRelativePath;
          out.add(
            PickedFile(
              path: rel.isEmpty ? file.name : rel,
              size: file.size,
              read: () async => (await file.arrayBuffer().toDart).toDart.asUint8List(),
            ),
          );
        }
      }
      if (!completer.isCompleted) {
        completer.complete(out);
      }
    }).toJS,
  );
  input.addEventListener(
    'cancel',
    ((web.Event _) {
      if (!completer.isCompleted) {
        completer.complete(const []);
      }
    }).toJS,
  );
  input.click();
  return completer.future;
}
