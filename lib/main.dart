import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:s3_ui/models/s3_server_config.dart';
import 'package:s3_ui/s3_config_page.dart';
import 'package:s3_ui/s3_browser_page.dart';
import 'package:s3_ui/settings_page.dart';
import 'package:s3_ui/core/design_system.dart';
import 'package:s3_ui/core/theme_manager.dart';
import 'package:s3_ui/core/language_manager.dart';
import 'package:s3_ui/core/localization.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:s3_ui/widgets/window_title_bar.dart';

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

  doWhenWindowReady(() {
    const initialSize = Size(1280, 800);
    appWindow.minSize = const Size(800, 600);
    appWindow.size = initialSize;
    appWindow.alignment = Alignment.center;
    appWindow.title = "S3 Manager";
    appWindow.show();
  });
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
          title: 'S3 Manager',
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

  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> serverConfigsStrings =
        prefs.getStringList('server_configs') ?? [];
    setState(() {
      _serverConfigs = serverConfigsStrings
          .map((config) => S3ServerConfig.fromJson(json.decode(config)))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Auto-collapse if width is small
        if (constraints.maxWidth < 600 && _isSidebarExtended) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _isSidebarExtended = false;
              });
            }
          });
        }

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
          body: WindowBorder(
            color: Colors.transparent,
            width: 0,
            child: Column(
              children: [
                // Custom Title Bar
                const WindowTitleBar(),
                Expanded(
                  child: Row(
                    children: [
                      // 左侧导航栏 - Floating Sidebar
                      Container(
                        width: _isSidebarExtended ? _sidebarWidth : 80,
                        margin: const EdgeInsets.fromLTRB(8, 0, 0, 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: NavigationRail(
                            extended: _isSidebarExtended,
                            minExtendedWidth: _sidebarWidth,
                            backgroundColor: Colors.transparent,
                            leading: Column(
                              children: [
                                if (_isSidebarExtended)
                                  SizedBox(
                                    height: 60,
                                    width: _sidebarWidth,
                                    child: Stack(
                                      children: [
                                        // Logo - Vertically aligned
                                        Positioned(
                                          top: 12,
                                          left: 12,
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      Theme.of(
                                                        context,
                                                      ).colorScheme.primary,
                                                      Theme.of(
                                                        context,
                                                      ).colorScheme.secondary,
                                                    ],
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: const Icon(
                                                  Icons.cloud_outlined,
                                                  size: 20,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    context.loc('app_name_s3'),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Theme.of(
                                                            context,
                                                          ).colorScheme.primary,
                                                        ),
                                                  ),
                                                  Text(
                                                    context.loc(
                                                      'app_name_manager',
                                                    ),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .labelSmall
                                                        ?.copyWith(
                                                          fontSize: 8,
                                                          letterSpacing: 2,
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .primary
                                                                  .withValues(
                                                                    alpha: 0.7,
                                                                  ),
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Collapse Button - Absolute Top Right
                                        Positioned(
                                          top: 15,
                                          right: 4,
                                          child: IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            icon: Icon(
                                              Icons.menu_open_rounded,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
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
                                            colors: [
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              Theme.of(
                                                context,
                                              ).colorScheme.secondary,
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            onTap: () {
                                              setState(() {
                                                _isSidebarExtended = true;
                                              });
                                            },
                                            child: const Padding(
                                              padding: EdgeInsets.all(8),
                                              child: Icon(
                                                Icons.cloud_outlined,
                                                size: 24,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                // Add Server Button
                                if (_isSidebarExtended)
                                  SizedBox(
                                    width: _sidebarWidth - 32,
                                    child: AppComponents.primaryButton(
                                      text: context.loc('add_new_server'),
                                      icon: Icons.add,
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          PageRouteBuilder(
                                            pageBuilder:
                                                (
                                                  context,
                                                  animation,
                                                  secondaryAnimation,
                                                ) => S3ConfigPage(
                                                  onSave: _loadConfigs,
                                                ),
                                            transitionsBuilder:
                                                (
                                                  context,
                                                  animation,
                                                  secondaryAnimation,
                                                  child,
                                                ) {
                                                  const curve =
                                                      Curves.easeOutQuart;

                                                  var scaleAnimation =
                                                      Tween(
                                                        begin: 0.0,
                                                        end: 1.0,
                                                      ).animate(
                                                        CurvedAnimation(
                                                          parent: animation,
                                                          curve: curve,
                                                        ),
                                                      );

                                                  var fadeAnimation =
                                                      Tween(
                                                        begin: 0.0,
                                                        end: 1.0,
                                                      ).animate(
                                                        CurvedAnimation(
                                                          parent: animation,
                                                          curve: curve,
                                                        ),
                                                      );

                                                  return ScaleTransition(
                                                    scale: scaleAnimation,
                                                    alignment:
                                                        Alignment.topLeft,
                                                    child: FadeTransition(
                                                      opacity: fadeAnimation,
                                                      child: child,
                                                    ),
                                                  );
                                                },
                                            transitionDuration: const Duration(
                                              milliseconds: 400,
                                            ),
                                            reverseTransitionDuration:
                                                const Duration(
                                                  milliseconds: 300,
                                                ),
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
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                PageRouteBuilder(
                                                  pageBuilder:
                                                      (
                                                        context,
                                                        animation,
                                                        secondaryAnimation,
                                                      ) => S3ConfigPage(
                                                        onSave: _loadConfigs,
                                                      ),
                                                  transitionsBuilder:
                                                      (
                                                        context,
                                                        animation,
                                                        secondaryAnimation,
                                                        child,
                                                      ) {
                                                        const curve =
                                                            Curves.easeOutQuart;

                                                        var scaleAnimation =
                                                            Tween(
                                                              begin: 0.0,
                                                              end: 1.0,
                                                            ).animate(
                                                              CurvedAnimation(
                                                                parent:
                                                                    animation,
                                                                curve: curve,
                                                              ),
                                                            );

                                                        var fadeAnimation =
                                                            Tween(
                                                              begin: 0.0,
                                                              end: 1.0,
                                                            ).animate(
                                                              CurvedAnimation(
                                                                parent:
                                                                    animation,
                                                                curve: curve,
                                                              ),
                                                            );

                                                        return ScaleTransition(
                                                          scale: scaleAnimation,
                                                          alignment:
                                                              Alignment.topLeft,
                                                          child: FadeTransition(
                                                            opacity:
                                                                fadeAnimation,
                                                            child: child,
                                                          ),
                                                        );
                                                      },
                                                  transitionDuration:
                                                      const Duration(
                                                        milliseconds: 400,
                                                      ),
                                                  reverseTransitionDuration:
                                                      const Duration(
                                                        milliseconds: 300,
                                                      ),
                                                ),
                                              );
                                            },
                                            child: const Padding(
                                              padding: EdgeInsets.all(8),
                                              child: Icon(
                                                Icons.add,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            indicatorColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.5),
                            indicatorShape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            destinations: [
                              ..._serverConfigs.map((server) {
                                final isSelected =
                                    _selectedServerConfig?.id == server.id;
                                return NavigationRailDestination(
                                  icon: Icon(
                                    Icons.cloud_outlined,
                                    size: 20,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.7),
                                  ),
                                  selectedIcon: Icon(
                                    Icons.cloud_done,
                                    size: 20,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  label: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          _sidebarWidth -
                                          80, // Prevent overflow
                                    ),
                                    child: Text(
                                      server.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                        color: isSelected
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                );
                              }),
                            ],
                            trailing: Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  // Settings Button
                                  Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 16,
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            PageRouteBuilder(
                                              pageBuilder:
                                                  (
                                                    context,
                                                    animation,
                                                    secondaryAnimation,
                                                  ) => const SettingsPage(),
                                              transitionsBuilder:
                                                  (
                                                    context,
                                                    animation,
                                                    secondaryAnimation,
                                                    child,
                                                  ) {
                                                    const begin = 0.0;
                                                    const end = 1.0;
                                                    const curve =
                                                        Curves.easeOutQuart;

                                                    var scaleAnimation =
                                                        Tween(
                                                          begin: begin,
                                                          end: end,
                                                        ).animate(
                                                          CurvedAnimation(
                                                            parent: animation,
                                                            curve: curve,
                                                          ),
                                                        );

                                                    var fadeAnimation =
                                                        Tween(
                                                          begin: 0.0,
                                                          end: 1.0,
                                                        ).animate(
                                                          CurvedAnimation(
                                                            parent: animation,
                                                            curve: curve,
                                                          ),
                                                        );

                                                    return ScaleTransition(
                                                      scale: scaleAnimation,
                                                      alignment:
                                                          Alignment.bottomLeft,
                                                      child: FadeTransition(
                                                        opacity: fadeAnimation,
                                                        child: child,
                                                      ),
                                                    );
                                                  },
                                              transitionDuration:
                                                  const Duration(
                                                    milliseconds: 400,
                                                  ),
                                              reverseTransitionDuration:
                                                  const Duration(
                                                    milliseconds: 300,
                                                  ),
                                            ),
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: _isSidebarExtended
                                              ? Row(
                                                  children: [
                                                    Icon(
                                                      Icons.settings_outlined,
                                                      color: Theme.of(
                                                        context,
                                                      ).colorScheme.primary,
                                                      size: 20,
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Text(
                                                      context.loc('settings'),
                                                      style: TextStyle(
                                                        color: Theme.of(
                                                          context,
                                                        ).colorScheme.primary,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              : Icon(
                                                  Icons.settings_outlined,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                  size: 24,
                                                ),
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
                            },
                            selectedIndex:
                                _selectedServerConfig != null &&
                                    _serverConfigs.isNotEmpty
                                ? _serverConfigs.indexWhere(
                                    (s) => s.id == _selectedServerConfig!.id,
                                  )
                                : null,
                          ),
                        ),
                      ),

                      // Resize Handle
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        onEnter: (_) =>
                            setState(() => _isHoveringResizeHandle = true),
                        onExit: (_) =>
                            setState(() => _isHoveringResizeHandle = false),
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
                                    ? Theme.of(context).colorScheme.primary
                                          .withValues(alpha: 0.5)
                                    : Colors.transparent,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Right Content Area - Floating
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(0, 0, 8, 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
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
                                          pageBuilder:
                                              (
                                                context,
                                                animation,
                                                secondaryAnimation,
                                              ) => S3ConfigPage(
                                                existingConfig:
                                                    _selectedServerConfig!,
                                                onSave: _loadConfigs,
                                              ),
                                          transitionsBuilder:
                                              (
                                                context,
                                                animation,
                                                secondaryAnimation,
                                                child,
                                              ) {
                                                const curve =
                                                    Curves.easeOutQuart;

                                                var scaleAnimation =
                                                    Tween(
                                                      begin: 0.0,
                                                      end: 1.0,
                                                    ).animate(
                                                      CurvedAnimation(
                                                        parent: animation,
                                                        curve: curve,
                                                      ),
                                                    );

                                                var fadeAnimation =
                                                    Tween(
                                                      begin: 0.0,
                                                      end: 1.0,
                                                    ).animate(
                                                      CurvedAnimation(
                                                        parent: animation,
                                                        curve: curve,
                                                      ),
                                                    );

                                                return ScaleTransition(
                                                  scale: scaleAnimation,
                                                  alignment: Alignment.topRight,
                                                  child: FadeTransition(
                                                    opacity: fadeAnimation,
                                                    child: child,
                                                  ),
                                                );
                                              },
                                          transitionDuration: const Duration(
                                            milliseconds: 400,
                                          ),
                                          reverseTransitionDuration:
                                              const Duration(milliseconds: 300),
                                        ),
                                      );
                                    },
                                  )
                                : AppComponents.emptyState(
                                    icon: Icons.cloud_off_outlined,
                                    title: context.loc('no_server_selected'),
                                    subtitle: context.loc(
                                      'select_server_to_start',
                                    ),
                                    onAction: _serverConfigs.isEmpty
                                        ? () {
                                            Navigator.push(
                                              context,
                                              PageRouteBuilder(
                                                pageBuilder:
                                                    (
                                                      context,
                                                      animation,
                                                      secondaryAnimation,
                                                    ) => S3ConfigPage(
                                                      onSave: _loadConfigs,
                                                    ),
                                                transitionsBuilder:
                                                    (
                                                      context,
                                                      animation,
                                                      secondaryAnimation,
                                                      child,
                                                    ) {
                                                      const curve =
                                                          Curves.easeOutQuart;

                                                      var scaleAnimation =
                                                          Tween(
                                                            begin: 0.0,
                                                            end: 1.0,
                                                          ).animate(
                                                            CurvedAnimation(
                                                              parent: animation,
                                                              curve: curve,
                                                            ),
                                                          );

                                                      var fadeAnimation =
                                                          Tween(
                                                            begin: 0.0,
                                                            end: 1.0,
                                                          ).animate(
                                                            CurvedAnimation(
                                                              parent: animation,
                                                              curve: curve,
                                                            ),
                                                          );

                                                      return ScaleTransition(
                                                        scale: scaleAnimation,
                                                        alignment:
                                                            Alignment.topLeft,
                                                        child: FadeTransition(
                                                          opacity:
                                                              fadeAnimation,
                                                          child: child,
                                                        ),
                                                      );
                                                    },
                                                transitionDuration:
                                                    const Duration(
                                                      milliseconds: 400,
                                                    ),
                                                reverseTransitionDuration:
                                                    const Duration(
                                                      milliseconds: 300,
                                                    ),
                                              ),
                                            );
                                          }
                                        : null,
                                    actionText: _serverConfigs.isEmpty
                                        ? context.loc('add_new_server')
                                        : null,
                                  ),
                          ),
                        ),
                      ),
                    ],
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
