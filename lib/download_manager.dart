import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // For debugPrint
import 'package:s3_ui/core/storage/storage_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

enum DownloadStatus { pending, downloading, success, failed }

class DownloadItem {
  final String id;
  final String key; // S3 object key
  final String? bucket; // Optional, for reference
  final int? size;

  DownloadStatus status;
  double progress;
  String? errorMessage;
  String? savePath;

  DownloadItem({
    required this.key,
    this.bucket,
    this.size,
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
  }) : id = '${DateTime.now().millisecondsSinceEpoch}_$key';

  String get fileName => key.split('/').last;
}

class DownloadManager extends ChangeNotifier {
  final List<DownloadItem> _queue = [];
  final StorageService _service;
  final VoidCallback? onDownloadComplete;

  bool _isProcessing = false;

  DownloadManager({required StorageService service, this.onDownloadComplete})
    : _service = service;

  List<DownloadItem> get queue => List.unmodifiable(_queue);

  bool get hasActiveDownloads => _queue.any(
    (item) =>
        item.status == DownloadStatus.downloading ||
        item.status == DownloadStatus.pending,
  );

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

  void addToQueue(String key, {int? size}) {
    _queue.add(DownloadItem(key: key, bucket: _service.bucketName, size: size));
    notifyListeners();
    _processQueue();
  }

  void retry(DownloadItem item) {
    if (item.status == DownloadStatus.failed) {
      item.status = DownloadStatus.pending;
      item.errorMessage = null;
      item.progress = 0.0;
      notifyListeners();
      _processQueue();
    }
  }

  void remove(DownloadItem item) {
    _queue.remove(item);
    notifyListeners();
  }

  void clearCompleted() {
    _queue.removeWhere((item) => item.status == DownloadStatus.success);
    notifyListeners();
  }

  void clearAll() {
    if (!hasActiveDownloads) {
      _queue.clear();
      notifyListeners();
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;

    _isProcessing = true;

    try {
      while (true) {
        // Find next pending item
        final pendingItems = _queue
            .where((item) => item.status == DownloadStatus.pending)
            .toList();
        if (pendingItems.isEmpty) break;

        final item = pendingItems.first;

        // Update status to downloading
        item.status = DownloadStatus.downloading;
        notifyListeners();

        try {
          final dir = await getDownloadDirectory();
          if (dir == null) {
            throw Exception('Could not access download directory');
          }

          final cleanFileName = item.fileName.replaceAll(
            RegExp(r'[^\w\s.-]'),
            '_',
          );

          // Smart renaming logic
          String uniqueFileName = cleanFileName;
          int counter = 1;

          while (File(path.join(dir.path, uniqueFileName)).existsSync()) {
            final name = path.basenameWithoutExtension(cleanFileName);
            final ext = path.extension(cleanFileName);
            uniqueFileName = '$name ($counter)$ext';
            counter++;
          }

          final saveFile = File(path.join(dir.path, uniqueFileName));
          item.savePath = saveFile.path;

          // Get object stream
          final stream = await _service.downloadStream(item.key);

          // We download the whole stream.
          // To track progress, we need to know the size (optional) and count bytes.
          // Minio stream is Stream<Uint8List>.

          final IOSink sink = saveFile.openWrite();
          int receivedBytes = 0;

          await for (final chunk in stream) {
            sink.add(chunk);
            receivedBytes += chunk.length;
            if (item.size != null && item.size! > 0) {
              item.progress = receivedBytes / item.size!;
              // Debounce notification if needed, or just let it flow?
              // Flutter might reconstruct widgets often if we notify too fast.
              // For now, let's notify periodically or every chunk?
              // Every chunk might be too much.
              // Let's do simple: notify.
              // But to avoid locking UI, maybe check time?
              notifyListeners();
            }
          }
          await sink.close();

          item.status = DownloadStatus.success;
          item.progress = 1.0;
          onDownloadComplete?.call();
        } catch (e) {
          item.status = DownloadStatus.failed;
          item.errorMessage = e.toString();
        }

        notifyListeners();
      }
    } finally {
      _isProcessing = false;
    }
  }
}
