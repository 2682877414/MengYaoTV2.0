/// download_drama_detail.dart → 剧集详情页下载按钮入口
/// ⭐⭐⭐ download_manager.dart → 三端完美兼容版 ⭐⭐⭐
/// ⭐⭐⭐ download_manager.dart → 正常下载版（无残留）⭐⭐⭐

import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // 只加这一行

/// 下载任务实体类
/// 包含剧集名称、集数名称、下载地址、进度、状态等信息
class DownloadTask {
  /// 剧集名称
  final String dramaName;
  /// 集数名称
  final String episodeName;
  /// 下载地址
  final String url;
  /// 下载进度 0.0 - 1.0
  double progress;
  /// 是否下载完成
  bool isCompleted;
  /// 文件保存路径
  String? savePath;
  /// 是否暂停
  bool isPaused;
  /// Windows进程对象
  Process? process;

  /// 构造函数
  DownloadTask({
    required this.dramaName,
    required this.episodeName,
    required this.url,
    this.progress = 0.0,
    this.isCompleted = false,
    this.savePath,
    this.isPaused = false,
    this.process,
  });

  /// 获取拼接后的标题（剧集名-集数名）
  String get title => "$dramaName-$episodeName";

  /// 转为Map，用于本地持久化存储
  Map<String, dynamic> toMap() {
    return {
      'dramaName': dramaName,
      'episodeName': episodeName,
      'url': url,
      'savePath': savePath,
      'isCompleted': isCompleted,
    };
  }

  /// 从Map还原为DownloadTask对象
  static DownloadTask fromMap(Map<String, dynamic> map) {
    return DownloadTask(
      dramaName: map['dramaName'],
      episodeName: map['episodeName'],
      url: map['url'],
      savePath: map['savePath'],
      isCompleted: map['isCompleted'] ?? false,
    );
  }
}

/// 全局下载管理单例
/// 负责任务队列、下载执行、状态管理、本地保存
class DownloadManager extends ChangeNotifier {
  /// 单例对象
  static final DownloadManager instance = DownloadManager._internal();
  /// 私有构造函数
  DownloadManager._internal();

  /// 正在下载中的任务列表
  final List<DownloadTask> _downloadingList = [];
  /// 已完成下载的任务列表
  final List<DownloadTask> _completedList = [];
  /// 全局上下文（用于显示SnackBar提示）
  BuildContext? _globalContext;
  /// 下载队列是否正在执行
  bool _isRunning = false;

  /// 获取正在下载列表（外部只读）
  List<DownloadTask> get downloadingList => _downloadingList;
  /// 获取已完成列表（外部只读）
  List<DownloadTask> get completedList => _completedList;

  /// 设置全局上下文
  void setContext(BuildContext context) => _globalContext = context;

