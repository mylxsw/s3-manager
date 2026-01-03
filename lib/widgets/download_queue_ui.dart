import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ploys3/core/localization.dart';
import 'package:ploys3/download_manager.dart';
import 'package:ploys3/core/design_system.dart';
import 'package:path/path.dart' as path;

class DownloadQueueUI extends StatefulWidget {
  final DownloadManager downloadManager;

  const DownloadQueueUI({super.key, required this.downloadManager});

  @override
  State<DownloadQueueUI> createState() => _DownloadQueueUIState();
}

class _DownloadQueueUIState extends State<DownloadQueueUI> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.downloadManager,
      builder: (context, child) {
        final queue = widget.downloadManager.queue;
        if (queue.isEmpty) return const SizedBox.shrink();
        final mediaQuery = MediaQuery.of(context);
        final isMobilePlatform =
            const [TargetPlatform.iOS, TargetPlatform.android].contains(defaultTargetPlatform);
        final horizontalMargin = isMobilePlatform ? 12.0 : 20.0;
        final bottomMargin = isMobilePlatform ? 12.0 : 20.0;
        final collapsedHeight = isMobilePlatform ? 56.0 : 60.0;
        final expandedHeight =
            isMobilePlatform ? mediaQuery.size.height * 0.6 : 500.0;
        final stackedOffset = collapsedHeight + (isMobilePlatform ? 12.0 : 20.0);

        final activeCount = queue
            .where(
              (item) =>
                  item.status == DownloadStatus.downloading ||
                  item.status == DownloadStatus.pending,
            )
            .length;

        // Auto-show for first time or simple logic?
        // We'll mimic upload queue logic.

        return Positioned(
          left: isMobilePlatform ? horizontalMargin : null,
          right: horizontalMargin,
          bottom: bottomMargin + mediaQuery.padding.bottom + stackedOffset,
          // To avoid overlap, we might need a better layout strategy or just offset.
          // Since users usually do one or the other, or we can just stack.
          // Or let's put it on top of upload queue?
          // If we hardcode bottom right, they will overlap.
          // Let's assume for now 80 (upload is 20 bottom).
          // Actually, if we use a Column or Stack in parent, we could manage it.
          // But here we are positioned absolutely.
          // Let's stick it to the left or top? Or just bottom right but offset?
          // Bottom 20 is UploadQueue. Let's make this Bottom 90.
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: isMobilePlatform ? double.infinity : (_isExpanded ? 400 : 200),
            height: _isExpanded ? expandedHeight : collapsedHeight,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: _isExpanded
                  ? _buildExpandedView(queue)
                  : _buildCollapsedView(activeCount),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCollapsedView(int activeCount) {
    return InkWell(
      onTap: () => setState(() => _isExpanded = true),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            if (activeCount > 0)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).primaryColor,
                ),
              )
            else
              Icon(Icons.check_circle, color: Theme.of(context).primaryColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                activeCount > 0
                    ? context.loc('downloading_count', [activeCount.toString()])
                    : context.loc('download_complete'),
                style: Theme.of(context).textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.keyboard_arrow_up,
              color: Theme.of(context).disabledColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedView(List<DownloadItem> queue) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.loc('download_queue'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Row(
                children: [
                  if (queue.every(
                    (i) =>
                        i.status == DownloadStatus.success ||
                        i.status == DownloadStatus.failed,
                  ))
                    IconButton(
                      icon: const Icon(Icons.clear_all),
                      tooltip: context.loc('clear_completed'),
                      onPressed: () => widget.downloadManager.clearAll(),
                    ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down),
                    onPressed: () => setState(() => _isExpanded = false),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // List
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(0),
            itemCount: queue.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = queue[index];
              return ListTile(
                title: Text(
                  item.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: AppFontSizes.md),
                ),
                subtitle: item.status == DownloadStatus.failed
                    ? Text(
                        item.errorMessage ?? context.loc('error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: AppFontSizes.sm,
                        ),
                      )
                    : item.status == DownloadStatus.downloading
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          LinearProgressIndicator(value: item.progress),
                        ],
                      )
                    : null,
                trailing: _buildItemAction(item),
                dense: true,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildItemAction(DownloadItem item) {
    switch (item.status) {
      case DownloadStatus.pending:
        return Icon(
          Icons.hourglass_empty,
          size: 16,
          color: Theme.of(context).disabledColor,
        );
      case DownloadStatus.downloading:
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: item.progress > 0 ? item.progress : null,
          ),
        );
      case DownloadStatus.success:
        return IconButton(
          icon: const Icon(Icons.folder_open),
          tooltip: context.loc('open'), // Need 'open'? Using 'Open' mostly.
          onPressed: () {
            if (item.savePath != null) {
              // Open file location
              final filePath = item.savePath!;
              if (Platform.isMacOS || Platform.isLinux) {
                Process.run('open', [path.dirname(filePath)]);
              } else if (Platform.isWindows) {
                Process.run('explorer', [path.dirname(filePath)]);
              }
            }
          },
        );
      case DownloadStatus.failed:
        return IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: context.loc('retry'),
          onPressed: () => widget.downloadManager.retry(item),
        );
    }
  }
}
