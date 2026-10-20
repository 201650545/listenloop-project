import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/primary_chinese_curriculum.dart';
import '../lesson/lesson_package_reader.dart';
import '../models/lesson.dart';
import '../models/sentence.dart';
import '../storage/lesson_repository.dart';
import '../theme/listenloop_theme.dart';
import '../widgets/ll_page.dart';
import '../widgets/ll_primitives.dart';
import 'cloud_catalog_sheet.dart' show CloudCourse;
import 'listening_screen.dart';

/// Three-Tier Online Course Library Screen (小学/初中语文 1~9 年级 在线课程库)
///
/// Tier 1: Grade (一年级 ~ 九年级)
/// Tier 2: Volume (上册 / 下册)
/// Tier 3: Specific lesson list (具体课文), integrated with live cloud downloads
/// from the distribution server, and full global search across all 1~9 grades.
class PrimaryChineseCatalogScreen extends StatefulWidget {
  const PrimaryChineseCatalogScreen({
    super.key,
    required this.repository,
    this.onLessonImported,
    this.initialQuery,
    this.initialGrade,
    this.initialTerm,
    this.onOpenLesson,
  });

  final LessonRepository repository;
  final ValueChanged<Lesson>? onLessonImported;
  final String? initialQuery;
  final int? initialGrade;
  final String? initialTerm;
  final void Function(LessonWithProgress item, List<Sentence> sentences)? onOpenLesson;

  static const String defaultServerUrl = 'http://123.57.84.97:3100';

  @override
  State<PrimaryChineseCatalogScreen> createState() =>
      _PrimaryChineseCatalogScreenState();
}

