import 'folder_parser.dart';

/// Выбор папки доступен только в web-сборке; на остальных платформах используйте выбор файлов.
const folderPickSupported = false;

Future<List<PickedFile>> pickFolder() async => const [];