  // ========================== 重启加载已下载 ==========================
  /// 初始化：APP启动时加载本地已保存的下载记录
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('downloads') ?? [];
    _completedList.clear();
    for (final s in list) {
      final task = DownloadTask.fromMap(jsonDecode(s));
      if (task.savePath != null && File(task.savePath!).existsSync()) {
        _completedList.add(task);
      }
    }
    notifyListeners();
  }

  /// 保存下载列表到SharedPreferences
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('downloads', _completedList.map((e) => jsonEncode(e.toMap())).toList());
  }

  /// 获取Windows平台ffmpeg.exe路径，不存在则释放内置资源
  Future<String> _getFfmpegPath() async {
    if (!Platform.isWindows) return "ffmpeg";
    final appDir = await getApplicationSupportDirectory();
    final ffmpegPath = "${appDir.path}/ffmpeg.exe";
    final file = File(ffmpegPath);
    if (!await file.exists()) {
      print("[日志] 释放ffmpeg");
      final data = await rootBundle.load("assets/ffmpeg/ffmpeg.exe");
      await file.writeAsBytes(data.buffer.asUint8List());
    }
    return ffmpegPath;
  }

  /// 批量添加下载任务（自动去重）
  void addTasks(List<DownloadTask> tasks) {
    for (var task in tasks) {
      bool exists = _downloadingList.any((t) => t.url == task.url);
      bool done = _completedList.any((t) => t.url == task.url);
      if (!exists && !done) {
        _downloadingList.add(task);
        print("[日志] 添加任务: ${task.title}");
      }
    }
    notifyListeners();
    startDownload();
  }

  /// 启动下载队列（串行执行）
  Future<void> startDownload() async {
    if (_isRunning) return;
    _isRunning = true;
    final tasks = List.from(_downloadingList);
    for (var t in tasks) {
      if (t.isCompleted || t.isPaused) continue;
      await _downloadVideo(t);
    }
    _isRunning = false;
    notifyListeners();
  }

  /// 单个视频核心下载方法
  /// 区分Windows（ffmpeg转mp4）与移动端（m3u8分片下载）
  Future<void> _downloadVideo(DownloadTask task) async {
    Process? process;
    try {
      print("\n[日志] 开始下载: ${task.title}");
      task.progress = 0.02;
      notifyListeners();

      /// 获取应用文档目录，创建剧集专属保存文件夹
      final rootDir = await getApplicationDocumentsDirectory();
      final videoDir = Directory("${rootDir.path}/videos/${task.title}");
      if (!await videoDir.exists()) await videoDir.create(recursive: true);

      /// Windows 平台下载逻辑（直接合成 MP4）
      if (Platform.isWindows) {
        final savePath = "${videoDir.path}/${task.title}.mp4";
        final ffmpegPath = await _getFfmpegPath();
        process = await Process.start(ffmpegPath, [
          "-hide_banner", "-loglevel", "info", "-i", task.url, "-c", "copy", "-y", savePath
        ]);
        task.process = process;
        task.savePath = savePath;

        /// 监听FFmpeg输出日志，更新下载进度
        process.stderr.transform(utf8.decoder).listen((log) {
          if (log.trim().isNotEmpty) {
            task.progress = (task.progress + 0.01).clamp(0.02, 0.98);
            print("[日志] 下载进度：${task.title} → ${(task.progress * 100).toStringAsFixed(1)}%");
            notifyListeners();
          }
        });

        await process.exitCode;
        process = null;

        /// 标记任务完成，移动到已完成列表
        task.progress = 1.0;
        task.isCompleted = true;
        _downloadingList.remove(task);
        _completedList.add(task);
        await _save();
        print("[日志] ✅ 已保存到：$savePath");

        /// 弹窗提示：下载完成 + 保存路径
        _showSnack("✅ 下载完成 已保存：$savePath", Colors.green);
      }

      /// 移动端（Android / iOS）下载逻辑
      else {
        final client = http.Client();
        final realM3u8 = await _getRealM3u8(task.url, client);
        print("[日志] 真实地址: $realM3u8");

        /// 下载并保存 m3u8 索引文件
        final m3u8File = File("${videoDir.path}/index.m3u8");
        final resp = await client.get(Uri.parse(realM3u8));
        await m3u8File.writeAsString(resp.body);

        /// 解析出所有 .ts 分片
        final tsList = resp.body.split("\n").where((e) => e.trim().endsWith(".ts")).toList();
        print("[日志] TS总数: ${tsList.length}");
        int current = 0;

        /// 逐一下载 TS 分片
        for (final line in tsList) {
          if (task.isPaused) break;
          try {
            final tsUrl = Uri.parse(line.trim()).isAbsolute
                ? line.trim()
                : Uri.parse(realM3u8).resolve(line.trim()).toString();
            final tsPath = "${videoDir.path}/${line.trim()}";
            if (await File(tsPath).exists()) {
              print("[日志] TS已存在，跳过：$tsPath");
              current++;
              continue;
            }
            print("[日志] 正在下载TS：${line.trim()}");
            final res = await client.get(Uri.parse(tsUrl));
            await File(tsPath).writeAsBytes(res.bodyBytes);
            current++;
            task.progress = 0.1 + (current / tsList.length) * 0.8;
            print("[日志] 下载进度：${task.title} → ${(task.progress * 100).toStringAsFixed(1)}%");
            notifyListeners();
          } catch (e) {}
        }

        /// 标记任务完成
        task.savePath = m3u8File.path;
        task.progress = 1.0;
        task.isCompleted = true;
        _downloadingList.remove(task);
        _completedList.add(task);
        await _save();
        print("[日志] ✅ 已保存到：${m3u8File.path}");
        print("[日志] 下载完成！");

        /// 弹窗提示：视频已保存 + 路径
        _showSnack("✅ 视频已保存：${m3u8File.path}", Colors.green);
        client.close();
      }
    } catch (e) {
      print("[错误] 下载异常: $e");
      _showSnack("❌ 下载失败", Colors.red);
      _downloadingList.remove(task);
    } finally {
      /// 确保进程被杀死，避免残留
      process?.kill();
      notifyListeners();
    }
  }

  /// 解析真实 m3u8 地址（自动处理嵌套 m3u8）
  Future<String> _getRealM3u8(String url, http.Client client) async {
    try {
      final resp = await client.get(Uri.parse(url));
      for (final line in resp.body.split("\n")) {
        final l = line.trim();
        if (l.startsWith("#")) continue;
        if (l.endsWith(".m3u8")) {
          final real = Uri.parse(url).resolve(l).toString();
          print("[日志] 发现嵌套m3u8: $real");
          return real;
        }
      }
    } catch (e) {}
    return url;
  }

  // ========================== ✅ 绝对防闪退 删除 ==========================
  /// 安全删除任务：只移除列表，不删除文件，避免播放器崩溃
  Future<void> deleteTaskSafe(DownloadTask task) async {
    print("[日志] 安全移除任务: ${task.title} (不删除文件，避免播放器崩溃)");

    _completedList.remove(task);
    _downloadingList.remove(task);
    await _save();

    await Future.delayed(const Duration(seconds: 5));
    task.savePath = null;
    notifyListeners();
    _showSnack("✅ 任务已移除", Colors.green);
  }

  /// 显示底部提示条
  void _showSnack(String msg, Color color) {
    if (_globalContext == null) return;
    ScaffoldMessenger.of(_globalContext!).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  /// 切换暂停/继续下载
  void togglePause(DownloadTask task) {
    task.isPaused = !task.isPaused;
    print("[日志] ${task.isPaused ? '⏸️ 暂停' : '▶️ 继续'}：${task.title}");
    notifyListeners();
  }

  /// 取消当前下载任务
  void cancelDownload(DownloadTask task) async {
    print("[日志] 🚫 取消下载：${task.title}");
    task.process?.kill();
    _downloadingList.remove(task);
    notifyListeners();
  }

  /// 外部删除任务（统一走安全删除）
  Future<void> deleteTask(DownloadTask task) async => deleteTaskSafe(task);
}