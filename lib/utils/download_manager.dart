/// ⭐⭐⭐ download_manager.dart → 正常下载版（无残留）⭐⭐⭐
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

/// 下载任务实体类
class DownloadTask {
  final String dramaName;
  final String episodeName;
  final String url;
  double progress;
  bool isCompleted;
  String? savePath;
  bool isPaused;
  Process? process;

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

  String get title => "$dramaName $episodeName";
}

class DownloadManager extends ChangeNotifier {
  static final DownloadManager instance = DownloadManager._internal();
  DownloadManager._internal();

  final List<DownloadTask> _downloadingList = [];
  final List<DownloadTask> _completedList = [];
  BuildContext? _globalContext;
  bool _isRunning = false;

  List<DownloadTask> get downloadingList => _downloadingList;
  List<DownloadTask> get completedList => _completedList;

  void setContext(BuildContext context) => _globalContext = context;

  Future<String> _getFfmpegPath() async {
    if (!Platform.isWindows) return "ffmpeg";

    final appDir = await getApplicationSupportDirectory();
    final ffmpegPath = "${appDir.path}/ffmpeg.exe";
    final file = File(ffmpegPath);

    if (!await file.exists()) {
      print("[FFmpeg] 释放资源文件...");
      final data = await rootBundle.load("assets/ffmpeg/ffmpeg.exe");
      await file.writeAsBytes(data.buffer.asUint8List());
      print("[FFmpeg] 释放完成：$ffmpegPath");
    }
    return ffmpegPath;
  }

  void addTasks(List<DownloadTask> tasks) {
    for (var task in tasks) {
      bool exists = _downloadingList.any((t) => t.title == task.title);
      bool done = _completedList.any((t) => t.title == task.title);
      if (!exists && !done) _downloadingList.add(task);
    }
    notifyListeners();
    startDownload();
  }

  Future<void> startDownload() async {
    if (_isRunning) return;
    _isRunning = true;
    final tasks = List.from(_downloadingList);
    for (var t in tasks) {
      if (t.isCompleted || t.isPaused) continue;
      await _downloadWithFFmpeg(t);
    }
    _isRunning = false;
    if (_globalContext != null) notifyListeners();
  }

  Future<void> _downloadWithFFmpeg(DownloadTask task) async {
    Process? process;

    if (!Platform.isWindows) {
      print("❌ 仅 Windows 支持下载");
      _showSnack("❌ 仅 Windows 支持下载", Colors.red);
      _downloadingList.remove(task);
      notifyListeners();
      return;
    }

    try {
      task.progress = 0.02;
      notifyListeners();

      final dir = await getApplicationDocumentsDirectory();
      final savePath = "${dir.path}/${task.title}.mp4";
      final ffmpegPath = await _getFfmpegPath();

      print("\n========================================");
      print("📥 开始下载：${task.title}");
      print("🔗 URL：${task.url}");
      print("========================================\n");

      // 最简命令，去掉多余 headers，避免卡住
      process = await Process.start(
        ffmpegPath,
        [
          "-hide_banner",
          "-loglevel", "info",
          "-user_agent", "Mozilla/5.0",
          "-i", task.url,
          "-c", "copy",
          "-y",
          savePath,
        ],
      );

      task.process = process;
      task.savePath = savePath;

      process.stderr.transform(utf8.decoder).listen((log) {
        if (log.trim().isNotEmpty) {
          print("[FFmpeg] $log");
          task.progress = (task.progress + 0.01).clamp(0.02, 0.98);
          if (_globalContext != null) notifyListeners();
        }
      });

      await process.exitCode;
      process = null;

      if (!_downloadingList.contains(task)) {
        print("❌ 任务已取消");
        return;
      }

      final file = File(savePath);
      if (await file.exists() && await file.length() > 1024 * 1024) {
        task.progress = 1.0;
        task.isCompleted = true;
        _downloadingList.remove(task);
        _completedList.add(task);
        print("✅ 下载完成！");
        _showSnack("✅ ${task.title} 下载完成！", Colors.green);
      } else {
        _safeDelete(savePath);
        _showSnack("❌ 下载失败", Colors.red);
        _downloadingList.remove(task);
      }
    } catch (e) {
      print("❌ 下载异常：$e");
      _showSnack("❌ 下载失败", Colors.red);
      _downloadingList.remove(task);
    } finally {
      process?.kill();
      if (_globalContext != null) notifyListeners();
    }
  }

  Future<void> _safeDelete(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  void _showSnack(String msg, Color color) {
    if (_globalContext == null) return;
    ScaffoldMessenger.of(_globalContext!).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  void togglePause(DownloadTask task) {
    task.isPaused = !task.isPaused;
    notifyListeners();
    if (!task.isPaused) startDownload();
  }

  void cancelDownload(DownloadTask task) async {
    task.process?.kill();
    _downloadingList.remove(task);

    if (task.savePath != null) {
      await Future.delayed(const Duration(milliseconds: 200));
      _safeDelete(task.savePath!);
      print("✅ 已清理取消下载文件");
    }

    task.isCompleted = false;
    task.progress = 0;
    notifyListeners();
  }

  Future<void> deleteTask(DownloadTask task) async {
    _completedList.remove(task);
    _downloadingList.remove(task);
    task.process?.kill();

    if (task.savePath != null) {
      _safeDelete(task.savePath!);
    }
    notifyListeners();
  }
}