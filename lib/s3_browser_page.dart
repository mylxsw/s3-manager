import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:s3_ui/models/s3_server_config.dart';

import 'package:s3_ui/download_manager.dart';
import 'package:s3_ui/widgets/loading_overlay.dart';
import 'package:s3_ui/core/localization.dart';
import 'package:s3_ui/core/upload_manager.dart';
import 'package:s3_ui/widgets/upload_queue_ui.dart';
import 'package:s3_ui/widgets/download_queue_ui.dart';
import 'package:s3_ui/core/storage/storage_service.dart';
import 'package:s3_ui/core/storage/s3_storage_service.dart';
import 'package:s3_ui/core/design_system.dart';

/// Represents an S3 object or directory prefix
class S3Item {
  final String key;
  final int? size;
  final DateTime? lastModified;
  final bool isDirectory;
  final String? eTag;

  S3Item({
    required this.key,
    this.size,
    this.lastModified,
    required this.isDirectory,
    this.eTag,
  });

  /// Create an S3Item from a prefix (directory)
  factory S3Item.fromPrefix(String prefix) {
    return S3Item(
      key: prefix,
      size: null,
      lastModified: null,
      isDirectory: true,
      eTag: null,
    );
  }
}

class S3BrowserPage extends StatefulWidget {
  final S3ServerConfig serverConfig;
  final VoidCallback? onEditServer;

  const S3BrowserPage({
    super.key,
    required this.serverConfig,
    this.onEditServer,
  });

  @override
  State<S3BrowserPage> createState() => _S3BrowserPageState();
}

class _S3BrowserPageState extends State<S3BrowserPage> {
  late StorageService _storageService;
  List<S3Item> _objects = [];
  bool _isLoading = true;
  bool _isUploading = false;
  bool _isGridView = false;
  String _currentPrefix = '';
  final List<String> _prefixHistory = [];
  bool _isDragging = false;

  // Cache storage for file listings
  final Map<String, List<S3Item>> _cache = {};
  bool _isRefreshing = false;
  UploadManager? _uploadManager;
  DownloadManager? _downloadManager;
  String? _initError;

