import 'dart:typed_data';

/// Represents a file or folder in the storage system
class StorageItem {
  final String key;
  final int? size;
  final DateTime? lastModified;
  final bool isDirectory;
  final String? eTag;

  StorageItem({
    required this.key,
    required this.isDirectory,
    this.size,
    this.lastModified,
    this.eTag,
  });
}

/// Abstract interface for storage services
abstract class StorageService {
  /// Unique identifier for this service instance (e.g., config ID)
  String get id;

  /// The name of the primary container (bucket)
  String get bucketName;

  /// List objects and directories in the given [prefix]
  Future<List<StorageItem>> listObjects({String? prefix});

  /// Create a folder (directory)
  Future<void> createFolder(String folderPath);

  /// Delete a single object
  Future<void> deleteObject(String key);

  /// Delete a folder and all its contents
  Future<void> deleteFolder(String folderPath);

  /// Rename an object
  Future<void> renameObject(String oldKey, String newKey);

  /// Create a readable stream for downloading a file
  Future<Stream<Uint8List>> downloadStream(String key);

  /// Upload a file from a stream
  Future<void> uploadStream(
    String key,
    Stream<Uint8List> stream, {
    int? size,
    String? contentType,
  });

  /// Get a public or CDN URL for the file
  String getFileUrl(String key);

  /// Check connection valid
  Future<void> testConnection();
}
