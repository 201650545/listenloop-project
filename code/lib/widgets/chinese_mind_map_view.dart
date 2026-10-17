import 'package:flutter/material.dart';
import '../data/primary_chinese_curriculum.dart';
import '../theme/listenloop_theme.dart';

/// 课文点击回调（支持直接进入精听/朗读）
typedef OnChineseLessonTap = void Function(PrimaryChineseLesson lesson);

/// 中文课程全景思维导图组件 (Chinese Mind Map Viewer)
/// ---------------------------------------------------------------------------
/// 采用无限画布手势平移与缩放 (InteractiveViewer)，将一个年级整册的所有单元与课文
/// 收敛在单张全景图谱中呈现。用户可双指放大缩小迅速定位，点击任意课文节点秒进精听页。
/// 支持全局搜索关键词联动：高亮命中课文节点并自动平移聚焦。
class ChineseMindMapView extends StatefulWidget {
  const ChineseMindMapView({
    super.key,
    required this.grade,
    required this.term,
    required this.onLessonTap,
    this.importedLessonTitles = const {},
    this.searchQuery = '',
  });

  final int grade;
  final String term;
  final OnChineseLessonTap onLessonTap;
  final Set<String> importedLessonTitles;
  final String searchQuery;

  @override
  State<ChineseMindMapView> createState() => _ChineseMindMapViewState();
}

