import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 语言枚举
enum AppLanguage {
  chinese('中文', 'zh', 'CN'),
  english('English', 'en', 'US');

  const AppLanguage(this.displayName, this.code, this.countryCode);

  final String displayName;
  final String code;
  final String countryCode;

  Locale get locale => Locale(code, countryCode);
}

/// 语言管理器
class LanguageManager extends ChangeNotifier {
  static LanguageManager? _instance;
  static LanguageManager get instance =>
      _instance ??= LanguageManager._internal();

  LanguageManager._internal() {
    _loadLanguage();
  }

  AppLanguage _currentLanguage = AppLanguage.chinese;

  AppLanguage get currentLanguage => _currentLanguage;

  /// 设置语言
  Future<void> setLanguage(AppLanguage language) async {
    _currentLanguage = language;
    await _saveLanguage();
    notifyListeners();
  }

  /// 获取本地化字符串
  String getLocalized(String key) {
    return _localizedStrings[_currentLanguage]?[key] ?? key;
  }

  /// 从SharedPreferences加载语言设置
  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString('app_language') ?? 'zh';

    _currentLanguage = AppLanguage.values.firstWhere(
      (lang) => lang.code == languageCode,
      orElse: () => AppLanguage.chinese,
    );

    notifyListeners();
  }

  /// 保存语言设置到SharedPreferences
  Future<void> _saveLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', _currentLanguage.code);
  }

  /// 本地化字符串映射
  static final Map<AppLanguage, Map<String, String>> _localizedStrings = {
    AppLanguage.chinese: {
      // 通用
      'ok': '确定',
      'cancel': '取消',
      'save': '保存',
      'delete': '删除',
      'edit': '编辑',
      'add': '添加',
      'close': '关闭',
      'confirm': '确认',
      'loading': '加载中...',
      'error': '错误',
      'success': '成功',
      'warning': '警告',
      'info': '信息',

      // 主页面
      's3_manager': 'S3 管理器',
      'add_new_server': '新服务器',
      'no_server_selected': '未选择服务器',
      'select_server_to_start': '选择一个服务器开始浏览',
      'settings': '设置',

      // 服务器列表
      'test_connection': '测试连接',
      'delete_server': '删除服务器',
      'delete_server_confirm': '确定要删除服务器 "%s" 吗？',

      // 配置页面
      'server_config': '服务器配置',
      'name': '名称',
      'address': '地址',
      'bucket': '存储桶',
      'access_key_id': '访问密钥 ID',
      'secret_access_key': '秘密访问密钥',
      'region': '区域（可选）',
      'cdn_url': 'CDN URL（可选）',
      'name_hint': '例如：我的个人 S3',
      'address_hint': 'https://s3.example.com',
      'bucket_hint': 'my-bucket',
      'access_key_hint': 'your-access-key-id',
      'secret_key_hint': 'your-secret-access-key',
      'region_hint': 'auto（用于 R2）或 us-east-1',
      'cdn_hint': 'https://cdn.example.com',
      'validation_required': '请输入 %s',

      // 文件浏览器
      'back': '返回',
      'home': '首页',
      'refresh': '刷新',
      'upload': '上传',
      'download': '下载',
      'copy_url': '复制 URL',
      'rename': '重命名',
      'delete_file': '删除文件',
      'delete_folder': '删除文件夹',
      'create_folder': '创建文件夹',
      'folder_name': '文件夹名称',
      'uploading': '上传中...',
      'downloading': '下载中...',
      'deleting': '删除中...',
      'file_uploaded': '文件已上传',
      'file_downloaded': '文件已下载',
      'file_deleted': '文件已删除',
      'folder_created': '文件夹已创建',
      'url_copied': 'URL 已复制到剪贴板',
      'markdown_copied': 'Markdown 已复制到剪贴板',
      'copy_options': '复制选项',

      // 设置页面
      'appearance_settings': '外观设置',
      'dark_mode': '主题',
      'dark_mode_desc': '启用深色主题',
      'language_settings': '语言设置',
      'language': '语言',
      'language_desc': '选择应用语言',
      'about': '关于',
      'version': '版本',

      // 错误信息
      'connection_error': '连接错误',
      'connection_failed_check':
          '连接失败。请检查：\n1. 网络连接\n2. 端点 URL 是否正确\n3. 访问凭据是否有效\n4. 对于 R2：确保存储桶存在且可访问',
      'access_denied': '访问被拒绝',
      'access_denied_check':
          '访问被拒绝。请检查：\n1. 访问密钥和密钥是否正确\n2. 存储桶是否存在\n3. 您是否具有存储桶的列表权限',
      'bucket_not_found': '存储桶未找到',
      'bucket_not_found_check': '存储桶未找到。请检查：\n1. 存储桶名称拼写是否正确\n2. 存储桶是否存在于您的账户中',

      // 确认对话框
      'confirm_delete': '确认删除',
      'confirm_delete_folder': '确定要删除文件夹 "%s" 及其所有内容吗？',
      'confirm_delete_file': '确定要删除文件 "%s" 吗？',
      'cancel_btn': '取消',
      'confirm_btn': '确认',

      // 新增翻译
      'title_add_server': '添加服务器',
      'title_edit_server': '编辑服务器',
      'edit_server': '编辑服务器',
      'collapse': '收起',
      'expand': '展开',
      'app_name_s3': 'S3',
      'app_name_manager': '管理器',
      'upload_failed': '上传失败：%s',
      'upload_success': '已上传 %s',
      'rename_object_title': '重命名对象',
      'delete_object_title': '删除对象',
      'delete_object_confirm': '确定要删除 "%s" 吗？',
      'delete_folder_title': '删除文件夹',
      'delete_folder_warning': '警告：这将删除其中的所有文件和子文件夹！',
      'delete_folder_success': '已删除文件夹 "%s" 和 %s 个对象',
      'rename_success': '已将 %s 重命名为 %s',
      'rename_error': '重命名 %s 时出错：%s',
      'delete_error': '删除 %s 时出错：%s',
      'uploading_file': '正在上传 %s...',
      'deleting_file': '正在删除 %s...',
      'upload_queue': '上传队列',
      'uploading_count': '正在上传 %s 个文件...',
      'upload_complete': '上传完成',
      'clear_completed': '清除已完成',
      'retry': '重试',
      'copy_link': '复制链接',
    },
    AppLanguage.english: {
      // Common
      'ok': 'OK',
      'cancel': 'Cancel',
      'save': 'Save',
      'delete': 'Delete',
      'edit': 'Edit',
      'add': 'Add',
      'close': 'Close',
      'confirm': 'Confirm',
      'loading': 'Loading...',
      'error': 'Error',
      'success': 'Success',
      'warning': 'Warning',
      'info': 'Info',

      // Main page
      's3_manager': 'S3 Manager',
      'add_new_server': 'New Server',
      'no_server_selected': 'No Server Selected',
      'select_server_to_start':
          'Select a server from the list to start browsing',
      'settings': 'Settings',

      // Server list
      'test_connection': 'Test Connection',
      'delete_server': 'Delete Server',
      'delete_server_confirm': 'Are you sure you want to delete server "%s"?',

      // Config page
      'server_config': 'Server Configuration',
      'name': 'Name',
      'address': 'Address',
      'bucket': 'Bucket',
      'access_key_id': 'Access Key ID',
      'secret_access_key': 'Secret Access Key',
      'region': 'Region (Optional)',
      'cdn_url': 'CDN URL (Optional)',
      'name_hint': 'e.g., My Personal S3',
      'address_hint': 'https://s3.example.com',
      'bucket_hint': 'my-bucket',
      'access_key_hint': 'your-access-key-id',
      'secret_key_hint': 'your-secret-access-key',
      'region_hint': 'auto (for R2) or us-east-1',
      'cdn_hint': 'https://cdn.example.com',
      'validation_required': 'Please enter %s',

      // File browser
      'back': 'Back',
      'home': 'Home',
      'refresh': 'Refresh',
      'upload': 'Upload',
      'download': 'Download',
      'copy_url': 'Copy URL',
      'rename': 'Rename',
      'delete_file': 'Delete File',
      'delete_folder': 'Delete Folder',
      'create_folder': 'Create Folder',
      'folder_name': 'Folder Name',
      'uploading': 'Uploading...',
      'downloading': 'Downloading...',
      'deleting': 'Deleting...',
      'file_uploaded': 'File uploaded',
      'file_downloaded': 'File downloaded',
      'file_deleted': 'File deleted',
      'folder_created': 'Folder created',
      'url_copied': 'URL copied to clipboard',
      'markdown_copied': 'Markdown copied to clipboard',
      'copy_options': 'Copy Options',
      'copy_markdown': 'Copy Markdown',

      // Settings page
      'appearance_settings': 'Appearance Settings',
      'dark_mode': 'Theme',
      'dark_mode_desc': 'Enable dark theme',
      'language_settings': 'Language Settings',
      'language': 'Language',
      'language_desc': 'Select app language',
      'about': 'About',
      'version': 'Version',

      // Error messages
      'connection_error': 'Connection Error',
      'connection_failed_check':
          'Connection failed. Please check:\n1. Your network connection\n2. The endpoint URL is correct\n3. Your access credentials are valid\n4. For R2: Ensure the bucket exists and is accessible',
      'access_denied': 'Access Denied',
      'access_denied_check':
          'Access denied. Please check:\n1. Your access key and secret are correct\n2. The bucket exists\n3. You have list permissions on the bucket',
      'bucket_not_found': 'Bucket Not Found',
      'bucket_not_found_check':
          'Bucket not found. Please check:\n1. The bucket name is spelled correctly\n2. The bucket exists in your account',

      // Confirm dialogs
      'confirm_delete': 'Confirm Delete',
      'confirm_delete_folder':
          'Are you sure you want to delete folder "%s" and all its contents?',
      'confirm_delete_file': 'Are you sure you want to delete file "%s"?',
      'cancel_btn': 'Cancel',
      'confirm_btn': 'Confirm',

      // New Translations
      'title_add_server': 'Add Server',
      'title_edit_server': 'Edit Server',
      'edit_server': 'Edit Server',
      'collapse': 'Collapse',
      'expand': 'Expand',
      'app_name_s3': 'S3',
      'app_name_manager': 'MANAGER',
      'upload_failed': 'Upload failed: %s',
      'upload_success': 'Uploaded %s',
      'rename_object_title': 'Rename Object',
      'delete_object_title': 'Delete Object',
      'delete_object_confirm': 'Are you sure you want to delete "%s"?',
      'delete_folder_title': 'Delete Folder',
      'delete_folder_warning':
          'Warning: This will delete all files and subfolders inside!',
      'delete_folder_success': 'Deleted folder "%s" and %s object(s)',
      'rename_success': 'Renamed %s to %s',
      'rename_error': 'Error renaming %s: %s',
      'delete_error': 'Error deleting %s: %s',
      'uploading_file': 'Uploading %s...',
      'deleting_file': 'Deleting %s...',
      'upload_queue': 'Upload Queue',
      'uploading_count': 'Uploading %s files...',
      'upload_complete': 'Upload Complete',
      'clear_completed': 'Clear Completed',
      'retry': 'Retry',
      'copy_link': 'Copy Link',
    },
  };
}

/// 语言提供者Widget
class LanguageProvider extends StatefulWidget {
  final Widget child;

  const LanguageProvider({super.key, required this.child});

  @override
  State<LanguageProvider> createState() => _LanguageProviderState();
}

class _LanguageProviderState extends State<LanguageProvider> {
  @override
  void initState() {
    super.initState();
    LanguageManager.instance.addListener(_onLanguageChanged);
  }

  @override
  void dispose() {
    LanguageManager.instance.removeListener(_onLanguageChanged);
    super.dispose();
  }

  void _onLanguageChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
