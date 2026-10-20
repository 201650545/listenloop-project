import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../lesson/lesson_package_reader.dart';
import '../models/lesson.dart';
import '../storage/lesson_repository.dart';
import '../theme/listenloop_theme.dart';

/// Represents a single course item parsed from `catalog.json`.
class CloudCourse {
  const CloudCourse({
    required this.lessonId,
    required this.title,
    required this.series,
    required this.sentenceCount,
    required this.language,
    required this.fileName,
    required this.fileSize,
    required this.downloadPath,
  });

  factory CloudCourse.fromJson(Map<String, dynamic> json) {
    return CloudCourse(
      lessonId: json['lessonId'] as String? ?? '',
      title: json['title'] as String? ?? '未命名课程',
      series: json['series'] as String? ?? '默认系列',
      sentenceCount: json['sentenceCount'] as int? ?? 0,
      language: json['language'] as String? ?? 'zh',
      fileName: json['fileName'] as String? ?? '',
      fileSize: json['fileSize'] as int? ?? 0,
      downloadPath: json['downloadPath'] as String? ?? '',
    );
  }

  final String lessonId;
  final String title;
  final String series;
  final int sentenceCount;
  final String language;
  final String fileName;
  final int fileSize;
  final String downloadPath;
}

/// Cloud Course Catalog Sheet (OTA 在线课程库)
///
/// Fetches `catalog.json` from the distribution server, displays courses
/// grouped by series, and enables one-click download and instant import
/// into ListenLoop without needing cables or adb.
class CloudCatalogSheet extends StatefulWidget {
  const CloudCatalogSheet({
    required this.repository,
    this.onLessonImported,
    super.key,
  });

  final LessonRepository repository;
  final ValueChanged<Lesson>? onLessonImported;

  static const String defaultServerUrl = 'http://123.57.84.97:3100';

  @override
  State<CloudCatalogSheet> createState() => _CloudCatalogSheetState();
}

class _CloudCatalogSheetState extends State<CloudCatalogSheet> {
  bool _loading = true;
  String? _errorMessage;
  List<CloudCourse> _courses = [];
  Set<String> _importedTitles = {};
  final Map<String, double> _downloadProgress = {};
  final Set<String> _downloadingIds = {};
  String _serverBaseUrl = CloudCatalogSheet.defaultServerUrl;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      // 1. Load local lessons to cross-reference already imported courses
      final localLessons = await widget.repository.listLessons();
      _importedTitles = localLessons.map((item) => item.lesson.title).toSet();

      // 2. Fetch catalog.json from cloud server (bypass caching)
      final uri = Uri.parse('$_serverBaseUrl/catalog.json?t=${DateTime.now().millisecondsSinceEpoch}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        throw HttpException('服务器返回错误码: ${resp.statusCode}');
      }

      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final rawList = data['courses'] as List<dynamic>? ?? [];
      final list = rawList
          .map((item) => CloudCourse.fromJson(item as Map<String, dynamic>))
          .toList();

