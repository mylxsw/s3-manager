import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:s3_ui/core/storage/storage_service.dart';

enum UploadStatus { pending, uploading, success, failed }

class UploadItem {
  final String id;
  final String filePath;
  final String fileName;
  final String targetBucket;
  final String targetKey;
  final String? cdnUrl; // For localized "Check" or "Copy Link"

  UploadStatus status;
  double progress;
  String? errorMessage;
  String? resultUrl;

  UploadItem({
    required this.filePath,
    required this.fileName,
    required this.targetBucket,
    required this.targetKey,
    this.cdnUrl,
    this.status = UploadStatus.pending,
    this.progress = 0.0,
  }) : id = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
}

class UploadManager extends ChangeNotifier {
  final List<UploadItem> _queue = [];
  final StorageService _service;
  final String? _cdnUrl;
  final VoidCallback? onUploadComplete;

  bool _isProcessing = false;

  UploadManager({
    required StorageService service,
    String? cdnUrl,
    this.onUploadComplete,
  }) : _service = service,
       _cdnUrl = cdnUrl;

  List<UploadItem> get queue => List.unmodifiable(_queue);

  bool get hasActiveUploads => _queue.any(
    (item) =>
        item.status == UploadStatus.uploading ||
        item.status == UploadStatus.pending,
  );

  void addToQueue(List<String> filePaths, String targetPrefix) {
    for (final path in filePaths) {
      final fileName = path.split(Platform.pathSeparator).last;
      final key = targetPrefix.isEmpty ? fileName : '$targetPrefix$fileName';

      _queue.add(
        UploadItem(
          filePath: path,
          fileName: fileName,
          targetBucket: _service.bucketName,
          targetKey: key,
          cdnUrl: _cdnUrl,
        ),
      );
    }
    notifyListeners();
    _processQueue();
  }

  void retry(UploadItem item) {
    if (item.status == UploadStatus.failed) {
      item.status = UploadStatus.pending;
      item.errorMessage = null;
      item.progress = 0.0;
      notifyListeners();
      _processQueue();
    }
  }

  void remove(UploadItem item) {
    _queue.remove(item);
    notifyListeners();
  }

  void clearCompleted() {
    _queue.removeWhere((item) => item.status == UploadStatus.success);
    notifyListeners();
  }

  void clearAll() {
    if (!hasActiveUploads) {
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
            .where((item) => item.status == UploadStatus.pending)
            .toList();
        if (pendingItems.isEmpty) break;

        final item = pendingItems.first;

        // Update status to uploading
        item.status = UploadStatus.uploading;
        notifyListeners();

        try {
          final file = File(item.filePath);
          final stream = file.openRead().cast<Uint8List>();
          final size = await file.length();

          // We'll wrap the stream to track progress if Minio client allows,
          // otherwise we might just update to 100% on completion.
          // Minio's putObject doesn't easily expose stream progress callback in all versions,
          // but we can try to estimate or just wait.
          // For now, let's assume atomic upload for simplicity or mock progress.
          // If we want real progress, we need to wrap the stream.

          await _service.uploadStream(item.targetKey, stream, size: size);

          item.status = UploadStatus.success;
          item.progress = 1.0;
          item.resultUrl = _buildFileUrl(item.targetKey);
          // Trigger callback to refresh file list
          onUploadComplete?.call();
        } catch (e) {
          item.status = UploadStatus.failed;
          item.errorMessage = e.toString();
        }

        notifyListeners();
      }
    } finally {
      _isProcessing = false;
    }
  }

  String _buildFileUrl(String key) {
    if (_cdnUrl != null && _cdnUrl.isNotEmpty) {
      String url = _cdnUrl;
      if (url.endsWith('/')) {
        url = url.substring(0, url.length - 1);
      }
      return '$url/$key';
    }
    // Fallback if no CDN, maybe simple key or presigned?
    // Usually standard S3 URL structure or just key.
    return key;
  }
}
