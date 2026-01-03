import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:ploys3/models/s3_server_config.dart';
import 'package:ploys3/s3_config_page.dart';
import 'package:ploys3/s3_browser_page.dart';
import 'package:ploys3/settings_page.dart';
import 'package:ploys3/core/design_system.dart';
import 'package:ploys3/core/theme_manager.dart';
import 'package:ploys3/core/language_manager.dart';
import 'package:ploys3/core/localization.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:ploys3/widgets/window_title_bar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 设置系统UI样式
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const App());

  if (const [TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux].contains(defaultTargetPlatform)) {
    doWhenWindowReady(() {
      const initialSize = Size(1280, 800);
      appWindow.minSize = const Size(800, 600);
      appWindow.size = initialSize;
      appWindow.alignment = Alignment.center;
      appWindow.title = "S3 Manager";
      appWindow.show();
    });
  }
}

/// 主应用
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeManager.instance,
      builder: (context, child) {
        return MaterialApp(
          title: 'Ploy S3',
          theme: ThemeManager.instance.currentTheme,
          debugShowCheckedModeBanner: false,
          home: const LanguageProvider(child: ThemeProvider(child: AppShell())),
        );
      },
    );
  }
}

/// 应用外壳
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  List<S3ServerConfig> _serverConfigs = [];
  S3ServerConfig? _selectedServerConfig;
  bool _isSidebarExtended = true;
  double _sidebarWidth = 220.0;
  bool _isHoveringResizeHandle = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> serverConfigsStrings = prefs.getStringList('server_configs') ?? [];
    setState(() {
      _serverConfigs = serverConfigsStrings.map((config) => S3ServerConfig.fromJson(json.decode(config))).toList();
    });
  }

  Future<void> _deleteServer(S3ServerConfig server) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> serverConfigsStrings = prefs.getStringList('server_configs') ?? [];
    serverConfigsStrings.removeWhere((configStr) {
      final config = S3ServerConfig.fromJson(json.decode(configStr));
      return config.id == server.id;
    });
    await prefs.setStringList('server_configs', serverConfigsStrings);
    // Clear selection if deleted server was selected
    if (_selectedServerConfig?.id == server.id) {
      setState(() {
        _selectedServerConfig = null;
      });
    }
    await _loadConfigs();
  }

  void _showServerContextMenu(BuildContext context, Offset position, S3ServerConfig server) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem<String>(
          value: 'edit',
          child: Row(
            children: [const Icon(Icons.edit, size: 18), const SizedBox(width: 8), Text(context.loc('edit_server'))],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 18, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 8),
              Text(context.loc('delete'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'edit') {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                S3ConfigPage(existingConfig: server, onSave: _loadConfigs),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              const curve = Curves.easeOutQuart;
              var scaleAnimation = Tween(
                begin: 0.0,
                end: 1.0,
              ).animate(CurvedAnimation(parent: animation, curve: curve));
              var fadeAnimation = Tween(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: animation, curve: curve));
              return ScaleTransition(
                scale: scaleAnimation,
                alignment: Alignment.topLeft,
                child: FadeTransition(opacity: fadeAnimation, child: child),
              );
            },
            transitionDuration: const Duration(milliseconds: 400),
            reverseTransitionDuration: const Duration(milliseconds: 300),
          ),
        );
      } else if (value == 'delete') {
        _showDeleteConfirmation(context, server);
      }
    });
  }

  void _showDeleteConfirmation(BuildContext context, S3ServerConfig server) {
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.loc('delete_server_title')),
        content: Text(context.loc('delete_server_message').replaceAll('{name}', server.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.loc('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: Text(context.loc('delete')),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        _deleteServer(server);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobilePlatform = const [TargetPlatform.iOS, TargetPlatform.android].contains(defaultTargetPlatform);
        final useDrawer = isMobilePlatform;

        // Auto-collapse if width is small
        if (!useDrawer && constraints.maxWidth < 600 && _isSidebarExtended) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _isSidebarExtended = false;
              });
            }
          });
        }

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
          drawer: useDrawer
              ? Drawer(
                  width: math.min(constraints.maxWidth * 0.85, 320),
                  child: SafeArea(
                    child: _buildSidebar(
                      context,
                      isSidebarExtended: true,
                      sidebarWidth: math.min(constraints.maxWidth * 0.85, 320),
                      isDrawer: true,
                      onDrawerClose: () => _scaffoldKey.currentState?.closeDrawer(),
                    ),
                  ),
                )
              : null,
          body: Column(
            children: [
              // Custom Title Bar
              const WindowTitleBar(),
              Expanded(
                child: useDrawer
                    ? _buildContentArea(
                        context,
                        margin: const EdgeInsets.all(0),
                        onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
                      )
                    : Row(
                        children: [
                          _buildSidebar(context, isSidebarExtended: _isSidebarExtended, sidebarWidth: _sidebarWidth),

                          // Resize Handle
                          if (!useDrawer)
                            MouseRegion(
                              cursor: SystemMouseCursors.resizeColumn,
                              onEnter: (_) => setState(() => _isHoveringResizeHandle = true),
                              onExit: (_) => setState(() => _isHoveringResizeHandle = false),
                              child: GestureDetector(
                                onHorizontalDragUpdate: (details) {
                                  setState(() {
                                    // Only resize if extended
                                    if (!_isSidebarExtended) {
                                      if (details.delta.dx > 5) {
                                        _isSidebarExtended = true;
                                      }
                                      return;
                                    }

                                    _sidebarWidth += details.delta.dx;
                                    if (_sidebarWidth < 200) _sidebarWidth = 200;
                                    if (_sidebarWidth > 400) _sidebarWidth = 400;
                                  });
                                },
                                child: Container(
                                  width: 8,
                                  height: double.infinity,
                                  color: Colors.transparent,
                                  child: Center(
                                    child: Container(
                                      width: 2,
                                      color: _isHoveringResizeHandle
                                          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
                                          : Colors.transparent,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          Expanded(child: _buildContentArea(context, margin: const EdgeInsets.fromLTRB(0, 0, 8, 8))),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebar(
    BuildContext context, {
    required bool isSidebarExtended,
    required double sidebarWidth,
    bool isDrawer = false,
    VoidCallback? onDrawerClose,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: isSidebarExtended ? sidebarWidth : 80,
      margin: isDrawer ? EdgeInsets.zero : const EdgeInsets.fromLTRB(8, 0, 0, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: NavigationRail(
          extended: isSidebarExtended,
          minExtendedWidth: sidebarWidth,
          backgroundColor: Colors.transparent,
          leading: Column(
            children: [
              if (isSidebarExtended)
                SizedBox(
                  height: 60,
                  width: sidebarWidth,
                  child: Stack(
                    children: [
                      // Logo - Vertically aligned
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context).colorScheme.primary,
                                    Theme.of(context).colorScheme.secondary,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.cloud_outlined, size: 20, color: Colors.white),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.loc('app_name_s3'),
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                Text(
                                  context.loc('app_name_manager'),
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    fontSize: AppFontSizes.xs,
                                    letterSpacing: 2,
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Collapse Button - Absolute Top Right
                      if (!isDrawer)
                        Positioned(
                          top: 15,
                          right: 4,
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              Icons.menu_open_rounded,
                              color: Theme.of(context).colorScheme.onSurface,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _isSidebarExtended = false;
                              });
                            },
                            tooltip: context.loc('collapse'),
                          ),
                        ),
                    ],
                  ),
                )
              else
                // Collapsed: Toggle acts as logo
                Container(
                  height: 60,
                  alignment: Alignment.center,
                  child: Tooltip(
                    message: context.loc('expand'),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            setState(() {
                              _isSidebarExtended = true;
                            });
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.cloud_outlined, size: 24, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              // Add Server Button
              if (isSidebarExtended)
                SizedBox(
                  width: sidebarWidth - 32,
                  child: AppComponents.primaryButton(
                    text: context.loc('add_new_server'),
                    icon: Icons.add,
                    onPressed: () {
                      onDrawerClose?.call();
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (context, animation, secondaryAnimation) => S3ConfigPage(onSave: _loadConfigs),
                        ),
                      );
                    },
                  ),
                )
              else
                Center(
                  child: Tooltip(
                    message: context.loc('add_new_server'),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            onDrawerClose?.call();
                            Navigator.push(
                              context,
                              PageRouteBuilder(
                                pageBuilder: (context, animation, secondaryAnimation) =>
                                    S3ConfigPage(onSave: _loadConfigs),
                              ),
                            );
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.add, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          indicatorColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
          indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          destinations: [
            ..._serverConfigs.map((server) {
              final isSelected = _selectedServerConfig?.id == server.id;
              return NavigationRailDestination(
                icon: Icon(
                  Icons.cloud_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                selectedIcon: Icon(Icons.cloud_done, size: 20, color: Theme.of(context).colorScheme.primary),
                label: GestureDetector(
                  onSecondaryTapDown: (details) {
                    _showServerContextMenu(context, details.globalPosition, server);
                  },
                  onLongPressStart: (details) {
                    _showServerContextMenu(context, details.globalPosition, server);
                  },
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: sidebarWidth - 80, // Prevent overflow
                    ),
                    child: Text(
                      server.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppFontSizes.md - 1,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 6),
              );
            }),
          ],
          trailing: Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Settings Button
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        onDrawerClose?.call();
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => const SettingsPage(),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: isSidebarExtended
                            ? Row(
                                children: [
                                  Icon(Icons.settings_outlined, color: Theme.of(context).colorScheme.primary, size: 20),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: Text(
                                      context.loc('settings'),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.primary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Icon(Icons.settings_outlined, color: Theme.of(context).colorScheme.primary, size: 24),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          onDestinationSelected: (index) {
            setState(() {
              _selectedServerConfig = _serverConfigs[index];
            });
            onDrawerClose?.call();
          },
          selectedIndex: _selectedServerConfig != null && _serverConfigs.isNotEmpty
              ? _serverConfigs.indexWhere((s) => s.id == _selectedServerConfig!.id)
              : null,
        ),
      ),
    );
  }

  Widget _buildContentArea(BuildContext context, {required EdgeInsets margin, VoidCallback? onOpenDrawer}) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _selectedServerConfig != null
            ? S3BrowserPage(
                serverConfig: _selectedServerConfig!,
                onEditServer: () {
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          S3ConfigPage(existingConfig: _selectedServerConfig!, onSave: _loadConfigs),
                    ),
                  );
                },
                onOpenDrawer: onOpenDrawer,
              )
            : Scaffold(
                appBar: onOpenDrawer != null
                    ? AppBar(
                        title: Text(context.loc("s3_manager")),
                        centerTitle: true,
                        leading: IconButton(icon: const Icon(Icons.menu), onPressed: onOpenDrawer),
                        elevation: 0,
                        scrolledUnderElevation: 0,
                        actions: [
                          IconButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                PageRouteBuilder(
                                  pageBuilder: (context, animation, secondaryAnimation) =>
                                      S3ConfigPage(onSave: _loadConfigs),
                                ),
                              );
                            },
                            icon: Icon(Icons.add),
                          ),
                        ],
                      )
                    : null,
                body: AppComponents.emptyState(
                  icon: Icons.cloud_off_outlined,
                  title: context.loc('no_server_selected'),
                  subtitle: context.loc('select_server_to_start'),
                  onAction: _serverConfigs.isEmpty
                      ? () {
                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) =>
                                  S3ConfigPage(onSave: _loadConfigs),
                            ),
                          );
                        }
                      : null,
                  actionText: _serverConfigs.isEmpty ? context.loc('add_new_server') : null,
                ),
              ),
      ),
    );
  }
}
