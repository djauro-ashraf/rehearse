import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/audio_importer.dart';

/// Picking and sharing files. The only place that talks to those plugins.
class FileService {
  const FileService();

  /// Lets the user choose one or more audio files.
  Future<List<ImportSource>> pickAudio() async {
    final files = await FilePicker.pickFiles(type: FileType.audio);
    // Mobile pickers hand over a cache copy, which is safe to delete after
    // importing. On desktop the path is the user's own file: never delete it.
    final isTemporary = Platform.isAndroid || Platform.isIOS;
    return [
      for (final file in files)
        ImportSource(
          name: file.name,
          path: file.path,
          openRead: file.path == null ? file.readAsByteStream : null,
          isTemporary: isTemporary,
        ),
    ];
  }

  /// Lets the user choose a practice sheet and returns its text.
  Future<String?> pickTextFile() async {
    final file = await FilePicker.pickFile();
    if (file == null) return null;
    return utf8.decode(await file.readAsBytes(), allowMalformed: true);
  }

  /// Opens a "save as" dialog. Returns false if the user cancelled.
  Future<bool> saveTextFile({
    required String fileName,
    required String content,
    String mimeType = 'application/json',
  }) async {
    final saved = await FilePicker.saveFile(
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(content)),
      mimeType: mimeType,
    );
    return saved != null;
  }

  /// Opens the system share sheet with plain text (pasteable anywhere).
  Future<void> shareText(String text, {String? subject}) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject, title: subject));
  }

  /// Opens the system share sheet with a small text file.
  Future<void> shareTextFile({
    required String fileName,
    required String content,
    String mimeType = 'application/json',
    String? subject,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(content);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: subject,
        title: subject,
      ),
    );
  }
}
