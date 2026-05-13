/// download_episode_sheet.dart → 选集下载弹窗
// 引入Flutter基础组件库
import 'package:flutter/material.dart';
// 引入下载中心页面，用于跳转
import '../screens/download_center_screen.dart';
// 引入全局下载管理器工具类
import '../utils/download_manager.dart';

/// 剧集下载底部弹窗组件
/// 改造后新增：传入剧集名称，用于下载任务分组
class DownloadEpisodeSheet extends StatefulWidget {
  // 短剧/剧集 总名称（例如：菩提临世、太平年）
  final String dramaName;
  // 所有单集名称列表（例如：第1集、第2集...）
  final List<String> episodes;
  // 每一集对应的真实视频下载链接
  final List<String> urls;
  // 兼容旧版的选中回调（目前闲置保留）
  final Function(List<String> selected) onDownload;

  /// 构造函数：必须传入剧名、集数列表、链接列表、回调
  const DownloadEpisodeSheet({
    super.key,
    required this.dramaName,
    required this.episodes,
    required this.urls,
    required this.onDownload,
  });

  @override
  State<DownloadEpisodeSheet> createState() => _DownloadEpisodeSheetState();
}

class _DownloadEpisodeSheetState extends State<DownloadEpisodeSheet> {
  // 存储用户勾选选中的单集名称
  final Set<String> _selected = {};

  /// 判断是否已经全选：选中数量 = 总集数数量
  bool get _isAllSelected => _selected.length == widget.episodes.length;

  @override
  Widget build(BuildContext context) {
    // 获取当前主题配置
    final theme = Theme.of(context);
    // 判断是否为深色模式
    final isDark = theme.brightness == Brightness.dark;

    // 底部弹窗外层容器
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // 背景跟随主题卡片色
        color: theme.cardColor,
        // 顶部圆角弹窗样式
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      // 垂直布局
      child: Column(
        // 自适应内容高度，不撑满全屏
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部标题栏 + 关闭按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "下载缓存",
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              // 关闭弹窗按钮
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  Icons.close,
                  color: theme.iconTheme.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 剧集网格列表区域
          Expanded(
            // 使用 LayoutBuilder 获取屏幕方向，实现横竖屏不同布局
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 获取屏幕方向（竖屏 / 横屏）
                final orientation = MediaQuery.orientationOf(context);

                // 定义变量：根据方向自动切换列数和宽高比
                late int crossAxisCount;
                late double childAspectRatio;

                // 竖屏（手机正常拿）
                if (orientation == Orientation.portrait) {
                  crossAxisCount = 4;    // 一行4个
                  childAspectRatio = 2.8; // 加宽按钮，让文字能完整显示
                }
                // 横屏（手机横着拿）
                else {
                  crossAxisCount = 6;    // 一行6个
                  childAspectRatio = 3.5; // 更宽，文字完全不挤
                }

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const AlwaysScrollableScrollPhysics(), // 超出可滚动
                  // 网格布局配置（动态根据横竖屏变化）
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 12, // 左右间距
                    mainAxisSpacing: 12,  // 上下间距
                    childAspectRatio: childAspectRatio, // 按钮宽高比例（动态）
                  ),
                  itemCount: widget.episodes.length,
                  itemBuilder: (context, index) {
                    // 当前单集名称
                    final ep = widget.episodes[index];
                    // 判断当前集是否被选中
                    final isSelected = _selected.contains(ep);

                    return GestureDetector(
                      // 点击整行切换选中状态
                      onTap: () {
                        setState(() {
                          isSelected ? _selected.remove(ep) : _selected.add(ep);
                        });
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          // 选中/未选中 背景色区分
                          color: isSelected
                              ? (isDark ? Colors.grey[700] : Colors.grey[300])
                              : (isDark ? Colors.grey[800] : Colors.grey[200]),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            // 复选框：用于标记是否选中该集
                            Checkbox(
                              value: isSelected,
                              onChanged: (v) {
                                setState(() {
                                  v == true ? _selected.add(ep) : _selected.remove(ep);
                                });
                              },
                              fillColor: WidgetStateProperty.all(Colors.transparent),
                              checkColor: theme.textTheme.bodyLarge?.color,
                            ),

                            // 关键修复：用 Expanded 包裹文字，让文字自适应剩余宽度，不拉伸、不溢出
                            Expanded(
                              child: Text(
                                ep, // 显示集数名称（第1集、第2集...）
                                style: TextStyle(
                                  color: theme.textTheme.bodyLarge?.color,
                                ),
                                // 已移除省略号，文字完整显示
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // 全选复选框行
          Row(
            children: [
              Checkbox(
                value: _isAllSelected,
                onChanged: (v) {
                  setState(() {
                    // 全选：加入所有集数；取消全选：清空选中
                    v == true
                        ? _selected.addAll(widget.episodes)
                        : _selected.clear();
                  });
                },
                fillColor: WidgetStateProperty.all(Colors.transparent),
                checkColor: theme.textTheme.bodyLarge?.color,
              ),
              Text(
                "全选",
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 底部两个按钮：立即下载、查看全部下载
          Row(
            children: [
              // 立即下载按钮
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  // 没选中任何集数则按钮置灰不可点击
                  onPressed: _selected.isEmpty
                      ? null
                      : () {
                    // 构建下载任务列表
                    final List<DownloadTask> tasks = [];

                    // 遍历所有集数，把选中的加入下载队列
                    for (int i = 0; i < widget.episodes.length; i++) {
                      final episodeName = widget.episodes[i];
                      if (_selected.contains(episodeName)) {
                        // 按新模型构造任务：传入剧名、集名、链接
                        tasks.add(DownloadTask(
                          dramaName: widget.dramaName,
                          episodeName: episodeName,
                          url: widget.urls[i],
                        ));
                      }
                    }

                    // 交给全局下载管理器开始后台下载
                    DownloadManager.instance.addTasks(tasks);
                    // 关闭下载弹窗
                    Navigator.pop(context);

                    // 弹出提示：已加入队列
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("✅ 已加入下载队列（${tasks.length}个）"),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Text(
                    "立即下载",
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // 查看全部下载 → 跳转到下载中心页面
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.secondary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    // 先关闭当前弹窗，再跳转页面
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DownloadCenterScreen(),
                      ),
                    );
                  },
                  child: const Text(
                    "查看全部下载",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}