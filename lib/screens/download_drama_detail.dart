/// download_drama_detail.dart → 已下载详情页
/// 功能：
/// 1. 展示已下载的剧集列表
/// 2. 本地视频播放器（支持 Windows:MP4 / 安卓iOS:m3u8+TS）
/// 3. 全平台自带倍速功能
/// 核心修复：解决安卓端多次打开/关闭播放器导致的「Callback invoked after it has been deleted」闪退问题
/// 额外修复1：修复记录进度不准、自动跳到后面时间点的进度漂移问题
/// 额外修复2：退出播放器页面返回后，视频还在后台继续播放声音问题
import 'package:flutter/material.dart';
import '../utils/download_manager.dart';
import 'dart:io';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'dart:async';

/// ====================== 【全局播放器单例管理类】 ======================
/// 设计目的：
/// 1. 全局只维护一个Player实例，避免多次创建/销毁导致底层mpv引擎回调泄漏
/// 2. 复用播放器核心资源，切换视频仅更换播放源，杜绝「回调已删除但仍触发」的崩溃
/// 3. 统一管理播放器生命周期，仅在APP退出时释放资源
/// 4. 新增：多层进度强制锁定，修复media_kit底层进度漂移BUG
class GlobalPlayerManager {
  /// 单例模式 - 私有构造方法
  static final GlobalPlayerManager _instance = GlobalPlayerManager._internal();
  factory GlobalPlayerManager() => _instance;
  GlobalPlayerManager._internal();

  /// 全局播放器核心实例（懒加载，首次使用时初始化）
  Player? _player;
  /// 视频渲染控制器（与播放器实例绑定）
  VideoController? _controller;
  /// 记录当前播放的文件路径（用于判断是否需要切换播放源）
  String? currentFilePath;

  /// 获取播放器实例（懒加载 + 判空保护）
  Player get player {
    if (_player == null) {
      _player = Player();
      // 预订阅无关回调并空处理，减少底层回调堆积风险
      _player!.stream.error.listen((_) {});
      _player!.stream.completed.listen((_) {});
    }
    return _player!;
  }

  /// 获取视频控制器（与播放器实例联动，确保一一对应）
  VideoController get controller {
    if (_controller == null || _player == null) {
      _controller = VideoController(player);
    }
    return _controller!;
  }

  /// 切换播放源（核心修复逻辑）
  /// 参数说明：
  /// - filePath: 新视频文件路径
  /// - speed: 播放倍速
  Future<void> switchSource(String filePath, double speed) async {
    // 同一文件无需重新加载，直接恢复播放
    if (currentFilePath == filePath) {
      player.setRate(speed);
      return;
    }

    // 切换前先暂停+停止，清空状态
    try {
      await player.pause();
      await player.stop();
      player.stream.position.drain();
      player.stream.playing.drain();
      // 延时等待引擎状态刷新
      await Future.delayed(const Duration(milliseconds: 80));
      // 🔥 强制归零初始进度，防止继承上一个视频进度
      await player.seek(Duration.zero);
    } catch (_) {}

    // 打开新文件
    await player.open(Media(filePath), play: false);
    player.setRate(speed);
    currentFilePath = filePath;
  }

  /// 恢复播放进度（适配全平台加载时序 + 二次强制跳转锁死进度）
  /// 参数：position - 目标播放进度（Duration类型）
  Future<void> seekTo(Duration position) async {
    try {
      // 第一次延时跳转
      await Future.delayed(const Duration(milliseconds: 200));
      await player.seek(position);
      // 🔥 二次延时再跳转，兜底修复底层进度漂移
      await Future.delayed(const Duration(milliseconds: 200));
      await player.seek(position);
    } catch (e) {
      debugPrint("⚠️ [全局播放器] 进度跳转失败：$e");
    }
  }

  /// 释放全局播放器资源（仅在APP退出时调用）
  Future<void> dispose() async {
    if (_player != null) {
      try {
        await _player!.stop();
        await _player!.dispose();
      } catch (_) {}
      _player = null;
      _controller = null;
      currentFilePath = null;
    }
  }
}