class _PrimaryChineseCatalogScreenState
    extends State<PrimaryChineseCatalogScreen> {
  int _selectedGrade = 2; // Default to Grade 2 where live courses exist
  String _selectedTerm = '上册'; // Default to 上册
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool _loading = true;
  String? _errorMessage;
  final Map<String, CloudCourse> _cloudCoursesById = {};
  final Map<String, CloudCourse> _cloudCoursesByTitle = {};
  Set<String> _importedTitles = {};
  Set<String> _importedIds = {};
  final Map<String, double> _downloadProgress = {};
  final Set<String> _downloadingIds = {};
  String _serverBaseUrl = PrimaryChineseCatalogScreen.defaultServerUrl;

  // 批量下载状态管理
  bool _isBatchDownloading = false;
  int _batchTotal = 0;
  int _batchCurrentIndex = 0;
  String _batchCurrentTitle = '';
  double _batchSubProgress = 0.0;
  bool _cancelBatchRequested = false;

  // 单元折叠栏状态管理与最后打开持久化
  final Set<String> _expandedUnits = {};

  String _unitPrefKey(int grade, String term) =>
      'chinese_catalog_last_unit_${grade}_$term';

  Future<void> _restoreExpandedUnits() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final key = _unitPrefKey(_selectedGrade, _selectedTerm);
      final savedUnit = sp.getString(key);
      final lessons = PrimaryChineseCurriculum.getLessons(
        _selectedGrade,
        _selectedTerm,
      );
      final allUnits = <String>{};
      for (final l in lessons) {
        allUnits.add(l.unit);
      }
      if (mounted) {
        setState(() {
          _expandedUnits.clear();
          if (savedUnit != null && allUnits.contains(savedUnit)) {
            _expandedUnits.add(savedUnit);
          } else if (allUnits.isNotEmpty) {
            // 首次进入默认展开第 1 单元
            final firstUnit = allUnits.first;
            _expandedUnits.add(firstUnit);
          }
        });
      }
    } catch (_) {}
  }

  void _toggleUnit(String unit) {
    setState(() {
      if (_expandedUnits.contains(unit)) {
        _expandedUnits.remove(unit);
      } else {
        _expandedUnits.add(unit);
        final key = _unitPrefKey(_selectedGrade, _selectedTerm);
        SharedPreferences.getInstance().then((sp) {
          sp.setString(key, unit);
        }).catchError((_) {});
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialGrade != null) {
      _selectedGrade = widget.initialGrade!;
    }
    if (widget.initialTerm != null) {
      _selectedTerm = widget.initialTerm!;
    }
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _searchQuery = widget.initialQuery!;
      _searchController.text = widget.initialQuery!;
    }
    _restoreExpandedUnits();
    _loadCatalog();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      // 1. Cross-reference local lessons
      final localLessons = await widget.repository.listLessons();
      _importedTitles = localLessons.map((item) => item.lesson.title).toSet();
      _importedIds = localLessons.map((item) => item.lesson.id).toSet();

      // 2. Fetch catalog.json from cloud server
      final uri = Uri.parse(
        '$_serverBaseUrl/catalog.json?t=${DateTime.now().millisecondsSinceEpoch}',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        throw HttpException('服务器返回错误码: ${resp.statusCode}');
      }

      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final rawList = data['courses'] as List<dynamic>? ?? [];
      final list = rawList
          .map((item) => CloudCourse.fromJson(item as Map<String, dynamic>))
          .toList();

      _cloudCoursesById.clear();
      _cloudCoursesByTitle.clear();
      for (final course in list) {
        if (course.lessonId.isNotEmpty) {
          _cloudCoursesById[course.lessonId] = course;
        }
        _cloudCoursesByTitle[course.title] = course;
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '连接云端课程库失败: $e';
        _loading = false;
      });
    }
  }

  CloudCourse? _findCloudCourse(PrimaryChineseLesson lesson) {
    if (lesson.lessonId != null &&
        _cloudCoursesById.containsKey(lesson.lessonId)) {
      return _cloudCoursesById[lesson.lessonId];
    }
    const genericNames = {'识字加油站', '字词句运用', '日积月累', '我爱阅读', '书写提示', '和大人一起读'};
    final pureTitle = lesson.displayTitle;
    if (genericNames.contains(pureTitle)) {
      for (final entry in _cloudCoursesByTitle.entries) {
        if (entry.key == lesson.title || entry.key == lesson.fullTitle) {
          return entry.value;
        }
      }
      return null;
    }
    // 去掉开头的 "课文N " 或 "识字N " 前缀进行模糊对齐
    final pureLessonTitle = lesson.title.replaceAll(RegExp(r'^(课文\d+|识字\d+|示范课例)\s*'), '');
    for (final entry in _cloudCoursesByTitle.entries) {
      if (entry.key.contains(pureLessonTitle) || (pureLessonTitle.isNotEmpty && entry.key.contains(lesson.title))) {
        return entry.value;
      }
    }
    return null;
  }

  bool _isLessonImported(PrimaryChineseLesson lesson, CloudCourse? cloud) {
    if (lesson.lessonId != null && _importedIds.contains(lesson.lessonId)) {
      return true;
    }
    if (cloud != null && _importedIds.contains(cloud.lessonId)) {
      return true;
    }
    if (cloud != null && _importedTitles.contains(cloud.title)) {
      return true;
    }
    const genericNames = {'识字加油站', '字词句运用', '日积月累', '我爱阅读', '书写提示', '和大人一起读'};
    final pureTitle = lesson.displayTitle;
    if (genericNames.contains(pureTitle)) {
      return _importedTitles.contains(lesson.title) || _importedTitles.contains(lesson.fullTitle);
    }
    for (final imported in _importedTitles) {
      final cleanImported = imported
          .replaceAll(RegExp(r'^(课文\d+|识字\d+|示范课例|园地[一二三四五六七八]\s*)\s*'), '')
          .replaceAll(RegExp(r'[（\(]双模[板版].*?[）\)]'), '')
          .trim();
      if (imported == lesson.title ||
          imported == pureTitle ||
          cleanImported == pureTitle ||
          (cleanImported.isNotEmpty && pureTitle.contains(cleanImported)) ||
          (pureTitle.isNotEmpty && cleanImported.contains(pureTitle))) {
        return true;
      }
    }
    return false;
  }

  Future<void> _openLessonInPlayer(Lesson lesson) async {
    final data = await widget.repository.getLessonWithSentences(lesson.id);
    if (!mounted || data == null) return;
    final sentences = data.sentences;
    if (widget.onOpenLesson != null) {
      final item = LessonWithProgress(lesson: lesson, progress: null);
      widget.onOpenLesson!(item, sentences);
      Navigator.of(context).pop();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ListeningScreen(
          title: lesson.title,
          language: lesson.language,
          sentences: sentences,
          audioAsset: lesson.audioPath,
          audioIsFile: true,
          lessonId: lesson.id,
          repository: widget.repository,
          coverPath: lesson.coverPath,
          videoSource: lesson.video,
        ),
      ),
    );
  }

  Future<void> _openLessonByCatalog(
    PrimaryChineseLesson lesson,
    CloudCourse? cloud,
  ) async {
    final all = await widget.repository.listLessons();
    Lesson? match;
    for (final l in all) {
      if (lesson.lessonId != null && l.lesson.id == lesson.lessonId) {
        match = l.lesson;
        break;
      }
      if (cloud != null && l.lesson.id == cloud.lessonId) {
        match = l.lesson;
        break;
      }
    }
    if (match == null) {
      const genericNames = {'识字加油站', '字词句运用', '日积月累', '我爱阅读', '书写提示', '和大人一起读'};
      final pureTarget = lesson.displayTitle;
      for (final l in all) {
        if (genericNames.contains(pureTarget)) {
          if (l.lesson.title == lesson.title || l.lesson.title == lesson.fullTitle) {
            match = l.lesson;
            break;
          }
          continue;
        }
        final pureLocal = l.lesson.title
            .replaceAll(RegExp(r'^(课文\d+|识字\d+|示范课例|园地[一二三四五六七八]\s*)\s*'), '')
            .replaceAll(RegExp(r'[（\(]双模[板版].*?[）\)]'), '')
            .trim();
        if (l.lesson.title == lesson.title ||
            l.lesson.title == pureTarget ||
            pureLocal == pureTarget ||
            (pureLocal.isNotEmpty && pureTarget.contains(pureLocal)) ||
            (pureTarget.isNotEmpty && pureLocal.contains(pureTarget))) {
          match = l.lesson;
          break;
        }
      }
    }
    if (match != null) {
      await _openLessonInPlayer(match);
    }
  }

  Future<void> _downloadAndImport(
    PrimaryChineseLesson lesson,
    CloudCourse course, {
    bool autoOpen = false,
    bool showSnack = true,
    ValueChanged<double>? onProgress,
  }) async {
    if (_downloadingIds.contains(course.lessonId)) return;

    setState(() {
      _downloadingIds.add(course.lessonId);
      _downloadProgress[course.lessonId] = 0.05;
    });
    onProgress?.call(0.05);

    File? tempFile;
    try {
      final downloadUrl = '$_serverBaseUrl${course.downloadPath}';
      final req = http.Request('GET', Uri.parse(downloadUrl));
      final streamed = await req.send().timeout(const Duration(seconds: 25));

      if (streamed.statusCode != 200) {
        throw HttpException('下载失败，状态码: ${streamed.statusCode}');
      }

      final tempDir = await getTemporaryDirectory();
      tempFile = File(p.join(tempDir.path, 'download_${course.fileName}'));
      final sink = tempFile.openWrite();

      final totalBytes = streamed.contentLength ?? course.fileSize;
      var receivedBytes = 0;

      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0 && mounted) {
          final pRatio = (receivedBytes / totalBytes).clamp(0.0, 0.95);
          setState(() {
            _downloadProgress[course.lessonId] = pRatio;
          });
          onProgress?.call(pRatio);
        }
      }
      await sink.flush();
      await sink.close();

      if (!mounted) return;
      setState(() {
        _downloadProgress[course.lessonId] = 0.98;
      });
      onProgress?.call(0.98);

      final package = await LessonPackageReader.read(tempFile.path);
      final imported = await widget.repository.importPackage(package);

      if (!mounted) return;
      setState(() {
        _downloadingIds.remove(course.lessonId);
        _downloadProgress.remove(course.lessonId);
        _importedTitles.add(course.title);
        _importedTitles.add(lesson.title);
        _importedIds.add(course.lessonId);
        if (lesson.lessonId != null) _importedIds.add(lesson.lessonId!);
      });
      onProgress?.call(1.0);

      widget.onLessonImported?.call(imported);

      if (showSnack && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('已导入: ${course.title}')));
      }

      if (autoOpen && mounted) {
        await _openLessonInPlayer(imported);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadingIds.remove(course.lessonId);
        _downloadProgress.remove(course.lessonId);
      });
      if (showSnack && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('导入失败: $e')));
      }
      rethrow;
    } finally {
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }

  /// 批量下载当前年级分册的全部未就绪课件
  Future<void> _startBatchDownload(List<PrimaryChineseLesson> lessons) async {
    if (_isBatchDownloading) return;

    final List<MapEntry<PrimaryChineseLesson, CloudCourse>> queue = [];
    for (final l in lessons) {
      if (l.hasSubLessons) {
        for (final sub in l.subLessons) {
          final cloud = _findCloudCourse(sub);
          if (cloud != null && !_isLessonImported(sub, cloud)) {
            queue.add(MapEntry(sub, cloud));
          }
        }
      } else {
        final cloud = _findCloudCourse(l);
        if (cloud != null && !_isLessonImported(l, cloud)) {
          queue.add(MapEntry(l, cloud));
        }
      }
    }

    if (queue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前分册的所有课件已全部下载就绪！')),
      );
      return;
    }

    setState(() {
      _isBatchDownloading = true;
      _batchTotal = queue.length;
      _batchCurrentIndex = 0;
      _batchCurrentTitle = queue.first.value.title;
      _batchSubProgress = 0.0;
      _cancelBatchRequested = false;
    });

    int downloadedCount = 0;
    for (int i = 0; i < queue.length; i++) {
      if (_cancelBatchRequested || !mounted) {
        break;
      }
      final item = queue[i];
      final lesson = item.key;
      final course = item.value;

      setState(() {
        _batchCurrentIndex = i;
        _batchCurrentTitle = course.title;
        _batchSubProgress = 0.05;
      });

      try {
        await _downloadAndImport(
          lesson,
          course,
          showSnack: false,
          onProgress: (p) {
            if (mounted) {
              setState(() => _batchSubProgress = p);
            }
          },
        );
        downloadedCount++;
      } catch (e) {
        debugPrint('[BatchDownload] 失败: ${course.title} $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _isBatchDownloading = false;
      _cancelBatchRequested = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _cancelBatchRequested
              ? '批量下载已取消，已成功下载 $downloadedCount 篇'
              : '批量下载完成！共成功下载 $downloadedCount 篇课件',
        ),
      ),
    );
  }

  void _cancelBatchDownload() {
    setState(() {
      _cancelBatchRequested = true;
    });
  }

  /// 呼出课程与存储空间管理面板
  void _showStorageManagementSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _StorageManagementSheet(
        repository: widget.repository,
        onStorageChanged: () {
          _loadCatalog();
        },
      ),
    );
  }

  void _showServerSettings() {
    final controller = TextEditingController(text: _serverBaseUrl);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.ll.surface,
        title: const Text('云端源地址设置'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '服务器 Base URL',
            hintText: 'http://123.57.84.97:3100',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final newUrl = controller.text.trim();
              if (newUrl.isNotEmpty) {
                setState(
                  () => _serverBaseUrl = newUrl.replaceAll(RegExp(r'/+$'), ''),
                );
                Navigator.of(ctx).pop();
                _loadCatalog();
              }
            },
            child: const Text('保存并刷新'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;

    return LLPage(
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: ll.textPrimary),
        tooltip: '返回课程',
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '小学语文在线课程库',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: ll.textPrimary,
            ),
          ),
          Text(
            '统编版 1-6 年级 · 名师原声朗读',
            style: TextStyle(fontSize: 11, color: ll.textTertiary),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: '课程存储管理',
          icon: Icon(Icons.inventory_2_outlined, color: ll.textSecondary, size: 20),
          onPressed: _showStorageManagementSheet,
        ),
        IconButton(
          tooltip: '服务器设置',
          icon: Icon(Icons.settings_outlined, color: ll.textSecondary, size: 20),
          onPressed: _showServerSettings,
        ),
        IconButton(
          tooltip: '刷新',
          icon: Icon(Icons.refresh, color: ll.textPrimary),
          onPressed: _loadCatalog,
        ),
      ],
      body: Column(
          children: [
          // 全局搜索栏 (顶部)
          _buildSearchBar(ll),

          // 三层级导航：Tier 1 (年级) & Tier 2 (分册)
          if (_searchQuery.isEmpty) ...[
            _buildGradeSelector(ll),
            _buildTermSelector(ll),
            _buildBatchActionBar(ll),
            const Divider(height: 1),
          ],

          // Tier 3: 具体课程列表 / 搜索结果
          Expanded(
            child: _loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text('正在连接云端课程库...',
                            style: TextStyle(color: ll.textSecondary)),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      if (_errorMessage != null)
                        Container(
                          color: Colors.orange.withValues(alpha: 0.12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.cloud_off,
                                  size: 15, color: Colors.orange),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              TextButton(
                                onPressed: _loadCatalog,
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text('重试',
                                    style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: _searchQuery.isNotEmpty
                            ? _buildSearchResults(ll)
                            : _buildLessonList(ll),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// 全局搜索栏
  Widget _buildSearchBar(LLPalette ll) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _searchController,
        style: TextStyle(fontSize: 14, color: ll.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          hintText: '', // 2026-10-20 郭老师：搜索框灰色提示字是废话，删掉
          hintStyle: TextStyle(fontSize: 13, color: ll.textTertiary),
          prefixIcon: Icon(Icons.search, size: 20, color: ll.textTertiary),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 18, color: ll.textTertiary),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
          filled: true,
          fillColor: ll.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: ll.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: ll.divider),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onChanged: (val) => setState(() => _searchQuery = val.trim()),
      ),
    );
  }

  /// Tier 1: 年级选择 (一年级 ~ 九年级)
  Widget _buildGradeSelector(LLPalette ll) {
    final grades = [1, 2, 3, 4, 5, 6, 7, 8, 9];
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: grades.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, idx) {
          final g = grades[idx];
          final isSelected = g == _selectedGrade;
          final label = switch (g) {
            1 => '一年级',
            2 => '二年级',
            3 => '三年级',
            4 => '四年级',
            5 => '五年级',
            6 => '六年级',
            7 => '七年级',
            8 => '八年级',
            9 => '九年级',
            _ => '$g年级',
          };
          final hasLiveCourses = g == 2;

          return ChoiceChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label),
                if (hasLiveCourses) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.orange.shade700
                          : Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '已上线',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : Colors.orange,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            selected: isSelected,
            selectedColor: Colors.blueAccent.withValues(alpha: 0.25),
            backgroundColor: ll.surface,
            labelStyle: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.blueAccent : ll.textSecondary,
            ),
            side: BorderSide(
              color: isSelected ? Colors.blueAccent : ll.divider,
            ),
            onSelected: (_) {
              setState(() => _selectedGrade = g);
              _restoreExpandedUnits();
            },
          );
        },
      ),
    );
  }

  /// Tier 2: 分册选择 (上册 / 下册)
  Widget _buildTermSelector(LLPalette ll) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          _termChip('上册', ll),
          const SizedBox(width: 10),
          _termChip('下册', ll),
          const Spacer(),
          Text(
            '统编教材标准目次',
            style: TextStyle(fontSize: 11, color: ll.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _termChip(String term, LLPalette ll) {
    final isSelected = _selectedTerm == term;
    return InkWell(
      onTap: () {
        setState(() => _selectedTerm = term);
        _restoreExpandedUnits();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.blueAccent.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blueAccent : ll.divider,
          ),
        ),
        child: Text(
          term,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.blueAccent : ll.textSecondary,
          ),
        ),
      ),
    );
  }

  /// 年级分册批量下载与存储管理栏
  Widget _buildBatchActionBar(LLPalette ll) {
    final lessons = PrimaryChineseCurriculum.getLessons(_selectedGrade, _selectedTerm);
    final List<MapEntry<PrimaryChineseLesson, CloudCourse>> downloadableList = [];
    for (final l in lessons) {
      if (l.hasSubLessons) {
        for (final sub in l.subLessons) {
          final cloud = _findCloudCourse(sub);
          if (cloud != null) {
            downloadableList.add(MapEntry(sub, cloud));
          }
        }
      } else {
        final cloud = _findCloudCourse(l);
        if (cloud != null) {
          downloadableList.add(MapEntry(l, cloud));
        }
      }
    }

    final totalCount = downloadableList.length;
    final pendingList = downloadableList
        .where((e) => !_isLessonImported(e.key, e.value))
        .toList();
    final pendingCount = pendingList.length;
    final allDone = totalCount > 0 && pendingCount == 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: ll.surface.withValues(alpha: 0.65),
      child: _isBatchDownloading
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '批量下载中 (${_batchCurrentIndex + 1}/$_batchTotal): $_batchCurrentTitle',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ll.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: _cancelBatchDownload,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: Colors.redAccent,
                      ),
                      child: const Text('取消', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _batchTotal > 0
                        ? ((_batchCurrentIndex + _batchSubProgress) / _batchTotal)
                            .clamp(0.0, 1.0)
                        : null,
                    minHeight: 4,
                    backgroundColor: ll.divider.withValues(alpha: 0.4),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                // 2026-10-20 郭老师：删除「本册已全部就绪 / 已下 X 篇」提示行（废话），
                // 只留状态点（就绪=绿 / 未就绪=灰）与「批量下载」动作。
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: allDone
                        ? const Color(0xFF4CAF50)
                        : ll.textTertiary.withValues(alpha: 0.35),
                  ),
                ),
                const SizedBox(width: 6),
                if (!allDone && pendingCount > 0) ...[
                  FilledButton.tonalIcon(
                    onPressed: () => _startBatchDownload(lessons),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.download_rounded, size: 14),
                    label: const Text(
                      '全部下载',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                IconButton(
                  tooltip: '存储空间管理',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: Icon(
                    Icons.inventory_2_outlined,
                    size: 18,
                    color: ll.textSecondary,
                  ),
                  onPressed: _showStorageManagementSheet,
                ),
              ],
            ),
    );
  }

  /// Tier 3: 具体课文列表 (按当前选中的 年级 + 分册，支持手风琴/折叠面板展开与收起)
  Widget _buildLessonList(LLPalette ll) {
    final lessons =
        PrimaryChineseCurriculum.getLessons(_selectedGrade, _selectedTerm);

    if (lessons.isEmpty) {
      return Center(
        child: Text(
          '该分册目次正在整理中',
          style: TextStyle(color: ll.textTertiary),
        ),
      );
    }

    // 按单元聚合，保留标准目次顺序
    final Map<String, List<PrimaryChineseLesson>> unitMap = {};
    for (final lesson in lessons) {
      unitMap.putIfAbsent(lesson.unit, () => []).add(lesson);
    }

    final unitEntries = unitMap.entries.toList();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      itemCount: unitEntries.length,
      itemBuilder: (context, index) {
        final entry = unitEntries[index];
        final unitName = entry.key;
        final unitLessons = entry.value;
        final isExpanded = _expandedUnits.contains(unitName);

        return _buildUnitSection(
          unitName: unitName,
          unitIndex: index + 1,
          lessons: unitLessons,
          isExpanded: isExpanded,
          ll: ll,
        );
      },
    );
  }

  /// 单元折叠栏卡片（手风琴/折叠面板）
  Widget _buildUnitSection({
    required String unitName,
    required int unitIndex,
    required List<PrimaryChineseLesson> lessons,
    required bool isExpanded,
    required LLPalette ll,
  }) {
    // 2026-10-20 郭老师：不再统计/展示「已就绪 N 篇」文字——就绪状态只用颜色表示
    // （就绪=绿，未就绪=灰），见下方 Text 的 color/fontWeight。
    final hasReady = lessons.any((l) =>
        (l.isPlayable && _isLessonImported(l, _findCloudCourse(l))) ||
        l.subLessons
            .any((s) => _isLessonImported(s, _findCloudCourse(s))));

    final totalCount = lessons.fold<int>(
      0,
      (sum, l) =>
          sum +
          (l.hasSubLessons ? l.subLessons.length : 1) +
          (l.isPlayable && l.hasSubLessons ? 1 : 0),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: ll.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExpanded
              ? Colors.blueAccent.withValues(alpha: 0.35)
              : ll.divider.withValues(alpha: 0.6),
          width: isExpanded ? 1.2 : 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 单元头部点击栏（折叠控制条）
          InkWell(
            onTap: () => _toggleUnit(unitName),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // 单元序号胶囊
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isExpanded
                          ? Colors.blueAccent.withValues(alpha: 0.15)
                          : ll.divider.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$unitIndex',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isExpanded ? Colors.blueAccent : ll.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // 单元名称与统计信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          unitName,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: ll.textPrimary,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$totalCount 篇课文',
                          style: TextStyle(
                            fontSize: 11,
                            color: hasReady
                                ? const Color(0xFF4CAF50)
                                : ll.textTertiary,
                            fontWeight:
                                hasReady ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 折叠展开旋转箭头
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: isExpanded ? Colors.blueAccent : ll.textTertiary,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 展开的内容区域
          if (isExpanded) ...[
            Divider(
              height: 1,
              thickness: 0.6,
              color: ll.divider.withValues(alpha: 0.4),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: lessons.map((lesson) {
                  final cloud = _findCloudCourse(lesson);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: lesson.hasSubLessons
                        ? _buildSubLessonsCard(lesson, ll)
                        : _buildLessonCard(lesson, cloud, ll),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 全局搜索结果视图
  Widget _buildSearchResults(LLPalette ll) {
    final results = PrimaryChineseCurriculum.search(_searchQuery);

    if (results.isEmpty) {
      return LLEmptyState(
        icon: Icons.search_off_rounded,
        title: '未搜到与 "$_searchQuery" 相关的课文',
        hint: '支持搜索课文名、古诗名、单元名或年级',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final lesson = results[index];
        final cloud = _findCloudCourse(lesson);
        if (lesson.hasSubLessons) {
          return _buildSubLessonsCard(lesson, ll);
        }
        return _buildLessonCard(lesson, cloud, ll, showGradeBadge: true);
      },
    );
  }

  /// 2026-10-20 郭老师：语文园地子栏目的展开集合（**默认收起**），
  /// 由用户点标题行右侧的箭头自己展开/收起。
  final Set<String> _expandedSubCards = {};

  /// 语文园地复合卡片（展示其下属的 识字加油站、字词句运用、日积月累、我爱阅读 等子栏目）
  Widget _buildSubLessonsCard(PrimaryChineseLesson lesson, LLPalette ll) {
    final subLessons = lesson.subLessons;
    final cardKey =
        '${_selectedGrade}_${_selectedTerm}_${lesson.displayTitle}';
    final isCardExpanded = _expandedSubCards.contains(cardKey);
    // 语文园地父级本身可能是「可点播整篇」（如 3~6 年级上册），此时除展开子板块外，
    // 仍需保留父级的精听/下载入口，避免课包变成孤儿。
    final parentCloud = _findCloudCourse(lesson);
    final parentPlayable = lesson.isPlayable;
    final parentImported = parentPlayable && _isLessonImported(lesson, parentCloud);
    final subImported = subLessons
        .where((sub) => _isLessonImported(sub, _findCloudCourse(sub)))
        .length;
    final importedCount = subImported + (parentImported ? 1 : 0);
    final someImported = importedCount > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: ll.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: someImported
              ? const Color(0xFF4CAF50).withValues(alpha: 0.28)
              : ll.divider.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 园地头部
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: someImported
                        ? const Color(0xFF1B3B2B)
                        : ll.divider.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(
                    Icons.collections_bookmark_rounded,
                    color: someImported ? const Color(0xFF4CAF50) : ll.textSecondary,
                    size: 15,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    lesson.displayTitle,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: ll.textPrimary,
                    ),
                  ),
                ),
                // 2026-10-20 郭老师：取消「已就绪 / 全部就绪 / X/Y 篇就绪」文字，
                // 就绪 = 绿色圆点，未就绪 = 灰色圆点（不再显示任何就绪字样）。
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: someImported
                        ? const Color(0xFF4CAF50)
                        : ll.textTertiary.withValues(alpha: 0.35),
                  ),
                ),
                // 展开/收起箭头（默认收起，用户自己决定要不要展开 4 个子项目）
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() {
                    if (isCardExpanded) {
                      _expandedSubCards.remove(cardKey);
                    } else {
                      _expandedSubCards.add(cardKey);
                    }
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Icon(
                      isCardExpanded
                          ? Icons.unfold_less_rounded
                          : Icons.unfold_more_rounded,
                      size: 16,
                      color: ll.textSecondary,
                    ),
                  ),
                ),
                if (parentPlayable) ...[
                  const SizedBox(width: 6),
                  if (parentImported)
                    FilledButton.icon(
                      onPressed: () => _openLessonByCatalog(lesson, parentCloud),
                      icon: const Icon(Icons.headphones_rounded, size: 12),
                      label: const Text('听', style: TextStyle(fontSize: 10.5)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    )
                  else if (parentCloud != null)
                    FilledButton.icon(
                      onPressed: _downloadingIds.contains(parentCloud.lessonId)
                          ? null
                          : () => _downloadAndImport(lesson, parentCloud, autoOpen: true),
                      icon: _downloadingIds.contains(parentCloud.lessonId)
                          ? const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.download_rounded, size: 12),
                      label: Text(
                        _downloadingIds.contains(parentCloud.lessonId)
                            ? '${((_downloadProgress[parentCloud.lessonId] ?? 0.0) * 100).toInt()}%'
                            : '听',
                        style: const TextStyle(fontSize: 10.5),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Divider(height: 1, thickness: 0.6, color: ll.divider.withValues(alpha: 0.4)),
            const SizedBox(height: 4),

            // 下属各子栏目（默认收起；展开后点项目名称直接进入该项目）
            if (isCardExpanded)
              ...subLessons.map((sub) => _buildSubLessonRow(sub, ll)),
          ],
        ),
      ),
    );
  }

  /// 园地内的单行子栏目
  Widget _buildSubLessonRow(PrimaryChineseLesson subLesson, LLPalette ll) {
    final subCloud = _findCloudCourse(subLesson);
    final isImported = _isLessonImported(subLesson, subCloud);
    final isAvailable = subCloud != null || isImported;
    final isDownloading =
        isAvailable && subCloud != null && _downloadingIds.contains(subCloud.lessonId);
    final progress =
        (isAvailable && subCloud != null) ? (_downloadProgress[subCloud.lessonId] ?? 0.0) : 0.0;
    final title = subLesson.displayTitle;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        if (isImported) {
          _openLessonByCatalog(subLesson, subCloud);
        } else if (isAvailable && subCloud != null && !isDownloading) {
          _downloadAndImport(subLesson, subCloud, autoOpen: true);
        } else if (!isAvailable) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text('《$title》示范朗读正在录制中，敬请期待！')),
            );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            Icon(
              isImported
                  ? Icons.check_circle_rounded
                  : (isAvailable ? Icons.headphones_rounded : Icons.radio_button_unchecked),
              size: 14,
              color: isImported
                  ? const Color(0xFF4CAF50)
                  : (isAvailable ? Colors.blueAccent : ll.textTertiary),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isImported ? FontWeight.w500 : FontWeight.normal,
                  height: 1.3,
                  color: isAvailable ? ll.textPrimary : ll.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 2026-10-20 郭老师：语文园地子项**不要「精听」按钮**——
            // 直接点项目名称就进入该项目（整行 onTap 已经是这个行为）。
            // 只保留「未下载」态的下载/进度按钮（那是状态，不是重复入口）。
            if (isAvailable && subCloud != null)
              FilledButton.icon(
                onPressed: isDownloading
                    ? null
                    : () => _downloadAndImport(subLesson, subCloud, autoOpen: true),
                icon: isDownloading
                    ? const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.download_rounded, size: 12),
                label: Text(
                  isDownloading ? '${(progress * 100).toInt()}%' : '精听',
                  style: const TextStyle(fontSize: 10.5),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              )
            else
              Text(
                '待录入',
                style: TextStyle(fontSize: 11, color: ll.textTertiary),
              ),
          ],
        ),
      ),
    );
  }

  /// 2026-10-20 郭老师：字词表栏的展开集合（**默认收起**）。
  final Set<String> _expandedWordCards = {};

  /// 2026-10-20 郭老师：把「会认字 / 会写字 / 词语」作为这篇课文的一个
  /// **可展开/收起的栏**（此前它们是默认铺开的字表；现在收起来，由用户自己展开）。
  ///
  /// 数据形态：子栏目的 `title` 是「栏目名\n字1 字2 字3」，
  /// 首行作栏目名、其余行作字词内容（与思维导图同一套约定）。
  Widget? _buildWordPanel(PrimaryChineseLesson lesson, LLPalette ll) {
    const groups = {'会认字', '会写字', '词语'};
    final wordGroups = <MapEntry<String, String>>[];
    for (final sub in lesson.subLessons) {
      final lines = sub.title.split('\n');
      if (lines.isEmpty) continue;
      final name = lines.first.trim();
      if (!groups.contains(name)) continue;
      final words =
          lines.length > 1 ? lines.sublist(1).join(' ').trim() : '';
      if (words.isEmpty) continue;
      wordGroups.add(MapEntry(name, words));
    }
    if (wordGroups.isEmpty) return null;

    final key = '${_selectedGrade}_${_selectedTerm}_${lesson.displayTitle}';
    final expanded = _expandedWordCards.contains(key);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 内层手势优先于外层 InkWell：点字词栏不会误触发"进入课文/下载"。
      onTap: () => setState(() {
        if (expanded) {
          _expandedWordCards.remove(key);
        } else {
          _expandedWordCards.add(key);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  expanded
                      ? Icons.unfold_less_rounded
                      : Icons.unfold_more_rounded,
                  size: 14,
                  color: ll.textTertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  '字词表',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: ll.textSecondary,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    wordGroups.map((g) => g.key).join(' · '),
                    style: TextStyle(fontSize: 10.5, color: ll.textTertiary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (expanded) ...[
              const SizedBox(height: 5),
              for (final g in wordGroups)
                Padding(
                  padding: const EdgeInsets.only(left: 18, top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 50,
                        child: Text(
                          g.key,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: ll.textTertiary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          g.value,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: ll.textSecondary,
                            height: 1.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// 单个课文卡片（紧凑高密度、纯课题展示）
  Widget _buildLessonCard(
    PrimaryChineseLesson lesson,
    CloudCourse? cloud,
    LLPalette ll, {
    bool showGradeBadge = false,
  }) {
    final isImported = _isLessonImported(lesson, cloud);
    final isAvailable = cloud != null || isImported;
    final isDownloading =
        isAvailable && cloud != null && _downloadingIds.contains(cloud.lessonId);
    final progress =
        (isAvailable && cloud != null) ? (_downloadProgress[cloud.lessonId] ?? 0.0) : 0.0;
    final displayTitle = lesson.displayTitle;
    // 2026-10-20 郭老师：字词表（会认字/会写字/词语）作为这篇课文的
    // 一个可展开/收起的栏，默认收起。
    final wordPanel = _buildWordPanel(lesson, ll);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: ll.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isAvailable
              ? (isImported
                  ? const Color(0xFF4CAF50).withValues(alpha: 0.25)
                  : Colors.blueAccent.withValues(alpha: 0.25))
              : ll.divider.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          if (isImported) {
            _openLessonByCatalog(lesson, cloud);
          } else if (isAvailable && cloud != null && !isDownloading) {
            _downloadAndImport(lesson, cloud, autoOpen: true);
          } else if (!isAvailable) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                    '《$displayTitle》权威示范朗读正在录制中，上线后即可一键云端下载！',
                  ),
                ),
              );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Icon
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isImported
                          ? const Color(0xFF1B3B2B)
                          : (isAvailable
                              ? Colors.blueAccent.withValues(alpha: 0.12)
                              : ll.divider.withValues(alpha: 0.2)),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      isImported
                          ? Icons.check_circle_rounded
                          : (isAvailable
                              ? Icons.cloud_download_rounded
                              : Icons.menu_book_rounded),
                      color: isImported
                          ? const Color(0xFF4CAF50)
                          : (isAvailable ? Colors.blueAccent : ll.textTertiary),
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),

                  // 只要课题
                  if (showGradeBadge) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: ll.divider,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${lesson.gradeLabel}${lesson.term} · ${lesson.unit}',
                        style: TextStyle(
                          fontSize: 10,
                          color: ll.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      displayTitle,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: isAvailable || isImported
                            ? ll.textPrimary
                            : ll.textSecondary,
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Action button
                  if (isAvailable)
                    if (isImported)
                      FilledButton.icon(
                        onPressed: () => _openLessonByCatalog(lesson, cloud),
                        icon: const Icon(Icons.headphones_rounded, size: 13),
                        label: const Text('听', style: TextStyle(fontSize: 11)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      )
                    else if (cloud != null)
                      FilledButton.icon(
                        onPressed: isDownloading
                            ? null
                            : () =>
                                _downloadAndImport(lesson, cloud, autoOpen: true),
                        icon: isDownloading
                            ? const SizedBox(
                                width: 11,
                                height: 11,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.download_rounded, size: 13),
                        label: Text(
                          isDownloading
                              ? '${(progress * 100).toInt()}%'
                              : '听',
                          style: const TextStyle(fontSize: 11),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      )
                    else
                      Text(
                        '待录入',
                        style: TextStyle(fontSize: 11, color: ll.textTertiary),
                      )
                  else
                    Text(
                      '待录入',
                      style: TextStyle(fontSize: 11, color: ll.textTertiary),
                    ),
                ],
              ),
              ?wordPanel,
              if (isDownloading) ...[
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    minHeight: 2.5,
                    backgroundColor: ll.divider,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.blueAccent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 课程存储空间管理面板 (按年级查看存储占用与一键批量清空)
class _StorageManagementSheet extends StatefulWidget {
  const _StorageManagementSheet({
    required this.repository,
    required this.onStorageChanged,
  });

  final LessonRepository repository;
  final VoidCallback onStorageChanged;

  @override
  State<_StorageManagementSheet> createState() => _StorageManagementSheetState();
}

class _StorageManagementSheetState extends State<_StorageManagementSheet> {
  bool _loading = true;
  Map<String, GradeStorageStats> _stats = {};
  int _totalBytes = 0;
  int _totalLessons = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    final stats = await widget.repository.getLessonsStorageStats();
    int bytes = 0;
    int count = 0;
    for (final s in stats.values) {
      bytes += s.totalBytes;
      count += s.lessonCount;
    }
    if (mounted) {
      setState(() {
        _stats = stats;
        _totalBytes = bytes;
        _totalLessons = count;
        _loading = false;
      });
    }
  }

  Future<void> _confirmDeleteGrade(String gradeLabel, GradeStorageStats stat) async {
    final mb = (stat.totalBytes / (1024 * 1024)).toStringAsFixed(1);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.ll.surface,
        title: Text('清空 $gradeLabel 全部课件？'),
        content: Text(
          '将删除 $gradeLabel 已下载的 ${stat.lessonCount} 门课包，立即释放 $mb MB 手机存储空间。\n\n'
          '提示：您的跟读学习记录和打卡统计将被安全保留，未来随时可以重新下载。',
          style: TextStyle(
            fontSize: 13.5,
            color: context.ll.textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('保留'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('清空 ($mb MB)'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await widget.repository.deleteLessons(stat.lessonIds, preserveProgress: true);
      widget.onStorageChanged();
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清空 $gradeLabel 课件，成功释放 $mb MB 存储空间')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final totalMb = (_totalBytes / (1024 * 1024)).toStringAsFixed(1);

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: ll.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 拖手
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: ll.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: ll.accent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '小学语文课件存储管理',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: ll.textPrimary,
                        ),
                      ),
                      Text(
                        '自由下载与批量删除各年级课件，释放手机空间',
                        style: TextStyle(fontSize: 11, color: ll.textTertiary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: ll.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 概览统计卡片
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: ll.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ll.divider.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: ll.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.pie_chart_outline_rounded, color: ll.accent, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '当前已占用手机存储: $totalMb MB',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: ll.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '共已下载 $_totalLessons 门课件 · 删除后打卡记录不受影响',
                          style: TextStyle(fontSize: 11, color: ll.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 各年级列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    children: [
                      for (final grade in ['一年级', '二年级', '三年级', '四年级', '五年级', '六年级', '其他'])
                        _buildGradeStorageItem(grade, ll),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradeStorageItem(String gradeLabel, LLPalette ll) {
    final stat = _stats[gradeLabel];
    final count = stat?.lessonCount ?? 0;
    final bytes = stat?.totalBytes ?? 0;
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
    final hasData = count > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: ll.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ll.divider.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: hasData
                  ? ll.accent.withValues(alpha: 0.12)
                  : ll.divider.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.school_outlined,
              size: 16,
              color: hasData ? ll.accent : ll.textTertiary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gradeLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: ll.textPrimary,
                  ),
                ),
                Text(
                  hasData ? '$count 门课件已下载 · 占用 $mb MB' : '未下载课件 (0 MB)',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: hasData ? ll.textSecondary : ll.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (hasData)
            TextButton.icon(
              onPressed: () => _confirmDeleteGrade(gradeLabel, stat!),
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 15),
              label: const Text('清空', style: TextStyle(fontSize: 12)),
            )
          else
            Text(
              '无数据',
              style: TextStyle(fontSize: 11.5, color: ll.textTertiary),
            ),
        ],
      ),
    );
  }
}

