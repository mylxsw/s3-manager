import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Manages file downloads with proper directory handling
class DownloadManager {
  /// Get the appropriate download directory based on platform
  static Future<Directory?> getDownloadDirectory() async {
    // Use path_provider to get the system downloads directory
    Directory? downloadsDir;
    try {
      downloadsDir = await getDownloadsDirectory();
    } catch (e) {
      debugPrint('Error getting downloads directory: $e');
    }

    if (downloadsDir != null) {
      if (!await downloadsDir.exists()) {
        try {
          await downloadsDir.create(recursive: true);
        } catch (e) {
          debugPrint('Error creating downloads directory: $e');
        }
      }
      return downloadsDir;
    }

    // Final fallback to application documents directory
    return getApplicationDocumentsDirectory();
  }

  /// Save file with proper error handling
  static Future<String> saveFile({
    required String fileName,
    required Uint8List bytes,
    String? customPath,
  }) async {
    try {
      Directory? directory;

      if (customPath != null) {
        directory = Directory(customPath);
      } else {
        directory = await getDownloadDirectory();
      }

      if (directory == null) {
        throw Exception('Could not determine download directory');
      }

      // Ensure directory exists
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }

      // Clean file name
      final cleanFileName = fileName.replaceAll(RegExp(r'[^\w\s.-]'), '_');
      final file = File(path.join(directory.path, cleanFileName));

      debugPrint('Saving file to: ${file.path}');

      // Write bytes to file
      await file.writeAsBytes(bytes);

      return file.path;
    } catch (e) {
      throw Exception('Failed to save file: $e');
    }
  }

  /// Show download progress dialog
  static void showDownloadDialog({
    required BuildContext context,
    required String fileName,
    required Future<String> downloadFuture,
    VoidCallback? onDownloaded,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        child: Container(
          padding: const EdgeInsets.all(24),
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Downloading $fileName...',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Please wait',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );

    downloadFuture
        .then((filePath) {
          Navigator.pop(context); // Close progress dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Downloaded: ${path.basename(filePath)}'),
              action: SnackBarAction(
                label: 'Open',
                onPressed: () {
                  // Open file location
                  if (Platform.isMacOS || Platform.isLinux) {
                    Process.run('open', [path.dirname(filePath)]);
                  } else if (Platform.isWindows) {
                    Process.run('explorer', [path.dirname(filePath)]);
                  }
                },
              ),
            ),
          );
          onDownloaded?.call();
        })
        .catchError((error) {
          Navigator.pop(context); // Close progress dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Download failed: $error'),
              backgroundColor: Colors.red,
            ),
          );
        });
  }
}