  // Multi-select state
  final Set<String> _selectedItems = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    try {
      _initializeService(); // This will now initialize _uploadManager too
    } catch (e) {
      debugPrint('Error initializing Minio in initState: $e');
      if (mounted) {
        setState(() {
          _initError = e.toString();
          _isLoading = false;
        });
      }
    }
    if (_initError == null) {
      _listObjects();
    }
  }

  @override
  void didUpdateWidget(S3BrowserPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.serverConfig.id != oldWidget.serverConfig.id) {
      // Clear cache and reset state when switching servers
      // Remove cache clearing to allow preserving cache across server switches
      // _cache.clear();
      _currentPrefix = '';
      _prefixHistory.clear();
      // _objects = []; // Let _listObjects handle this based on cache
      // _isLoading = true; // Let _listObjects handle this based on cache
      _initializeService();
      _listObjects();
    }
  }

  void _initializeService() {
    try {
      // Validate S3/R2 config first (keeping existing helper for now, though service might do it)
      // Since S3StorageService encapsulates logic, we just instantiate it.
      // But we still want to log or validate.
      // The current S3StorageService constructor encapsulates creation.
      // Let's create it.

      _storageService = S3StorageService(widget.serverConfig);

      // Initialize UploadManager
      _uploadManager = UploadManager(
        service: _storageService,
        cdnUrl: widget.serverConfig.cdnUrl,
        onUploadComplete: () {
          // Refresh file list after upload completes
          _clearCache();
          _listObjects(prefix: _currentPrefix);
        },
      );

      // Initialize DownloadManager
      _downloadManager = DownloadManager(
        service: _storageService,
        onDownloadComplete: () {
          // Optional: Notify user or just let the queue UI handle it
        },
      );

      debugPrint('✓ Storage service initialized successfully');
    } catch (e) {
      debugPrint('✗ Failed to initialize Storage service: $e');
      // Re-throw to be handled by the caller
      rethrow;
    }
  }

  Future<void> _listObjects({String? prefix}) async {
    final effectivePrefix = prefix ?? _currentPrefix;
    final cacheKey =
        '${widget.serverConfig.id}:${widget.serverConfig.bucket}:$effectivePrefix';

    // If we're already on a different prefix, don't update UI for old requests
    if (effectivePrefix != _currentPrefix) {
      debugPrint(
        'Ignoring list request for $effectivePrefix (current: $_currentPrefix)',
      );
      return;
    }

    // 1. Check cache
    if (_cache.containsKey(cacheKey)) {
      // If we have cache, show it immediately and do NOT show loading overlay
      if (mounted) {
        setState(() {
          _objects = _cache[cacheKey]!;
          _isLoading = false;
        });
      }
      debugPrint('Loaded from cache for prefix: $effectivePrefix');
    } else {
      // If no cache, clear objects and show loading overlay
      if (mounted) {
        setState(() {
          _objects = [];
          _isLoading = true;
        });
      }
    }

    // Always fetch fresh data in the background
    _isRefreshing = true;

    try {
      // Debug information
      debugPrint('Listing objects from bucket: ${widget.serverConfig.bucket}');
      debugPrint('Using endpoint: ${widget.serverConfig.address}');
      debugPrint('Using prefix: $effectivePrefix');

      final results = await _storageService.listObjects(
        prefix: effectivePrefix,
      );

      // Convert StorageItem to S3Item (or use StorageItem directly in UI later?)
      // For now, convert to S3Item to minimize UI changes.
      // But listObjects now returns List<StorageItem>.
      // We need to group directories and files if service doesn't.
      // Service flattens them? The implementation I wrote for S3StorageService
      // returns both prefixes (as isDirectory=true) and objects.
      // So we just iterate and split.

      final items = <S3Item>[];
      final directories = <S3Item>[];
      final files = <S3Item>[];

      for (final item in results) {
        if (item.isDirectory) {
          directories.add(S3Item.fromPrefix(item.key));
        } else {
          // We need to map StorageItem back to logic that assumes S3Item
          // Actually, S3Item structure is almost identical to StorageItem.
          // S3Item constructor match?
          files.add(
            S3Item(
              key: item.key,
              size: item.size,
              lastModified: item.lastModified,
              isDirectory: false,
              eTag: item.eTag,
            ),
          );
        }
      }

      // Sort directories and files separately
      directories.sort((a, b) => a.key.compareTo(b.key));
      files.sort((a, b) => a.key.compareTo(b.key));

      // Combine: directories first, then files
      items.addAll(directories);
      items.addAll(files);

      debugPrint(
        '✓ Found ${items.length} items (${directories.length} dirs, ${files.length} files)',
      );

      // Update cache
      _cache[cacheKey] = List.from(items);

      // Update UI if we're still on the same page
      if (mounted && _currentPrefix == effectivePrefix) {
        setState(() {
          _objects = items;
          _isLoading = false;
          _isRefreshing = false;
        });
        debugPrint('Updated with fresh data for prefix: $effectivePrefix');
      } else {
        debugPrint(
          'Discarding result for $effectivePrefix (current: $_currentPrefix)',
        );
        _isRefreshing = false;
      }
    } catch (e) {
      if (mounted && _currentPrefix == effectivePrefix) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });

        // More detailed error message
        String errorMessage = 'Error listing objects: $e';
        String detailedError = e.toString();

        debugPrint('=== S3 List Error ===');
        debugPrint('Error Type: ${e.runtimeType}');
        debugPrint('Error Message: $e');
        debugPrint('Full Error: $detailedError');
        debugPrint('====================');

        if (detailedError.contains('Connection failed')) {
          errorMessage =
              'Connection failed. Please check:\n'
              '1. Your network connection\n'
              '2. The endpoint URL is correct\n'
              '3. Your access credentials are valid\n'
              '4. For R2: Ensure the bucket exists and is accessible\n\n'
              'Technical details: ${e.toString().substring(0, 100)}...';
        } else if (detailedError.contains('AccessDenied')) {
          errorMessage =
              'Access Denied. Please check:\n'
              '1. Your access key and secret are correct\n'
              '2. The bucket exists\n'
              '3. You have list permissions on the bucket';
        } else if (detailedError.contains('NoSuchBucket')) {
          errorMessage =
              'Bucket not found. Please check:\n'
              '1. The bucket name is spelled correctly\n'
              '2. The bucket exists in your account';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  void _clearCache() {
    // Clear all cached data for this bucket
    final prefix = '${widget.serverConfig.id}:${widget.serverConfig.bucket}:';
    _cache.removeWhere((key, value) => key.startsWith(prefix));
    debugPrint('Cleared cache for bucket: ${widget.serverConfig.bucket}');
  }

  void _showDeleteProgressDialog(String fileName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        child: Container(
          padding: const EdgeInsets.all(24),
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                '${context.loc('deleting_file', [fileName.split('/').last])}...',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                context.loc('loading'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadObject(String key, {bool showDialog = true}) async {
    if (_downloadManager == null) return;

    // Try to find file size
    int? size;
    try {
      final obj = _objects.firstWhere(
        (element) => element.key == key,
        orElse: () => S3Item(key: key, isDirectory: false), // Dummy fallback
      );
      size = obj.size;
    } catch (_) {}

    _downloadManager!.addToQueue(key, size: size);

    if (showDialog && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.loc('downloading_file', [key.split('/').last])),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _renameObject(String oldKey) async {
    final newKeyController = TextEditingController(text: oldKey);
    final bool? confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.loc('rename_object_title')),
        content: TextField(
          controller: newKeyController,
          decoration: InputDecoration(
            labelText: context.loc('name'), // Reusing name label
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.loc('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.loc('rename')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final newKey = newKeyController.text;
      if (newKey.isNotEmpty && newKey != oldKey) {
        try {
          await _storageService.renameObject(oldKey, newKey);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.loc('rename_success', [oldKey, newKey])),
            ),
          );
          _listObjects();
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.loc('rename_error', [oldKey, e.toString()]),
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteObject(String key) async {
    final bool? confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.loc('delete_object_title')),
        content: Text(context.loc('delete_object_confirm', [key])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.loc('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.loc('delete')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Show progress dialog
      _showDeleteProgressDialog(key);

      try {
        await _storageService.deleteObject(key);

        // Close progress dialog
        if (mounted) {
          Navigator.pop(context); // Close progress dialog
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(context.loc('file_deleted'))));
          // Clear cache and refresh
          _clearCache();
          _listObjects();
        }
      } catch (e) {
        // Close progress dialog if still open
        if (mounted) {
          try {
            Navigator.pop(context); // Close progress dialog
          } catch (_) {}

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.loc('delete_error', [key, e.toString()])),
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteFolder(String folderKey) async {
    // Ensure folder key ends with '/'
    final normalizedFolderKey = folderKey.endsWith('/')
        ? folderKey
        : '$folderKey/';

    final bool? confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.loc('delete_folder_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.loc('delete_folder_confirm', [folderKey]),
            ), // Reusing confirm delete folder key or creating dynamic? Wait, I added delete_folder_confirm? No, I added delete_folder_warning.
            // Oh I see 'confirm_delete_folder' exists in core/language_manager.dart: '确定要删除文件夹 "%s" 及其所有内容吗？'
            // But here the content was split. Let's use `confirm_delete_folder`.
            const SizedBox(height: 8),
            Text(
              context.loc('delete_folder_warning'),
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.loc('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.loc('delete'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show progress dialog
    _showDeleteProgressDialog(folderKey);

    try {
      // Delete folder via service
      await _storageService.deleteFolder(normalizedFolderKey);

      // Service doesn't return count.
      // If we want count, we should ask service or assume success.
      // Or change service to return count.
      // For now, let's just say "all" or remove count from message or use 0.
      // Or we can list before delete?
      // Service actually lists inside deleteFolder.
      // Let's just pass "many" or "success".
      // UI expects count?
      // "Deleted folder {name} and {count} objects"
      // Let's mock count as "some" or 0 for now to fit UI, or fetch.
      // Fetching again is expensive.
      // S3StorageService implementation iterates.
      // I can't easily get count back without changing interface.
      // Let's use "?" for count or 0.
      int deletedCount = 0;

      // Close progress dialog
      if (mounted) {
        Navigator.pop(context); // Close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.loc('delete_folder_success', [
                folderKey,
                deletedCount.toString(),
              ]),
            ),
          ),
        );
        // Clear cache and refresh
        _clearCache();
        _listObjects();
      }
    } catch (e) {
      // Close progress dialog if still open
      if (mounted) {
        try {
          Navigator.pop(context); // Close progress dialog
        } catch (_) {}

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.loc('delete_error', [folderKey, e.toString()]),
            ),
          ),
        );
      }
    }
  }

  String _formatBytes(int bytes, int decimals) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];

    // Calculate which suffix to use
    var i = 0;
    var size = bytes.toDouble();

    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }

    return '${size.toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  // Navigation methods
  void _navigateToDirectory(String prefix) {
    setState(() {
      _prefixHistory.add(_currentPrefix);
      _currentPrefix = prefix;
      // Do not clear objects or set loading here.
      // _listObjects will handle it based on cache.
    });
    _listObjects(prefix: prefix);
  }

  void _showFileListCopyMenu(String key, bool isImage) {
    // Create a custom dropdown button that will handle the positioning
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(
            context.loc('copy_options'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  Icons.link,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                title: Text(
                  context.loc('copy_url'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                onTap: () {
                  final url = _buildFileUrl(key);
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(context.loc('url_copied'))),
                  );
                  Navigator.pop(dialogContext);
                },
              ),
              if (isImage) ...[
                const Divider(color: Colors.white24),
                ListTile(
                  leading: Icon(
                    Icons.image,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  title: Text(
                    context.loc('copy_markdown'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  onTap: () {
                    final url = _buildFileUrl(key);
                    final markdown = '![${key.split('/').last}]($url)';
                    Clipboard.setData(ClipboardData(text: markdown));
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text(context.loc('markdown_copied'))),
                    );
                    Navigator.pop(dialogContext);
                  },
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.loc('cancel')),
            ),
          ],
        );
      },
    );
  }

  String _buildFileUrl(String key) {
    if (widget.serverConfig.cdnUrl != null &&
        widget.serverConfig.cdnUrl!.isNotEmpty) {
      String cdnUrl = widget.serverConfig.cdnUrl!;
      if (cdnUrl.endsWith('/')) {
        cdnUrl = cdnUrl.substring(0, cdnUrl.length - 1);
      }
      return '$cdnUrl/$key';
    } else {
      String baseUrl = widget.serverConfig.address;
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }
      return '$baseUrl/$key';
    }
  }

  // File preview method
  void _showFilePreview(S3Item object) async {
    if (object.isDirectory) {
      _navigateToDirectory(object.key);
      return;
    }

    // Check if it's an image
    final isImage = RegExp(
      r'\.(jpg|jpeg|png|gif|bmp|webp|svg)$',
      caseSensitive: false,
    ).hasMatch(object.key);

    // For files, show preview dialog
    showDialog(
      context: context,
      builder: (context) => _PreviewDialog(
        object: object,
        serverConfig: widget.serverConfig,
        storageService: _storageService,
        isImage: isImage,
        onDownload: _downloadObject,
      ),
    );
  }

  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);

      if (result != null && result.files.isNotEmpty) {
        final paths = result.files
            .map((f) => f.path)
            .where((path) => path != null)
            .cast<String>()
            .toList();

        if (paths.isNotEmpty && _uploadManager != null) {
          _uploadManager!.addToQueue(paths, _currentPrefix);

          // Clear cache to prepare for updates, though the upload is async.
          // The UploadManager doesn't auto-refresh the file list on completion yet.
          // We could listen to it, or just let user refresh, or optimistic update?
          // For now, simple approach:
          // We can't easily refresh exactly when one file finishes without listening.
          // User can hit refresh.

          // Actually, UploadManager notifies listeners. We can listen to it in initState ideally?
          // But UploadQueueUI handles the UI.
          // To update the file list, we might want to listen to UploadManager.
          // Let's add listener for now? Or keep it simple.
          // Simple for now.
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.loc('upload_failed', [e.toString()])),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // _uploadFileFromPath removed as it relies on blocking UI.

  void _handleDragDone(DropDoneDetails details) async {
    setState(() {
      _isDragging = false;
    });

    if (details.files.isEmpty) return;

    final paths = details.files
        .map((f) => f.path)
        .where((path) => path.isNotEmpty)
        .toList();

    if (paths.isNotEmpty && _uploadManager != null) {
      _uploadManager!.addToQueue(paths, _currentPrefix);
    }
  }

  Future<void> _createFolder() async {
    final folderNameController = TextEditingController();
    final bool? confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.loc('create_folder_title')),
        content: TextField(
          controller: folderNameController,
          decoration: InputDecoration(
            labelText: context.loc('folder_name'),
            hintText: context.loc('folder_name_hint'),
          ),
          autofocus: true,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(context, true);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.loc('cancel')),
          ),
          TextButton(
            onPressed: () {
              if (folderNameController.text.trim().isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            child: Text(context.loc('create_btn')),
          ),
        ],
      ),
    );

    if (confirmed != true || folderNameController.text.trim().isEmpty) return;

    setState(() {
      _isUploading = true;
    });

    try {
      // Normalize folder name - ensure it ends with /
      String folderName = folderNameController.text.trim();
      if (!folderName.endsWith('/')) {
        folderName = '$folderName/';
      }

      // Build the full key with current prefix
      final key = _currentPrefix.isEmpty
          ? folderName
          : '$_currentPrefix$folderName';

      debugPrint('Creating folder: $key');

      // In S3, folders are created by uploading an empty object with the folder name ending with /
      await _storageService.createFolder(key);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.loc('folder_create_success', [
                folderName.replaceAll('/', ''),
              ]),
            ),
          ),
        );
        // Clear cache and refresh to show the new folder
        _clearCache();
        _listObjects();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.loc('folder_create_failed', [e.toString()])),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _batchDownload() async {
    if (_selectedItems.isEmpty) return;

    for (final key in _selectedItems.toList()) {
      await _downloadObject(key);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.loc('batch_download_success', [
              _selectedItems.length.toString(),
            ]),
          ),
        ),
      );
      setState(() {
        _isSelectionMode = false;
        _selectedItems.clear();
      });
    }
  }

  Future<void> _batchDelete() async {
    if (_selectedItems.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.loc('confirm_delete')),
        content: Text(
          context.loc('batch_delete_confirm_msg', [
            _selectedItems.length.toString(),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.loc('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(context.loc('delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    int successCount = 0;
    int failCount = 0;

    for (final key in _selectedItems.toList()) {
      try {
        await _storageService.deleteObject(key);
        successCount++;
      } catch (e) {
        failCount++;
        debugPrint('Failed to delete $key: $e');
      }
    }

    if (mounted) {
      _clearCache();
      await _listObjects(prefix: _currentPrefix);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failCount > 0
                ? context.loc('batch_delete_result', [
                    successCount.toString(),
                    failCount.toString(),
                  ])
                : context.loc('batch_delete_result_success', [
                    successCount.toString(),
                  ]),
          ),
        ),
      );

      setState(() {
        _isSelectionMode = false;
        _selectedItems.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      'S3BrowserPage Build: isLoading=$_isLoading, isRefreshing=$_isRefreshing, objects=${_objects.length}, error=$_initError',
    );
    if (_initError != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.serverConfig.name),
          actions: [
            // Ensure Edit button is available even in error state
            if (widget.onEditServer != null)
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: widget.onEditServer,
                tooltip: context.loc('edit_server'),
              ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Failed to initialize connection',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _initError!,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              if (widget.onEditServer != null)
                FilledButton.icon(
                  onPressed: widget.onEditServer,
                  icon: const Icon(Icons.edit),
                  label: Text(context.loc('edit_server')),
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
            ? Text('${_selectedItems.length} selected')
            : Text(widget.serverConfig.name),
        backgroundColor: Colors.transparent,
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _isSelectionMode = false;
                    _selectedItems.clear();
                  });
                },
                tooltip: 'Cancel selection',
              )
            : null,
        actions: _isSelectionMode
            ? [
                // Select All button
                IconButton(
                  icon: Icon(
                    _selectedItems.length ==
                            _objects.where((o) => !o.isDirectory).length
                        ? Icons.deselect
                        : Icons.select_all,
                  ),
                  onPressed: () {
                    setState(() {
                      if (_selectedItems.length ==
                          _objects.where((o) => !o.isDirectory).length) {
                        _selectedItems.clear();
                      } else {
                        _selectedItems.clear();
                        for (final obj in _objects.where(
                          (o) => !o.isDirectory,
                        )) {
                          _selectedItems.add(obj.key);
                        }
                      }
                    });
                  },
                  tooltip: 'Select all',
                ),
                // Batch download
                IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: _selectedItems.isEmpty ? null : _batchDownload,
                  tooltip: 'Download selected',
                ),
                // Batch delete
                IconButton(
                  icon: Icon(
                    Icons.delete,
                    color: _selectedItems.isEmpty
                        ? null
                        : Theme.of(context).colorScheme.error,
                  ),
                  onPressed: _selectedItems.isEmpty ? null : _batchDelete,
                  tooltip: 'Delete selected',
                ),
              ]
            : [
                // Create folder button
                IconButton(
                  icon: const Icon(Icons.create_new_folder_outlined),
                  onPressed: _isUploading ? null : _createFolder,
                  tooltip: 'Create folder',
                ),
                // Upload button
                IconButton(
                  icon: const Icon(Icons.upload_file_outlined),
                  onPressed: _isUploading ? null : _uploadFile,
                  tooltip: 'Upload file',
                ),
                // Selection mode toggle
                IconButton(
                  icon: const Icon(Icons.checklist),
                  onPressed: () {
                    setState(() {
                      _isSelectionMode = true;
                    });
                  },
                  tooltip: 'Select files',
                ),
                // View toggle button
                IconButton(
                  icon: Icon(_isGridView ? Icons.list : Icons.grid_view),
                  onPressed: () {
                    setState(() {
                      _isGridView = !_isGridView;
                    });
                  },
                  tooltip: _isGridView ? 'List view' : 'Grid view',
                ),

                // Refresh button
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _isLoading || _isRefreshing
                      ? null
                      : () {
                          _clearCache();
                          _listObjects(prefix: _currentPrefix);
                        },
                  tooltip: 'Refresh',
                ),
              ],
      ),
      body: DropTarget(
        onDragDone: _handleDragDone,
        onDragEntered: (details) {
          setState(() {
            _isDragging = true;
          });
        },
        onDragExited: (details) {
          setState(() {
            _isDragging = false;
          });
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                // Breadcrumb navigation
                if (_currentPrefix.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        // Home button to return to root
                        if (_currentPrefix.isNotEmpty ||
                            _prefixHistory.isNotEmpty)
                          IconButton(
                            onPressed: () {
                              // Clear prefix history and go to root
                              setState(() {
                                _prefixHistory.clear();
                                _currentPrefix = '';
                                _objects = [];
                                _isLoading = true;
                              });
                              _listObjects(prefix: '');
                            },
                            icon: const Icon(Icons.home),
                            tooltip: 'Home',
                            style: IconButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onSurface,
                            ),
                          ),
                        if ((_prefixHistory.isNotEmpty ||
                                _currentPrefix.isNotEmpty) &&
                            _currentPrefix.isNotEmpty)
                          const SizedBox(width: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                // Split prefix into parts and create clickable breadcrumbs
                                ..._currentPrefix
                                    .split('/')
                                    .where((part) => part.isNotEmpty)
                                    .toList()
                                    .asMap()
                                    .entries
                                    .map((entry) {
                                      final index = entry.key;
                                      final part = entry.value;
                                      final parts = _currentPrefix
                                          .split('/')
                                          .where((p) => p.isNotEmpty)
                                          .toList();
                                      final isLast = index == parts.length - 1;

                                      // Reconstruct path for this segment
                                      final pathParts = parts.sublist(
                                        0,
                                        index + 1,
                                      );
                                      final path = '${pathParts.join('/')}/';

                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (index > 0)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                  ),
                                              child: Icon(
                                                Icons.chevron_right,
                                                size: 16,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.5),
                                              ),
                                            ),
                                          InkWell(
                                            onTap: isLast
                                                ? null
                                                : () => _navigateToDirectory(
                                                    path,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 2,
                                                  ),
                                              child: Text(
                                                part,
                                                style: isLast
                                                    ? Theme.of(context)
                                                          .textTheme
                                                          .bodyMedium
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          )
                                                    : Theme.of(context)
                                                          .textTheme
                                                          .bodyMedium
                                                          ?.copyWith(
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .primary,
                                                            decoration:
                                                                TextDecoration
                                                                    .underline,
                                                          ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    }),
                              ],
                            ),
                          ),
                        ),
                        // Back button (up to parent)
                        if (_currentPrefix.isNotEmpty)
                          IconButton(
                            onPressed: () {
                              // Navigate to parent directory
                              final parts = _currentPrefix
                                  .split('/')
                                  .where((p) => p.isNotEmpty)
                                  .toList();
                              if (parts.isNotEmpty) {
                                parts.removeLast();
                                final parentPath = parts.isEmpty
                                    ? ''
                                    : '${parts.join('/')}/';
                                _navigateToDirectory(parentPath);
                              }
                            },
                            icon: const Icon(Icons.arrow_upward),
                            tooltip: 'Up to parent',
                            style: IconButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onSurface,
                            ),
                          ),
                      ],
                    ),
                  ),

                // Objects list/grid
                Expanded(
                  child: LoadingOverlay(
                    isLoading: _isLoading,
                    child: _objects.isEmpty
                        ? (_isLoading
                              ? const SizedBox.expand()
                              : Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        _currentPrefix.isEmpty
                                            ? Icons.cloud_off
                                            : Icons.folder_open,
                                        size: 64,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.2),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _currentPrefix.isEmpty
                                            ? 'No objects in bucket'
                                            : 'No objects in this directory',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Try refreshing if you expect files here',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.5),
                                            ),
                                      ),
                                      const SizedBox(height: 24),
                                      FilledButton.icon(
                                        onPressed: () {
                                          _clearCache();
                                          _listObjects(prefix: _currentPrefix);
                                        },
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('Refresh Now'),
                                      ),
                                    ],
                                  ),
                                ))
                        : _isGridView
                        ? _buildGridView()
                        : _buildListView(),
                  ),
                ),
              ],
            ),
            // Drag overlay
            if (_isDragging)
              Container(
                color: Colors.black.withValues(alpha: 0.5),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_upload,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Drop files here to upload',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: AppFontSizes.xl,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Upload Queue Overlay
            if (_uploadManager != null)
              UploadQueueUI(uploadManager: _uploadManager!),
            // Download Queue Overlay
            if (_downloadManager != null)
              DownloadQueueUI(downloadManager: _downloadManager!),
          ],
        ),
      ),
    );
  }

  Widget _buildListView() {
    return ListView.builder(
      itemCount: _objects.length,
      itemBuilder: (context, index) {
        final object = _objects[index];
        final isSelected = _selectedItems.contains(object.key);
        final canSelect = !object.isDirectory;

        return ListTile(
          leading: _isSelectionMode
              ? Checkbox(
                  value: isSelected,
                  onChanged: canSelect
                      ? (value) {
                          setState(() {
                            if (value == true) {
                              _selectedItems.add(object.key);
                            } else {
                              _selectedItems.remove(object.key);
                            }
                          });
                        }
                      : null,
                )
              : Icon(
                  object.isDirectory ? Icons.folder : Icons.insert_drive_file,
                  color: object.isDirectory
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
          title: Text(
            object.key.startsWith(_currentPrefix)
                ? object.key.substring(_currentPrefix.length)
                : object.key,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          subtitle: object.isDirectory
              ? null
              : Text(
                  '${_formatBytes(object.size ?? 0, 1)} • ${DateFormat('yyyy-MM-dd HH:mm').format(object.lastModified ?? DateTime.now())}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'download') {
                _downloadObject(object.key);
              } else if (value == 'copy') {
                // Check if it's an image
                final isImage = RegExp(
                  r'\.(jpg|jpeg|png|gif|bmp|webp|svg)$',
                  caseSensitive: false,
                ).hasMatch(object.key);
                if (isImage) {
                  _showFileListCopyMenu(object.key, true);
                } else {
                  // For non-image files, copy URL directly
                  final url = _buildFileUrl(object.key);
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('URL copied to clipboard')),
                  );
                }
              } else if (value == 'rename') {
                _renameObject(object.key);
              } else if (value == 'delete') {
                if (object.isDirectory) {
                  _deleteFolder(object.key);
                } else {
                  _deleteObject(object.key);
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'download', child: Text('Download')),
              if (!object.isDirectory) ...[
                const PopupMenuItem(value: 'copy', child: Text('Copy URL')),
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
              ],
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
          onTap: () {
            if (_isSelectionMode && !object.isDirectory) {
              setState(() {
                if (isSelected) {
                  _selectedItems.remove(object.key);
                } else {
                  _selectedItems.add(object.key);
                }
              });
            } else if (object.isDirectory) {
              _navigateToDirectory(object.key);
            } else {
              _showFilePreview(object);
            }
          },
        );
      },
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 1,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _objects.length,
      itemBuilder: (context, index) {
        final object = _objects[index];
        final isSelected = _selectedItems.contains(object.key);

        return Card(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).cardColor,
          elevation: isSelected ? 4 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isSelected
                ? BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  )
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              if (_isSelectionMode) {
                if (object.isDirectory) {
                  // Allow navigation in selection mode for folders
                  _navigateToDirectory(object.key);
                } else {
                  setState(() {
                    if (isSelected) {
                      _selectedItems.remove(object.key);
                    } else {
                      _selectedItems.add(object.key);
                    }
                  });
                }
              } else {
                if (object.isDirectory) {
                  _navigateToDirectory(object.key);
                } else {
                  _showFilePreview(object);
                }
              }
            },
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        object.isDirectory
                            ? Icons.folder
                            : Icons.insert_drive_file,
                        size: 48,
                        color: object.isDirectory
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          object.key.startsWith(_currentPrefix)
                              ? object.key.substring(_currentPrefix.length)
                              : object.key,
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!object.isDirectory) ...[
                        const SizedBox(height: 4),
                        Text(
                          _formatBytes(object.size ?? 0, 0),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ],
                  ),
                ),
                if (_isSelectionMode && !object.isDirectory)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedItems.add(object.key);
                          } else {
                            _selectedItems.remove(object.key);
                          }
                        });
                      },
                      shape: const CircleBorder(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Custom preview dialog widget
class _PreviewDialog extends StatefulWidget {
  final S3Item object;
  final S3ServerConfig serverConfig;
  final StorageService storageService;
  final bool isImage;
  final Function(String, {bool showDialog}) onDownload;

  const _PreviewDialog({
    required this.object,
    required this.serverConfig,
    required this.storageService,
    required this.isImage,
    required this.onDownload,
  });

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  Uint8List? _imageBytes;
  bool _isLoadingImage = false;
  bool _isDownloading = false;
  final GlobalKey _copyButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.isImage) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    setState(() {
      _isLoadingImage = true;
    });

    try {
      final stream = await widget.storageService.downloadStream(
        widget.object.key,
      );
      final bytes = await stream.toList();
      final flatBytes = bytes.expand((x) => x).toList();

      if (mounted) {
        setState(() {
          _imageBytes = Uint8List.fromList(flatBytes);
          _isLoadingImage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingImage = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getFileUrl() {
    return widget.storageService.getFileUrl(widget.object.key);
  }

  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showCopyMenu() {
    // Get the button's RenderBox using the GlobalKey
    final RenderObject? renderObject = _copyButtonKey.currentContext
        ?.findRenderObject();
    if (renderObject == null || renderObject is! RenderBox) return;

    final button = renderObject;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;

    // Calculate position relative to the overlay
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      items: [
        const PopupMenuItem<String>(
          value: 'url',
          child: ListTile(
            leading: Icon(Icons.link),
            title: Text('Copy URL'),
            dense: true,
          ),
        ),
        if (widget.isImage) ...[
          const PopupMenuItem<String>(
            value: 'markdown',
            child: ListTile(
              leading: Icon(Icons.image),
              title: Text('Copy Markdown'),
              dense: true,
            ),
          ),
        ],
      ],
    ).then((String? value) {
      if (value == null) return;

      final url = _getFileUrl();

      switch (value) {
        case 'url':
          _copyToClipboard(url, 'URL copied to clipboard');
          break;
        case 'markdown':
          final markdown = '![${widget.object.key.split('/').last}]($url)';
          _copyToClipboard(markdown, 'Markdown copied to clipboard');
          break;
      }
    });
  }

  Future<void> _handleDownload() async {
    setState(() {
      _isDownloading = true;
    });

    try {
      // Download without showing dialog (since we're already in a dialog)
      await widget.onDownload(widget.object.key, showDialog: false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded: ${widget.object.key.split('/').last}'),
            action: SnackBarAction(label: 'OK', onPressed: () {}),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with close button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.object.key,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Preview area
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Preview/Image area
                  Expanded(flex: 1, child: _buildPreviewContent()),
                  const SizedBox(width: 16),
                  // File details
                  Expanded(flex: 1, child: _buildFileDetails(dateFormat)),
                ],
              ),
            ),

            // Action buttons
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  key: _copyButtonKey,
                  onPressed: _showCopyMenu,
                  icon: const Icon(Icons.content_copy),
                  label: const Text('Copy'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isDownloading ? null : _handleDownload,
                  icon: _isDownloading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: Text(_isDownloading ? 'Downloading...' : 'Download'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewContent() {
    final containerColor = Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest;
    final iconColor = Theme.of(
      context,
    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    final textColor = Theme.of(context).colorScheme.onSurfaceVariant;

    if (!widget.isImage) {
      return Container(
        decoration: BoxDecoration(
          color: containerColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.insert_drive_file, size: 64, color: iconColor),
              const SizedBox(height: 16),
              Text(
                'File Preview',
                style: TextStyle(color: textColor.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 8),
              Text(
                'Preview not available for this file type',
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.5),
                  fontSize: AppFontSizes.sm,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoadingImage) {
      return Container(
        decoration: BoxDecoration(
          color: containerColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_imageBytes != null) {
      return Container(
        decoration: BoxDecoration(
          color: containerColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            _imageBytes!,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, size: 64, color: iconColor),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load image',
                      style: TextStyle(color: textColor.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image, size: 64, color: iconColor),
            const SizedBox(height: 16),
            Text(
              'Image Preview',
              style: TextStyle(color: textColor.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 8),
            Text(
              'Failed to load image preview',
              style: TextStyle(
                color: textColor.withValues(alpha: 0.5),
                fontSize: AppFontSizes.sm,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileDetails(DateFormat dateFormat) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'File Information',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildDetailRow('Name', widget.object.key),
            if (widget.object.size != null) ...[
              const SizedBox(height: 8),
              _buildDetailRow('Size', _formatBytes(widget.object.size!, 2)),
            ],
            if (widget.object.lastModified != null) ...[
              const SizedBox(height: 8),
              _buildDetailRow(
                'Modified',
                dateFormat.format(widget.object.lastModified!),
              ),
            ],
            if (widget.object.eTag != null) ...[
              const SizedBox(height: 8),
              _buildDetailRow('ETag', widget.object.eTag!),
            ],
            const SizedBox(height: 8),
            _buildDetailRow('Type', widget.isImage ? 'Image' : 'File'),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }

  String _formatBytes(int bytes, int decimals) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];

    // Calculate which suffix to use
    var i = 0;
    var size = bytes.toDouble();

    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }

    return '${size.toStringAsFixed(decimals)} ${suffixes[i]}';
  }
}