class _ChineseMindMapViewState extends State<ChineseMindMapView>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformController =
      TransformationController();
  final GlobalKey _contentKey = GlobalKey();

  late final AnimationController _animController;
  Animation<Matrix4>? _matrixAnimation;

  GlobalKey? _firstMatchedKey;
  bool _hasCalculatedFirstMatch = false;
  bool _isLocked = false;
  double _currentScale = 0.5;
  double _favoritedScale = 0.5;
  Matrix4? _favoritedMatrix;
  final GlobalKey _firstUnitKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    )..addListener(() {
        if (_matrixAnimation != null) {
          _transformController.value = _matrixAnimation!.value;
        }
      });

    _transformController.addListener(_onTransformChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.searchQuery.trim().isNotEmpty) {
        _panToMatchedNode();
      } else {
        _resetToDefaultView(animated: false);
      }
    });
  }

  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    if ((scale - _currentScale).abs() > 0.008) {
      setState(() {
        _currentScale = scale;
      });
    }
  }

  @override
  void didUpdateWidget(ChineseMindMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != oldWidget.searchQuery ||
        widget.grade != oldWidget.grade ||
        widget.term != oldWidget.term) {
      if (widget.searchQuery.trim().isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _panToMatchedNode());
      }
    }
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _animController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  /// 收藏当前视图为还原基准
  void _favoriteCurrentView() {
    setState(() {
      _favoritedScale = _currentScale;
      _favoritedMatrix = Matrix4.copy(_transformController.value);
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('★ 已将 ${(_favoritedScale * 100).toInt()}% 收藏为基准视图'),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 还原到默认基准视图（默认 50% 且第一单元居中置顶）
  void _restoreFavoritedView() {
    _resetToDefaultView(animated: true);
  }

  /// 默认视图：50% 缩放，第一单元水平居中且置于视口顶部
  void _resetToDefaultView({bool animated = true}) {
    if (!mounted) return;
    final unitContext = _firstUnitKey.currentContext;
    final contentContext = _contentKey.currentContext;
    final viewerContext = context;

    const double targetScale = 0.50; // 用户指定：默认 50% 视图

    if (unitContext != null &&
        contentContext != null) {
      final unitBox = unitContext.findRenderObject() as RenderBox?;
      final contentBox = contentContext.findRenderObject() as RenderBox?;
      final viewerBox = viewerContext.findRenderObject() as RenderBox?;

      if (unitBox != null &&
          contentBox != null &&
          viewerBox != null &&
          unitBox.hasSize &&
          contentBox.hasSize &&
          viewerBox.hasSize) {
        final unitOffset =
            unitBox.localToGlobal(Offset.zero, ancestor: contentBox);
        final unitWidth = unitBox.size.width;
        final viewerWidth = viewerBox.size.width;

        // 计算第一单元在未缩放画卷中的水平中心与顶部 Y
        // 将第一单元及其根节点构成的顶部视界整体居中（使第一单元卡片居中，两侧留白均匀对称）
        final topBlockWidth = unitOffset.dx + unitWidth;
        final topBlockCenterX = topBlockWidth > 0 ? (topBlockWidth / 2) : (unitOffset.dx + unitWidth / 2);
        final unitTopY = unitOffset.dy;

        // 在 50% 缩放下：
        // 1. 第一单元居中：视口水平中心对齐第一单元视觉块中心
        final tx = viewerWidth / 2 - topBlockCenterX * targetScale;
        // 2. 第一单元在最上面：顶部留出 24dp 边距
        final ty = 24.0 - unitTopY * targetScale;

        final targetMatrix = Matrix4.identity()
          ..setTranslationRaw(tx, ty, 0.0)
          ..scale(targetScale, targetScale, 1.0);

        if (animated) {
          _animateToMatrix(targetMatrix);
        } else {
          _transformController.value = targetMatrix;
          _favoritedMatrix ??= Matrix4.copy(targetMatrix);
          setState(() {
            _currentScale = targetScale;
          });
        }
        return;
      }
    }

    // 布局未完成时的保底
    final fallbackMatrix = Matrix4.identity()
      ..setTranslationRaw(0.0, 24.0, 0.0)
      ..scale(targetScale, targetScale, 1.0);
    if (animated) {
      _animateToMatrix(fallbackMatrix);
    } else {
      _transformController.value = fallbackMatrix;
      _favoritedMatrix ??= Matrix4.copy(fallbackMatrix);
      setState(() {
        _currentScale = targetScale;
      });
    }
  }

  /// 适应全景：缩到最小，从头到尾都能看到全部内容
  void _zoomFitOverview() {
    final contentBox =
        _contentKey.currentContext?.findRenderObject() as RenderBox?;
    final viewerBox = context.findRenderObject() as RenderBox?;
    if (contentBox != null &&
        viewerBox != null &&
        contentBox.hasSize &&
        viewerBox.hasSize) {
      final cw = contentBox.size.width;
      final ch = contentBox.size.height;
      final vw = viewerBox.size.width;
      final vh = viewerBox.size.height;
      if (cw > 0 && ch > 0) {
        // 留出适度安全边距，缩到最小，完整看到全部内容
        final scaleX = (vw - 32) / cw;
        final scaleY = (vh - 32) / ch;
        final fitScale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.12, 1.0);

        final tx = (vw - cw * fitScale) / 2;
        final ty = (vh - ch * fitScale) / 2;

        final targetMatrix = Matrix4.identity()
          ..setTranslationRaw(tx, ty, 0.0)
          ..scale(fitScale, fitScale, 1.0);
        _animateToMatrix(targetMatrix);
        return;
      }
    }
    // 兜底全景最小缩放
    _animateToMatrix(Matrix4.diagonal3Values(0.20, 0.20, 1.0));
  }


  /// 切换视图锁定（只锁缩放，不锁移动）
  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isLocked ? '已锁定缩放（防止误触放大缩小，仍可自由拖动）' : '已解锁缩放'),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _animateToMatrix(Matrix4 target) {
    _animController.stop();
    _matrixAnimation = Matrix4Tween(
      begin: _transformController.value,
      end: target,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    _animController.forward(from: 0.0);
  }

  void _panToMatchedNode() {
    if (!mounted || widget.searchQuery.trim().isEmpty) return;
    final targetContext = _firstMatchedKey?.currentContext;
    final contentContext = _contentKey.currentContext;
    final viewerContext = context;
    if (targetContext == null || contentContext == null) return;

    final targetBox = targetContext.findRenderObject() as RenderBox?;
    final contentBox = contentContext.findRenderObject() as RenderBox?;
    final viewerBox = viewerContext.findRenderObject() as RenderBox?;
    if (targetBox == null || contentBox == null || viewerBox == null) return;
    if (!targetBox.hasSize || !contentBox.hasSize || !viewerBox.hasSize) return;

    // 计算目标节点在未缩放画卷坐标系下的中心点
    final targetOffsetInContent =
        targetBox.localToGlobal(Offset.zero, ancestor: contentBox);
    final targetCenterX = targetOffsetInContent.dx + targetBox.size.width / 2;
    final targetCenterY = targetOffsetInContent.dy + targetBox.size.height / 2;

    final viewerSize = viewerBox.size;
    const double scale = 1.0;
    final double tx = viewerSize.width / 2 - targetCenterX * scale;
    final double ty = viewerSize.height / 2 - targetCenterY * scale;

    final targetMatrix = Matrix4.identity()
      ..setTranslationRaw(tx, ty, 0.0)
      ..scale(scale, scale, 1.0);

    _animateToMatrix(targetMatrix);
  }

  bool _isLessonMatched(PrimaryChineseLesson lesson) {
    final q = widget.searchQuery.trim().toLowerCase();
    if (q.isEmpty) return false;
    final t = lesson.title.toLowerCase();
    final dt = lesson.displayTitle.toLowerCase();
    final nt = lesson.numberedTitle().toLowerCase();
    if (t.contains(q) || dt.contains(q) || nt.contains(q)) return true;
    for (final sub in lesson.subLessons) {
      if (_isLessonMatched(sub)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final lessons =
        PrimaryChineseCurriculum.getLessons(widget.grade, widget.term);

    // 重置首个匹配节点的 key 捕获器
    _hasCalculatedFirstMatch = false;

    // 按单元将课文分组
    final Map<String, List<PrimaryChineseLesson>> unitMap = {};
    for (final l in lessons) {
      unitMap.putIfAbsent(l.unit, () => []).add(l);
    }

    final gradeLabel = PrimaryChineseLesson(
      grade: widget.grade,
      term: widget.term,
      unit: '',
      title: '',
    ).gradeLabel;

    return Stack(
      children: [
        // 1. 无限缩放与拖拽画布（支持 0.12~3.5 超广缩放，手势自由缩放 50%~300%）
        InteractiveViewer(
          transformationController: _transformController,
          minScale: 0.12,
          maxScale: 3.5,
          boundaryMargin: const EdgeInsets.all(800),
          constrained: false,
          panEnabled: true, // 始终允许拖拽平移，锁定状态下也自由移动
          scaleEnabled: !_isLocked, // 仅在未锁定时允许双指缩放；锁定后只锁定放大缩小
          child: Padding(
            key: _contentKey,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
            child: _buildMindMapTree(
              context,
              ll: ll,
              gradeLabel: gradeLabel,
              unitMap: unitMap,
              totalLessons: lessons.length,
            ),
          ),
        ),

        // 2. 右上角：当锁定缩放时的状态指示条
        if (_isLocked)
          Positioned(
            top: 14,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: ll.surface.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ll.divider, width: 0.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_rounded, size: 13, color: ll.accent),
                  const SizedBox(width: 4),
                  Text(
                    '缩放已锁定（可自由拖动）',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ll.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 3. 右下角快捷缩放与锁定悬浮控制药丸
        Builder(
          builder: (context) {
            final isCurrentFavorited =
                (_currentScale - _favoritedScale).abs() < 0.03;
            return Positioned(
              right: 16,
              bottom: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: ll.surface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: ll.divider, width: 0.8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 3.1 锁定开关（只锁定放大缩小，不锁定移动）
                    IconButton(
                      tooltip: _isLocked
                          ? '缩放已锁定（点击解锁手势缩放）'
                          : '锁定缩放（防误触改变大小，锁定后仍可自由拖动）',
                      icon: Icon(
                        _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                        size: 18,
                      ),
                      onPressed: _toggleLock,
                      visualDensity: VisualDensity.compact,
                      color: _isLocked ? ll.accent : ll.textPrimary,
                    ),
                    Container(
                      width: 1,
                      height: 16,
                      color: ll.divider,
                    ),
                    // 3.2 动态显示当前比例 + 旁边星号收藏
                    Tooltip(
                      message: isCurrentFavorited
                          ? '当前为已收藏基准视图（${(_favoritedScale * 100).toInt()}%）'
                          : '点击星号：将当前 ${(_currentScale * 100).toInt()}% 视图收藏为还原基准',
                      child: InkWell(
                        onTap: _favoriteCurrentView,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${(_currentScale * 100).toInt()}%',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: ll.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Icon(
                                isCurrentFavorited
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                size: 16,
                                color: isCurrentFavorited
                                    ? Colors.amber.shade700
                                    : ll.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 16,
                      color: ll.divider,
                    ),
                    // 3.3 适应全景：缩到最小，从头到尾都能看到
                    IconButton(
                      tooltip: '适应全景（缩至最小全览）',
                      icon: const Icon(Icons.fullscreen_outlined, size: 18),
                      onPressed: _zoomFitOverview,
                      visualDensity: VisualDensity.compact,
                      color: ll.textPrimary,
                    ),
                    Container(
                      width: 1,
                      height: 16,
                      color: ll.divider,
                    ),
                    // 3.4 还原键：还原到用户收藏的基准视图
                    IconButton(
                      tooltip:
                          '还原到收藏基准视图（${(_favoritedScale * 100).toInt()}%）',
                      icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      onPressed: _restoreFavoritedView,
                      visualDensity: VisualDensity.compact,
                      color: ll.textPrimary,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// 构建横向辐射状思维导图树
  Widget _buildMindMapTree(
    BuildContext context, {
    required LLPalette ll,
    required String gradeLabel,
    required Map<String, List<PrimaryChineseLesson>> unitMap,
    required int totalLessons,
  }) {
    final units = unitMap.entries.toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 核心根节点：年级与分册
        _buildRootNode(ll, gradeLabel, totalLessons, units.length),

        const SizedBox(width: 48),

        // 分支：所有单元列
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < units.length; i++) ...[
              if (i > 0) const SizedBox(height: 20),
              _buildUnitBranch(
                ll,
                key: i == 0 ? _firstUnitKey : null,
                unitName: units[i].key,
                lessons: units[i].value,
                unitIndex: i + 1,
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// 根节点卡片
  Widget _buildRootNode(
    LLPalette ll,
    String gradeLabel,
    int totalLessons,
    int totalUnits,
  ) {
    return Container(
      width: 160,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: ll.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ll.textPrimary.withValues(alpha: 0.8),
          width: 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ll.textPrimary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.account_tree_outlined,
              size: 22,
              color: ll.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$gradeLabel ${widget.term}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: ll.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '统编版语文',
            style: TextStyle(
              fontSize: 11,
              color: ll.textSecondary,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: ll.textPrimary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ll.divider, width: 0.6),
            ),
            child: Text(
              '$totalUnits 单元 · $totalLessons 篇',
              style: TextStyle(
                fontSize: 10,
                color: ll.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 单元分支卡片及其延伸出来的具体课文（课文列表纵向自上而下排布）
  Widget _buildUnitBranch(
    LLPalette ll, {
    Key? key,
    required String unitName,
    required List<PrimaryChineseLesson> lessons,
    required int unitIndex,
  }) {
    return KeyedSubtree(
      key: key,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 单元节点卡片
        Container(
          width: 140,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: ll.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ll.divider, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: ll.textPrimary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      unitName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ll.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${lessons.length} 篇课文',
                style: TextStyle(
                  fontSize: 10,
                  color: ll.textTertiary,
                ),
              ),
            ],
          ),
        ),

        // 连接主干横线：连入课文纵向主干母线
        Container(
          width: 20,
          height: 1.5,
          color: ll.divider.withValues(alpha: 0.9),
        ),

        // 叶子节点：课文列表（纵向排开，形成标准树状分支）
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int j = 0; j < lessons.length; j++)
              _buildLessonItemWithBranch(
                ll,
                lessons[j],
                isFirst: j == 0,
                isLast: j == lessons.length - 1,
                isSingle: lessons.length == 1,
                lessonIndex: j + 1,
              ),
          ],
        ),
      ],
    ),
  );
}

  /// 带分支连线的单篇课文包装项（三级分支，若有 subLessons 则向右延伸出四级分支）
  Widget _buildLessonItemWithBranch(
    LLPalette ll,
    PrimaryChineseLesson lesson, {
    required bool isFirst,
    required bool isLast,
    required bool isSingle,
    required int lessonIndex,
  }) {
    final isMatched = _isLessonMatched(lesson);
    final hasSub = lesson.subLessons.isNotEmpty;

    return IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CustomPaint(
            size: const Size(20, double.infinity),
            painter: _LessonBranchPainter(
              isFirst: isFirst,
              isLast: isLast,
              isSingle: isSingle,
              color: ll.divider.withValues(alpha: 0.9),
              isMatched: isMatched,
              matchedColor: Colors.amber.shade700,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildLessonNode(ll, lesson, lessonIndex: lessonIndex),
            ),
          ),
          if (hasSub) ...[
            // 连入四级分支的水平连接横线
            Container(
              width: 16,
              height: 1.5,
              color: ll.divider.withValues(alpha: 0.9),
            ),
            // 四级分支列表（垂直排开，如识字加油站、字词句运用、日积月累、我爱阅读）
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int k = 0; k < lesson.subLessons.length; k++)
                  _buildSubLessonItemWithBranch(
                    ll,
                    lesson.subLessons[k],
                    isFirst: k == 0,
                    isLast: k == lesson.subLessons.length - 1,
                    isSingle: lesson.subLessons.length == 1,
                    subIndex: k + 1,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 四级子分支项（如语文园地下的各板块）
  Widget _buildSubLessonItemWithBranch(
    LLPalette ll,
    PrimaryChineseLesson subLesson, {
    required bool isFirst,
    required bool isLast,
    required bool isSingle,
    required int subIndex,
  }) {
    final isMatched = _isLessonMatched(subLesson);

    return IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CustomPaint(
            size: const Size(18, double.infinity),
            painter: _LessonBranchPainter(
              isFirst: isFirst,
              isLast: isLast,
              isSingle: isSingle,
              color: ll.divider.withValues(alpha: 0.9),
              isMatched: isMatched,
              matchedColor: Colors.amber.shade700,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: _buildSubLessonNode(ll, subLesson, subIndex: subIndex),
          ),
        ],
      ),
    );
  }

  /// 四级子节点卡片（紧凑精致，带小序号圆标）
  Widget _buildSubLessonNode(
    LLPalette ll,
    PrimaryChineseLesson subLesson, {
    required int subIndex,
  }) {
    final isMatched = _isLessonMatched(subLesson);

    // 标题支持换行：首行作为栏目名（如 会认字 / 会写字 / 词语），其余为字词内容
    final rawTitle = subLesson.displayTitle;
    final titleLines = rawTitle.split('\n');
    final hasLabel = titleLines.length > 1;
    final label = hasLabel ? titleLines.first : null;
    final body = hasLabel ? titleLines.sublist(1).join('\n') : rawTitle;

    Key? nodeKey;
    if (isMatched && !_hasCalculatedFirstMatch) {
      _firstMatchedKey = GlobalKey();
      nodeKey = _firstMatchedKey;
      _hasCalculatedFirstMatch = true;
    }

    final border = isMatched
        ? Border.all(color: Colors.amber.shade700, width: 2.0)
        : Border.all(color: ll.divider.withValues(alpha: 0.8), width: 0.8);

    final bgColor = isMatched
        ? Colors.amber.withValues(alpha: 0.16)
        : ll.surface;

    final shadows = isMatched
        ? [
            BoxShadow(
              color: Colors.amber.withValues(alpha: 0.35),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ]
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ];

    return InkWell(
      key: nodeKey,
      onTap: subLesson.isPlayable ? () => widget.onLessonTap(subLesson) : null,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        constraints: const BoxConstraints(minHeight: 30),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: border,
          boxShadow: shadows,
        ),
        alignment: Alignment.centerLeft,
        // 单行布局：编号 + 栏目名 + 字词内容，宽度自适应，显示完整
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: isMatched
                    ? Colors.amber.shade800
                    : ll.textPrimary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$subIndex',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: isMatched ? Colors.white : ll.textSecondary,
                  height: 1.0,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                hasLabel ? '$label：$body' : body,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isMatched ? FontWeight.w700 : FontWeight.w500,
                  color: isMatched ? Colors.black87 : ll.textPrimary,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 单个课文节点（点击即开，命中搜索高亮，课题带序号）
  Widget _buildLessonNode(
    LLPalette ll,
    PrimaryChineseLesson lesson, {
    required int lessonIndex,
  }) {
    final numberedTitle = lesson.numberedTitle(fallbackIndex: lessonIndex);
    final isMatched = _isLessonMatched(lesson);

    Key? nodeKey;
    if (isMatched && !_hasCalculatedFirstMatch) {
      _firstMatchedKey = GlobalKey();
      nodeKey = _firstMatchedKey;
      _hasCalculatedFirstMatch = true;
    }

    // 搜索命中样式：明亮琥珀色高亮边框与柔和微光背景
    final border = isMatched
        ? Border.all(color: Colors.amber.shade700, width: 2.0)
        : Border.all(
            color: ll.divider,
            width: 0.8,
          );

    final bgColor = isMatched
        ? Colors.amber.withValues(alpha: 0.16)
        : ll.surface;

    final shadows = isMatched
        ? [
            BoxShadow(
              color: Colors.amber.withValues(alpha: 0.35),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ]
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ];

    return InkWell(
      key: nodeKey,
      onTap: () => widget.onLessonTap(lesson),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 184,
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: border,
          boxShadow: shadows,
        ),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            if (isMatched) ...[
              Container(
                margin: const EdgeInsets.only(right: 5),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: ll.accent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '匹配',
                  style: TextStyle(fontSize: 10, color: ll.onPrimary, fontWeight: FontWeight.bold),
                ),
              ),
            ],
            Expanded(
              child: Text(
                numberedTitle,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isMatched ? FontWeight.w700 : FontWeight.w500,
                  color: isMatched ? Colors.black87 : ll.textPrimary,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (lesson.subLessons.isNotEmpty)
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: ll.textTertiary,
              ),
          ],
        ),
      ),
    );
  }
}

/// 树状分支折线绘制器（自适应垂直主干母线与水平短枝）
class _LessonBranchPainter extends CustomPainter {
  const _LessonBranchPainter({
    required this.isFirst,
    required this.isLast,
    required this.isSingle,
    required this.color,
    required this.isMatched,
    required this.matchedColor,
  });

  final bool isFirst;
  final bool isLast;
  final bool isSingle;
  final Color color;
  final bool isMatched;
  final Color matchedColor;

  @override
  void paint(Canvas canvas, Size size) {
    final basePaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final yCenter = size.height / 2;

    if (isSingle) {
      // 只有一篇课文：单横线贯穿
      canvas.drawLine(
        Offset(0, yCenter),
        Offset(size.width, yCenter),
        isMatched ? (basePaint..color = matchedColor..strokeWidth = 2.0) : basePaint,
      );
      return;
    }

    // 1. 垂直主干母线（位于 x = 0，与单元发出的横线相交）
    final topY = isFirst ? yCenter : 0.0;
    final bottomY = isLast ? yCenter : size.height;
    canvas.drawLine(Offset(0, topY), Offset(0, bottomY), basePaint);

    // 2. 水平分支线（从 x = 0 连到 x = size.width，接入课文卡片）
    final branchPaint = isMatched
        ? (Paint()
            ..color = matchedColor
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke)
        : basePaint;

    canvas.drawLine(
      Offset(0, yCenter),
      Offset(size.width, yCenter),
      branchPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _LessonBranchPainter oldDelegate) {
    return isFirst != oldDelegate.isFirst ||
        isLast != oldDelegate.isLast ||
        isSingle != oldDelegate.isSingle ||
        color != oldDelegate.color ||
        isMatched != oldDelegate.isMatched ||
        matchedColor != oldDelegate.matchedColor;
  }
}