      if (!mounted) return;
      setState(() {
        _courses = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '连接云端课程库失败: $e\n\n提示：请检查手机网络连接。';
        _loading = false;
      });
    }
  }

  Future<void> _downloadAndImport(CloudCourse course) async {
    if (_downloadingIds.contains(course.lessonId)) return;

    setState(() {
      _downloadingIds.add(course.lessonId);
      _downloadProgress[course.lessonId] = 0.05;
    });

    File? tempFile;
    try {
      final downloadUrl = '$_serverBaseUrl${course.downloadPath}';
      final req = http.Request('GET', Uri.parse(downloadUrl));
      final streamed = await req.send().timeout(const Duration(seconds: 15));

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
          setState(() {
            _downloadProgress[course.lessonId] = (receivedBytes / totalBytes).clamp(0.0, 0.95);
          });
        }
      }
      await sink.flush();
      await sink.close();

      if (!mounted) return;
      setState(() {
        _downloadProgress[course.lessonId] = 0.98;
      });

      // Import via LessonPackageReader
      final package = await LessonPackageReader.read(tempFile.path);
      final imported = await widget.repository.importPackage(package);

      if (!mounted) return;
      setState(() {
        _downloadingIds.remove(course.lessonId);
        _downloadProgress.remove(course.lessonId);
        _importedTitles.add(course.title);
      });

      widget.onLessonImported?.call(imported);

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('已导入: ${course.title}')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadingIds.remove(course.lessonId);
        _downloadProgress.remove(course.lessonId);
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('导入失败: $e')));
    } finally {
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
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
            hintText: 'http://123.57.84.97:8080',
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
                setState(() => _serverBaseUrl = newUrl.replaceAll(RegExp(r'/+$'), ''));
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

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: ll.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: ll.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Top bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.cloud_download_rounded, color: ll.textPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '在线课程库 (云端下载)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: ll.textPrimary,
                        ),
                      ),
                      Text(
                        '名师原声 · 初读/熟读自由切换 · 一键下载',
                        style: TextStyle(fontSize: 12, color: ll.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '设置源地址',
                  icon: Icon(Icons.settings_outlined, color: ll.textSecondary, size: 20),
                  onPressed: _showServerSettings,
                ),
                IconButton(
                  tooltip: '刷新',
                  icon: Icon(Icons.refresh, color: ll.textPrimary),
                  onPressed: _loadCatalog,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Body
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final ll = context.ll;

    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('正在连接云端课程库...', style: TextStyle(color: ll.textSecondary)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.orange),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: ll.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadCatalog,
                icon: const Icon(Icons.refresh),
                label: const Text('重试连接'),
              ),
            ],
          ),
        ),
      );
    }

    if (_courses.isEmpty) {
      return Center(
        child: Text('云端暂无可用课程包', style: TextStyle(color: ll.textSecondary)),
      );
    }

    // Group by series
    final Map<String, List<CloudCourse>> grouped = {};
    for (final c in _courses) {
      grouped.putIfAbsent(c.series, () => []).add(c);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: grouped.keys.length,
      itemBuilder: (context, seriesIndex) {
        final seriesName = grouped.keys.elementAt(seriesIndex);
        final seriesCourses = grouped[seriesName]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.blueAccent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    seriesName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: ll.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${seriesCourses.length} 节',
                    style: TextStyle(fontSize: 12, color: ll.textTertiary),
                  ),
                ],
              ),
            ),
            ...seriesCourses.map((c) => _buildCourseCard(c)),
          ],
        );
      },
    );
  }

  Widget _buildCourseCard(CloudCourse course) {
    final ll = context.ll;
    final isImported = _importedTitles.contains(course.title);
    final isDownloading = _downloadingIds.contains(course.lessonId);
    final progress = _downloadProgress[course.lessonId] ?? 0.0;
    final sizeKb = course.fileSize ~/ 1024;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: ll.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: ll.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isImported
                    ? const Color(0xFF1B3B2B)
                    : Colors.blueAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isImported ? Icons.check_circle_outline : Icons.menu_book_outlined,
                color: isImported ? const Color(0xFF4CAF50) : Colors.blueAccent,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: ll.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${course.sentenceCount} 句 · $sizeKb KB',
                    style: TextStyle(fontSize: 12, color: ll.textSecondary),
                  ),
                  if (isDownloading) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: ll.divider,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (isImported)
              OutlinedButton(
                onPressed: isDownloading ? null : () => _downloadAndImport(course),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: BorderSide(color: ll.divider),
                ),
                child: const Text('重新导入', style: TextStyle(fontSize: 12)),
              )
            else
              FilledButton.icon(
                onPressed: isDownloading ? null : () => _downloadAndImport(course),
                icon: isDownloading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.download, size: 16),
                label: Text(
                  isDownloading ? '${(progress * 100).toInt()}%' : '下载导入',
                  style: const TextStyle(fontSize: 12),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
