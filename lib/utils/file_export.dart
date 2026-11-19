/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Saving exported files on computers.
///
/// Phones and tablets hand an exported file to the system share sheet. On
/// Windows that sheet only offers mail, Teams and nearby devices, and its
/// plugin reports back before the user has picked a target, so the temporary
/// file can be gone by the time the target reads it. On computers (Windows,
/// Linux, macOS) we show the normal Save As dialog instead. macOS needs the
/// com.apple.security.files.user-selected.read-write entitlement for this.
class FileExport {
  FileExport._();

  @visibleForTesting
  static bool? debugUseSaveDialog;

  /// True on Windows, Linux and macOS (for labels such as "this computer").
  static bool get isComputer {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  /// True when exports should use a Save As dialog instead of the share sheet.
  static bool get useSaveDialog {
    final override = debugUseSaveDialog;
    if (override != null) return override;
    return isComputer;
  }

  /// Returns [name] trimmed, with a trailing [extension] (e.g. `.ptab`)
  /// removed, so a name typed as "Base.ptab" does not become "Base.ptab.ptab".
  static String baseName(String name, String extension) {
    final trimmed = name.trim();
    if (trimmed.toLowerCase().endsWith(extension.toLowerCase())) {
      return trimmed.substring(0, trimmed.length - extension.length).trim();
    }
    return trimmed;
  }

  /// Replaces characters Windows does not allow in file names with `_`.
  /// file_picker's Windows dialog throws on them inside a helper isolate,
  /// and the export would then wait forever with no dialog and no error.
  static String safeFileName(String fileName) =>
      fileName.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');

  /// Shows the Save As dialog and writes [bytes] to the chosen file.
  ///
  /// Returns the saved path, or null if the user cancelled.
  static Future<String?> saveWithDialog({
    required String dialogTitle,
    required String fileName,
    required List<int> bytes,
  }) async {
    final uri = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: safeFileName(fileName),
      bytes: Uint8List.fromList(bytes),
      windowsOptions: const WindowsOptions(lockParentWindow: true),
      linuxOptions: const LinuxOptions(lockParentWindow: true),
    );
    if (uri == null) return null;
    return uri.isScheme('file') ? uri.toFilePath() : uri.toString();
  }
}
