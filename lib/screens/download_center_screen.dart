/// download_center_screen.dart → 下载界面（你看到的页面）
import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/download_manager.dart';
import 'download_drama_detail.dart';

class DownloadCenterScreen extends StatefulWidget {
  const DownloadCenterScreen({super.key});

  @override
  State<DownloadCenterScreen> createState() => _DownloadCenterScreenState();
}

class _DownloadCenterScreenState extends State<DownloadCenterScreen>
    with SingleTickerProviderStateMixin {
  final DownloadManager _manager = DownloadManager.instance;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // 注册监听，指向单独的回调函数
    _manager.addListener(_onDownloadUpdate);
  }

  @override
  void dispose() {
    // 页面销毁时，移除对DownloadManager的监听，防止内存泄漏
    _manager.removeListener(_onDownloadUpdate);
    _tabController.dispose();
    super.dispose();
  }

  // 单独的监听回调，带mounted检查
  void _onDownloadUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("下载中心"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "已下载"),
            Tab(text: "下载中"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCompletedTab(),
          _buildDownloadingTab(),
        ],
      ),
    );
  }

  // 已下载列表
  Widget _buildCompletedTab() {
    final Map<String, List<DownloadTask>> dramaGroups = {};
    for (var task in _manager.completedList) {
      dramaGroups.putIfAbsent(task.dramaName, () => []).add(task);
    }

    if (dramaGroups.isEmpty) {
      return const Center(child: Text("暂无已下载内容"));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: dramaGroups.keys.length,
      itemBuilder: (context, index) {
        final dramaName = dramaGroups.keys.elementAt(index);
        final dramaTasks = dramaGroups[dramaName]!;
        double totalSizeMB = 0;
        for (var task in dramaTasks) {
          if (task.savePath != null) {
            final file = File(task.savePath!);
            totalSizeMB += file.lengthSync() / 1024 / 1024;
          }
        }

        return ListTile(
          leading: const Icon(Icons.movie, color: Colors.blue),
          title: Text(dramaName),
          subtitle: Text("共${dramaTasks.length}个 · ${totalSizeMB.toStringAsFixed(2)} MB · 短剧"),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DownloadDramaDetailScreen(dramaName: dramaName),
              ),
            );
          },
        );
      },
    );
  }

  // 下载中列表（带取消按钮 + 确认弹窗 + 带名称取消提示）
  Widget _buildDownloadingTab() {
    if (_manager.downloadingList.isEmpty) {
      return const Center(child: Text("暂无正在下载的任务"));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _manager.downloadingList.length,
      itemBuilder: (context, index) {
        final task = _manager.downloadingList[index];
        return ListTile(
          leading: IconButton(
            icon: Icon(
              task.isPaused ? Icons.play_arrow : Icons.pause,
              color: Colors.blue,
            ),
            onPressed: () {
              _manager.togglePause(task);
            },
          ),
          title: Text(task.title),
          subtitle: LinearProgressIndicator(value: task.progress),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("${(task.progress * 100).toInt()}%"),
              const SizedBox(width: 8),
              // 取消下载按钮 + 确认弹窗
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red, size: 20),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text("取消下载"),
                      content: const Text("确定要取消这个下载任务吗？"),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("取消"),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _manager.cancelDownload(task);
                            // 动态显示：已取消下载 + 剧名集数
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("✅ 已取消下载：${task.title}"),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                          child: const Text("确定", style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}