/// download_drama_detail.dart → 已下载详情页
/// 功能：
/// 1. 展示已下载的剧集列表
/// 2. 本地视频播放器（支持 Windows:MP4 / 安卓iOS:m3u8+TS）
/// 3. 全平台自带倍速功能
import 'package:flutter/material.dart';
import '../utils/download_manager.dart';
import 'dart:io';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// ====================== 【本地视频播放器】 ======================
/// 适配架构：
/// Windows  → 播放本地 MP4
/// 安卓/iOS → 播放本地 m3u8 + TS 离线缓存
/// 全平台支持：播放、暂停、进度条、手动倍速（0.5x - 2.0x）
class LocalVideoPlayerScreen extends StatefulWidget {
  /// 本地文件路径（MP4 或 m3u8）
  final String filePath;

  /// 视频标题（剧集名）
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
  /// 播放器核心实例
  late final Player player;

  /// 视频控制器
  late final VideoController controller;

  /// 支持的倍速列表
  final List<double> _speedList = [0.5, 0.75, 1.0, 1.5, 2.0];

  /// 当前使用的倍速（默认正常 1.0x）
  double _currentSpeed = 1.0;

  @override
  void initState() {
    super.initState();

    // 初始化播放器
    player = Player();

    // 绑定控制器
    controller = VideoController(player);

    // 打开本地视频文件（自动识别 MP4 / m3u8）
    player.open(Media(widget.filePath));

    // 设置初始播放速度
    player.setRate(_currentSpeed);
  }

  @override
  void dispose() {
    // 页面关闭时释放播放器资源
    player.dispose();
    super.dispose();
  }

  /// 打开倍速选择弹窗
  /// 弹出底部倍速选择菜单（可滑动，横竖屏不溢出）
  void _openSpeedMenu() {
    showModalBottomSheet(
      context: context,
      // 允许弹窗自适应高度
      isScrollControlled: true,
      builder: (ctx) => SingleChildScrollView(
        // 可滑动，解决横屏溢出问题
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _speedList.map((speed) {
              return ListTile(
                title: Text("${speed}x"),
                onTap: () {
                  setState(() {
                    _currentSpeed = speed;
                    player.setRate(speed);
                  });
                  Navigator.pop(ctx);
                },
                // 当前选中的倍速显示对勾
                trailing: _currentSpeed == speed
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // 竖屏顶部导航栏
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        // 竖屏右上角保留倍速按钮（备用入口）
        actions: [
          IconButton(
            icon: const Icon(Icons.speed, color: Colors.white),
            onPressed: _openSpeedMenu,
            tooltip: "播放倍速",
          ),
        ],
      ),
      // 包裹视频控件，自定义横竖屏控制栏
      body: MaterialVideoControlsTheme(
        // 竖屏普通模式控制栏配置（去掉const）
        normal: MaterialVideoControlsThemeData(
          bottomButtonBar: [
            const MaterialPlayOrPauseButton(), // 播放/暂停按钮
            const MaterialPositionIndicator(),  // 播放进度文字
            const Spacer(),                    // 占位撑开布局
            // 底部控制栏加入倍速按钮
            IconButton(
              icon: const Icon(Icons.speed, color: Colors.white),
              onPressed: _openSpeedMenu,
              tooltip: "播放倍速",
            ),
            const MaterialFullscreenButton(),  // 全屏按钮
          ],
        ),
        // 横屏全屏模式控制栏配置（去掉const）
        fullscreen: MaterialVideoControlsThemeData(
          bottomButtonBar: [
            const MaterialPlayOrPauseButton(),
            const MaterialPositionIndicator(),
            const Spacer(),
            // 全屏横屏也显示倍速按钮
            IconButton(
              icon: const Icon(Icons.speed, color: Colors.white),
              onPressed: _openSpeedMenu,
              tooltip: "播放倍速",
            ),
            const MaterialFullscreenButton(),
          ],
        ),
        // 视频播放组件
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

/// ====================== 【已下载剧集列表页面】 ======================
/// 功能：
/// 1. 显示某一部剧下所有已下载的集数
/// 2. 按数字自动排序（第1集、第2集、第3集...）
/// 3. 点击播放 / 长按删除
class DownloadDramaDetailScreen extends StatefulWidget {
  /// 当前打开的剧集名称
  final String dramaName;

  const DownloadDramaDetailScreen({
    super.key,
    required this.dramaName,
  });

  @override
  State<DownloadDramaDetailScreen> createState() => _DownloadDramaDetailScreenState();
}

class _DownloadDramaDetailScreenState extends State<DownloadDramaDetailScreen> {
  /// 下载管理实例
  final DownloadManager _downloadManager = DownloadManager.instance;

  @override
  Widget build(BuildContext context) {
    /// 筛选出当前这部剧的所有已下载任务
    final List<DownloadTask> dramaTasks = _downloadManager.completedList
        .where((task) => task.dramaName == widget.dramaName)
        .toList();

    /// ====================== ✅ 自动按集数数字排序 ======================
    /// 从“第10集”中提取数字 10，然后按数字从小到大排序
    dramaTasks.sort((a, b) {
      final numA = int.tryParse(RegExp(r'\d+').stringMatch(a.episodeName) ?? '0') ?? 0;
      final numB = int.tryParse(RegExp(r'\d+').stringMatch(b.episodeName) ?? '0') ?? 0;
      return numA.compareTo(numB);
    });
    /// ==================================================================

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
            // 点击 → 播放本地视频
            onTap: () {
              if (task.savePath == null || !File(task.savePath!).existsSync()) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("文件不存在或已删除")),
                );
                return;
              }

              // 跳转到本地播放器
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
            // 右侧删除按钮
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
                          setState(() {}); // 刷新列表
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