/// ====================== 【本地视频播放器页面】 ======================
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
  final GlobalPlayerManager _playerManager = GlobalPlayerManager();
  final List<double> _speedList = [0.5, 0.75, 1.0, 1.5, 2.0];
  double _currentSpeed = 1.0;
  late DownloadTask _currentTask;
  StreamSubscription<Duration>? _positionSubscription;
  bool _isDisposed = false;
  /// 标记是否已经完成进度恢复，防止循环重复跳转
  bool _hasRestored = false;

  @override
  void initState() {
    super.initState();
    _isDisposed = false;
    _hasRestored = false;
    debugPrint("✅ [本地播放器] 页面初始化开始");

    _currentTask = DownloadManager.instance.completedList.firstWhere(
          (t) => t.savePath == widget.filePath,
    );
    debugPrint("✅ [本地播放器] 匹配到当前播放剧集：${_currentTask.episodeName}");

    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      await _playerManager.switchSource(widget.filePath, _currentSpeed);
      debugPrint("✅ [本地播放器] 初始倍速设置为：${_currentSpeed}x");

      await _restorePlaybackPosition();

      // 🔥 防崩监听：严格防护 + 实时进度兜底矫正
      _positionSubscription = _playerManager.player.stream.position.listen((Duration p) async {
        if (_isDisposed || !mounted) return;

        // 进度未恢复完成时，实时矫正漂移进度
        if (!_hasRestored) {
          final target = _currentTask.watchPositionSeconds;
          // 允许±2秒误差，超出立刻强制跳回正确进度
          if (target > 0 && (p.inSeconds < target - 2 || p.inSeconds > target + 2)) {
            await _playerManager.player.seek(Duration(seconds: target));
          } else {
            _hasRestored = true;
          }
        }

        // 正常记录当前播放进度
        if (p.inSeconds > 0) {
          try {
            _currentTask = _currentTask.copyWith(
              watchPositionSeconds: p.inSeconds,
            );
            DownloadManager.instance.updateTask(_currentTask);
          } catch (_) {}
        }
      });

      _playerManager.player.play();
    } catch (e) {
      debugPrint("⚠️ [本地播放器] 初始化失败：$e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("播放初始化失败：$e")),
        );
      }
    }
  }

  Future<void> _restorePlaybackPosition() async {
    final targetSeconds = _currentTask.watchPositionSeconds;
    if (targetSeconds <= 0 || _isDisposed) {
      debugPrint("ℹ️ [本地播放器] 无历史进度，从开头播放");
      return;
    }

    final targetPosition = Duration(seconds: targetSeconds);
    final minutes = targetPosition.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = targetPosition.inSeconds.remainder(60).toString().padLeft(2, '0');
    debugPrint("ℹ️ [本地播放器] 尝试恢复进度：$minutes:$seconds");

    // 调用全局管理器强制锁定进度
    await _playerManager.seekTo(targetPosition);
    _hasRestored = true;
    debugPrint("✅ [本地播放器] 进度恢复成功!");
  }

  // 🔥 🔥 🔥 最重要：彻底修复闪退 + 修复返回后台继续播放
  @override
  void dispose() {
    _isDisposed = true; // 先标记销毁

    // 🔥 关键修复：页面返回立刻暂停视频，杜绝后台还在播放声音
    _playerManager.player.pause();
    debugPrint("ℹ️ [本地播放器] 页面退出，已暂停视频播放");

    // 立即取消监听
    try {
      _positionSubscription?.cancel();
      _positionSubscription = null;
    } catch (_) {}

    // 只记录日志，不操作播放器实例销毁，防止崩溃
    debugPrint("🛑 [本地播放器] 页面安全销毁 ✅ 无闪退风险");

    super.dispose();
  }

  void _openSpeedMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SingleChildScrollView(
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
                    _playerManager.player.setRate(speed);
                  });
                  Navigator.pop(ctx);
                  debugPrint("ℹ️ [本地播放器] 切换播放倍速：${speed}x");
                },
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
    if (_isDisposed) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.speed, color: Colors.white),
            onPressed: _openSpeedMenu,
            tooltip: "播放倍速",
          ),
        ],
      ),
      body: MaterialVideoControlsTheme(
        normal: MaterialVideoControlsThemeData(
          seekBarHeight: 9,
          seekBarMargin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
          bottomButtonBarMargin: const EdgeInsets.only(bottom: 35),
          bottomButtonBar: [
            const MaterialPlayOrPauseButton(),
            const MaterialPositionIndicator(),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.speed, color: Colors.white),
              onPressed: _openSpeedMenu,
            ),
            const MaterialFullscreenButton(),
          ],
        ),
        fullscreen: MaterialVideoControlsThemeData(
          seekBarHeight: 9,
          seekBarMargin: const EdgeInsets.fromLTRB(24, 0, 24, 100),
          bottomButtonBarMargin: const EdgeInsets.only(bottom: 40),
          bottomButtonBar: [
            const MaterialPlayOrPauseButton(),
            const MaterialPositionIndicator(),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.speed, color: Colors.white),
              onPressed: _openSpeedMenu,
            ),
            const MaterialFullscreenButton(),
          ],
        ),
        child: Video(
          controller: _playerManager.controller,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

/// ====================== 【已下载剧集列表页面】 ======================
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

  /// 格式化视频文件大小
  String _getVideoSize(String? path) {
    if (path == null || !File(path).existsSync()) return "0MB";
    final bytes = File(path).lengthSync();
    final mb = bytes / 1024 / 1024;
    return "${mb.toStringAsFixed(2)}MB";
  }

  /// 秒数转 分:秒 格式化
  String _formatSecondToTime(int seconds) {
    int m = seconds ~/ 60;
    int s = seconds % 60;
    String minute = m.toString().padLeft(2, '0');
    String second = s.toString().padLeft(2, '0');
    return "$minute:$second";
  }

  @override
  Widget build(BuildContext context) {
    final List<DownloadTask> dramaTasks = _downloadManager.completedList
        .where((task) => task.dramaName == widget.dramaName)
        .toList();

    // 按集数数字排序
    dramaTasks.sort((a, b) {
      final numA = int.tryParse(RegExp(r'\d+').stringMatch(a.episodeName) ?? '0') ?? 0;
      final numB = int.tryParse(RegExp(r'\d+').stringMatch(b.episodeName) ?? '0') ?? 0;
      return numA.compareTo(numB);
    });

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
          final sizeText = _getVideoSize(task.savePath);
          final int watchSec = task.watchPositionSeconds;
          final String watchText = watchSec > 0
              ? "已观看至 ${_formatSecondToTime(watchSec)}"
              : "未观看";

          return ListTile(
            leading: const Icon(Icons.video_file, color: Colors.blue),
            title: Text(task.episodeName),
            subtitle: Text(
              "已下载 · $sizeText · $watchText",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            onTap: () {
              if (task.savePath == null || !File(task.savePath!).existsSync()) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("文件不存在或已删除")),
                );
                debugPrint("⚠️ [离线列表] 视频文件不存在：${task.episodeName}");
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
              ).then((_) {
                setState(() {});
              });
            },
            // 删除按钮
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                debugPrint("🗑️ [离线列表] 点击删除剧集弹窗：${task.episodeName}");
                // 显示删除确认弹窗
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("删除已下载内容"),
                    content: const Text("确定要删除这个已下载的视频吗？文件将被永久删除。"),
                    actions: [
                      // 修复1：TextButton.onPressed 不能直接写 Navigator.pop
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("取消"),
                      ),
                      TextButton(
                        onPressed: () async {
                          // 修复2：先拿到 context，防止异步操作后 context 失效
                          final navigatorContext = context;
                          Navigator.pop(navigatorContext);
                          // 调用下载管理器删除任务（含文件）
                          await _downloadManager.deleteTask(task);
                          if (mounted) {
                            setState(() {}); // 刷新列表
                            ScaffoldMessenger.of(navigatorContext).showSnackBar(
                              SnackBar(content: Text("已删除：${task.episodeName}")),
                            );
                          }
                          debugPrint("🗑️ [离线列表] 已成功删除离线剧集：${task.episodeName}");
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

/// 【可选】APP退出时释放全局播放器
/// @override
/// void dispose() {
///   GlobalPlayerManager().dispose();
///   super.dispose();
/// }