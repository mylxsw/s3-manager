import 'dart:typed_data';
import 'package:minio/minio.dart';
import 'package:s3_ui/core/storage/storage_service.dart';
import 'package:s3_ui/models/s3_server_config.dart';
import 'package:s3_ui/r2_connection_helper.dart';

class S3StorageService implements StorageService {
  final S3ServerConfig _config;
  late final Minio _minio;

  S3StorageService(this._config) {
    _initializeMinio();
  }

  void _initializeMinio() {
    // Use R2 helper for R2 endpoints logic reuse
    final uri = Uri.parse(_config.address);
    final isR2 = uri.host.contains('r2.cloudflarestorage.com');

    if (isR2) {
      _minio = R2ConnectionHelper.createR2Client(_config);
    } else {
      final endPoint = uri.host;
      final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      final useSSL = uri.scheme == 'https';
      final region = _config.region ?? 'us-east-1';

      _minio = Minio(
        endPoint: endPoint,
        port: port,
        accessKey: _config.accessKeyId,
        secretKey: _config.secretAccessKey,
        useSSL: useSSL,
        region: region,
      );
    }
  }

  @override
  String get id => _config.id;

  @override
  String get bucketName => _config.bucket;

  @override
  Future<List<StorageItem>> listObjects({String? prefix}) async {
    final stream = _minio.listObjects(bucketName, prefix: prefix ?? '');
    final results = await stream.toList();

    final items = <StorageItem>[];

    for (final result in results) {
      for (final p in result.prefixes) {
        items.add(StorageItem(key: p, isDirectory: true));
      }
      for (final obj in result.objects) {
        items.add(
          StorageItem(
            key: obj.key ?? '',
            isDirectory: false,
            size: obj.size,
            lastModified: obj.lastModified,
            eTag: obj.eTag,
          ),
        );
      }
    }

    // Sort logic can be moved here or kept in UI. Let's keep basic directory first structure if possible or let UI handle sort.
    // UI currently handles sorting. Let's return as is.
    return items;
  }

  @override
  Future<void> createFolder(String folderPath) async {
    await _minio.putObject(
      bucketName,
      folderPath,
      Stream.fromIterable([Uint8List(0)]),
    );
  }

  @override
  Future<void> deleteObject(String key) async {
    await _minio.removeObject(bucketName, key);
  }

  @override
  Future<void> deleteFolder(String folderPath) async {
    // Ensure folder key ends with '/'
    final normalizedFolderKey = folderPath.endsWith('/')
        ? folderPath
        : '$folderPath/';

    final stream = _minio.listObjects(bucketName, prefix: normalizedFolderKey);
    final results = await stream.toList();

    for (final result in results) {
      for (final obj in result.objects) {
        if (obj.key != null) {
          await _minio.removeObject(bucketName, obj.key!);
        }
      }
    }
  }

  @override
  Future<void> renameObject(String oldKey, String newKey) async {
    await _minio.copyObject(bucketName, newKey, '/$bucketName/$oldKey');
    await _minio.removeObject(bucketName, oldKey);
  }

  Future<Stream<Uint8List>> downloadStream(String key) async {
    final stream = await _minio.getObject(bucketName, key);
    return stream.cast<Uint8List>();
  }

  @override
  Future<void> uploadStream(
    String key,
    Stream<Uint8List> stream, {
    int? size,
    String? contentType,
  }) async {
    await _minio.putObject(bucketName, key, stream, size: size);
  }

  @override
  String getFileUrl(String key) {
    if (_config.cdnUrl != null && _config.cdnUrl!.isNotEmpty) {
      String cdnUrl = _config.cdnUrl!;
      if (cdnUrl.endsWith('/')) {
        cdnUrl = cdnUrl.substring(0, cdnUrl.length - 1);
      }
      return '$cdnUrl/$key';
    } else {
      String baseUrl = _config.address;
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }
      return '$baseUrl/$key';
    }
  }

  @override
  Future<void> testConnection() async {
    // Basic test: list buckets or list objects in root
    // R2 doesn't support listBuckets usually, so maybe listObjects
    await _minio.listObjects(bucketName).take(1).toList();
  }
}
