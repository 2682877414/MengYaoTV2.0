/// download_drama_detail.dart → 已下载详情页
import 'package:flutter/material.dart';
import '../utils/download_manager.dart';
import 'dart:io';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 【本地视频专用播放器】—— 直接播放下载好的MP4，不走在线逻辑
class LocalVideoPlayerScreen extends StatefulWidget {
  final String filePath;
  final String title;

  const LocalVideoPlayerScreen({
    super.key,
    required this.filePath,
    required this.title,
  });

  @override
  State<LocalVideoPlayerScreen> createState() => _LocalVideoPlayerScreenState();
}

class _LocalVideoPlayerScreenState extends State<LocalVideoPlayerScreen> {
  late final Player player;
  late final VideoController controller;

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    player.open(Media(widget.filePath));
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: Video(
          controller: controller,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

/// 【短剧下载详情页】
class DownloadDramaDetailScreen extends StatefulWidget {
  final String dramaName;

  const DownloadDramaDetailScreen({
    super.key,
    required this.dramaName,
  });

  @override
  State<DownloadDramaDetailScreen> createState() => _DownloadDramaDetailScreenState();
}

class _DownloadDramaDetailScreenState extends State<DownloadDramaDetailScreen> {
  final DownloadManager _downloadManager = DownloadManager.instance;

  @override
  Widget build(BuildContext context) {
    final List<DownloadTask> dramaTasks = _downloadManager.completedList
        .where((task) => task.dramaName == widget.dramaName)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.dramaName),
      ),
      body: dramaTasks.isEmpty
          ? const Center(child: Text("暂无已下载剧集"))
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: dramaTasks.length,
        itemBuilder: (context, index) {
          final task = dramaTasks[index];
          return ListTile(
            leading: const Icon(Icons.video_file, color: Colors.blue),
            title: Text(task.episodeName),
            subtitle: const Text("已下载 → 点击播放"),
            onTap: () {
              if (task.savePath == null || !File(task.savePath!).existsSync()) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("文件不存在或已删除")),
                );
                return;
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => LocalVideoPlayerScreen(
                    filePath: task.savePath!,
                    title: task.episodeName,
                  ),
                ),
              );
            },
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("删除已下载内容"),
                    content: const Text("确定要删除这个已下载的视频吗？文件将被永久删除。"),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("取消"),
                      ),
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _downloadManager.deleteTask(task);
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("已删除：${task.episodeName}")),
                          );
                        },
                        child: const Text("删除", style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}