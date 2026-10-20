import 'package:flutter/foundation.dart';

/// Single curriculum entry for People's Education Press (统编版) Primary Chinese (1-6 年级).
@immutable
class PrimaryChineseLesson {
  const PrimaryChineseLesson({
    required this.grade,
    required this.term,
    required this.unit,
    required this.title,
    this.lessonId,
    this.isDualMode = false,
    this.subLessons = const [],
  });

  /// 1 to 6
  final int grade;

  /// '上册' or '下册'
  final String term;

  /// e.g. '第一单元', '第二单元', '第三单元'
  final String unit;

  /// e.g. '小蝌蚪找妈妈', '我是什么'
  final String title;

  /// If this lesson has a known server lessonId
  final String? lessonId;

  /// Whether this is a dual-mode package
  final bool isDualMode;

  /// 四级子分支（如语文园地下属的识字加油站、字词句运用、日积月累、我爱阅读）
  final List<PrimaryChineseLesson> subLessons;

  /// 是否包含子栏目（如语文园地）
  bool get hasSubLessons => subLessons.isNotEmpty;

  /// 是否带可点播的课包（配置了 lessonId 才有课包，无课包的字词节点不可点）
  bool get isPlayable => lessonId != null && lessonId!.isNotEmpty;

  /// 是否仅作容器展示（如语文园地：自身无课包，内容在其子栏目里）
  bool get isContainerOnly => !isPlayable && subLessons.isNotEmpty;

  String get gradeLabel {
    switch (grade) {
      case 1:
        return '一年级';
      case 2:
        return '二年级';
      case 3:
        return '三年级';
      case 4:
        return '四年级';
      case 5:
        return '五年级';
      case 6:
        return '六年级';
      case 7:
        return '七年级';
      case 8:
        return '八年级';
      case 9:
        return '九年级';
      default:
        return '$grade年级';
    }
  }

  String get fullTitle => '$gradeLabel$term · $title';

  String get displayTitle {
    final trimmed = title
        .replaceAll(RegExp(r'[（\(]双模[板版].*?[）\)]'), '')
        .replaceAll(RegExp(r'双模[板版]'), '')
        .trim();

    // 如果本身就是 "语文园地X" 或 "园地X"，始终完整保留 "语文园地一"、"语文园地二"
    if (RegExp(r'^(语文园地|园地)[一二三四五六七八九十]+$').hasMatch(trimmed)) {
      if (trimmed.startsWith('园地')) {
        return '语文$trimmed';
      }
      return trimmed;
    }

    // 只有在后面跟着具体子栏目时（如 "园地一 识字加油站"），才剥离前缀保留子项短名
    return trimmed
        .replaceAll(
          RegExp(r'^(课文\d+|识字\d+|示范课例|园地[一二三四五六七八]\s+|语文园地[一二三四五六七八]\s+)\s*'),
          '',
        )
        .trim();
  }

  /// 带课题序号的展示标题（优先采用官方教材课序，如 "1 小蝌蚪找妈妈"、"识字1 场景歌"、"语文园地一"）
  String numberedTitle({int? fallbackIndex}) {
    final clean = displayTitle;
    final trimmed = title
        .replaceAll(RegExp(r'[（\(]双模[板版].*?[）\)]'), '')
        .replaceAll(RegExp(r'双模[板版]'), '')
        .trim();

    // 1. 如果本身就是语文园地父节点（如 "语文园地一"、"园地一"），无论有没有 fallbackIndex，始终完整展示 "语文园地一"
    if (RegExp(r'^(语文园地|园地)[一二三四五六七八九十]+$').hasMatch(trimmed) ||
        RegExp(r'^(语文园地|园地)[一二三四五六七八九十]+$').hasMatch(clean)) {
      if (clean.startsWith('园地')) {
        return '语文$clean';
      }
      if (clean.startsWith('语文园地')) {
        return clean;
      }
      if (trimmed.startsWith('园地')) {
        return '语文$trimmed';
      }
      return trimmed;
    }

    // 2. 如果原始 title 包含 "课文1" / "课文2" 等，转为教材规范课序号 "1 小蝌蚪找妈妈"
    final kwMatch = RegExp(r'^课文(\d+)\s*(.*)').firstMatch(trimmed);
    if (kwMatch != null) {
      final num = kwMatch.group(1);
      return '$num $clean';
    }

    // 3. 如果包含 "识字1" / "识字2" 等，保留 "识字1 场景歌"
    final szMatch = RegExp(r'^识字(\d+)\s*(.*)').firstMatch(trimmed);
    if (szMatch != null) {
      final num = szMatch.group(1);
      return '识字$num $clean';
    }

    // 4. 如果没有自带课序但传入了 fallbackIndex（如其他年级单元自增序号）
    if (fallbackIndex != null) {
      return '$fallbackIndex $clean';
    }

    return clean;
  }
}

/// Official curriculum lessons for Grades 1-6 (统编版小学语文).
class PrimaryChineseCurriculum {
  static const List<PrimaryChineseLesson> allLessons = [
    // ==============================================================
    // 一年级上册 (统编版官方完整目次)
    // ==============================================================
    // 第一单元（识字）
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第一单元（识字）',
      title: '天地人',
      // 字词取课本三张表原文（识字表/写字表/词语表，2024新课标）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第一单元（识字）',
          title: '会认字\n天 地 人 你 我 他',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第一单元（识字）',
          title: '会写字\n天 地 人',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第一单元（识字）',
          title: '词语\n天地 人们 你我他',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第一单元（识字）',
      title: '金木水火土',
      // 字词取课本三张表原文（识字表/写字表/词语表，2024新课标）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第一单元（识字）',
          title: '会认字\n一 二 三 四 五 上 下',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第一单元（识字）',
          title: '会写字\n一 二 三 四 五 上 下',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第一单元（识字）',
          title: '词语\n上下 五个 金木水火土',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第一单元（识字）',
      title: '口耳目手足',
      // 字词取课本三张表原文（识字表/写字表/词语表，2024新课标）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第一单元（识字）',
          title: '会认字\n口 耳 目 手 足 站 坐',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第一单元（识字）',
          title: '会写字\n口 耳 目 手 足',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第一单元（识字）',
          title: '词语\n口耳 手足 站坐',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第一单元（识字）',
      title: '日月山川',
      // 字词取课本三张表原文（识字表/写字表/词语表，2024新课标）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第一单元（识字）',
          title: '会认字\n日 月 水 火 山 石 田 禾',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第一单元（识字）',
          title: '会写字\n日 月 水 火',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第一单元（识字）',
          title: '词语\n日月 山水 田禾',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第一单元（识字）',
      title: '语文园地一',
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第一单元（识字）',
          title: '识字加油站',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第一单元（识字）',
          title: '字词句运用',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第一单元（识字）',
          title: '书写提示',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第一单元（识字）',
          title: '咏鹅（日积月累）',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第一单元（识字）',
          title: '小兔子乖乖（和大人一起读）',
        ),
      ],
    ),

    // 第二单元（汉语拼音）
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第二单元（拼音）',
      title: 'a o e',
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第二单元（拼音）',
      title: 'i u ü',
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第二单元（拼音）',
      title: 'b p m f',
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第二单元（拼音）',
      title: 'd t n l',
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第二单元（拼音）',
      title: '小兔子乖乖（和大人一起读）',
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第二单元（拼音）',
      title: '语文园地二',
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第二单元（拼音）',
          title: '识字加油站',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第二单元（拼音）',
          title: '用拼音',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第二单元（拼音）',
          title: '剪窗花（和大人一起读）',
        ),
      ],
    ),

    // 第三单元（汉语拼音）
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第三单元（拼音）',
      title: 'g k h',
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第三单元（拼音）',
      title: 'j q x',
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第三单元（拼音）',
      title: 'z c s',
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第三单元（拼音）',
      title: 'zh ch sh r',
    ),
    PrimaryChineseLesson(grade: 1, term: '上册', unit: '第三单元（拼音）', title: 'y w'),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第三单元（拼音）',
      title: '剪窗花（和大人一起读）',
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第三单元（拼音）',
      title: '语文园地三',
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第三单元（拼音）',
          title: '用拼音',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第三单元（拼音）',
          title: '字词句运用',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第三单元（拼音）',
          title: '小鸟念书（和大人一起读）',
        ),
      ],
    ),

    // 第四单元（课文）
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第四单元（拼音）',
      title: 'ai ei ui',
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第四单元（拼音）',
      title: 'ao ou iu',
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第四单元（拼音）',
      title: 'ie üe er',
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第四单元（拼音）',
      title: 'an en in un ün',
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第四单元（拼音）',
      title: 'ang eng ing ong',
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第四单元（拼音）',
      title: '小鸟念书（和大人一起读）',
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第四单元（拼音）',
      title: '语文园地四',
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第四单元（拼音）',
          title: '识字加油站',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第四单元（拼音）',
          title: '字词句运用',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第四单元（拼音）',
          title: '惜时名言（日积月累）',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第四单元（拼音）',
          title: '小松鼠找花生（和大人一起读）',
        ),
      ],
    ),

    // 第五单元（识字）
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第五单元（阅读）',
      title: '秋天',
      // 字词取课本三张表原文（识字表/写字表/词语表，2024新课标）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第五单元（阅读）',
          title: '会认字\n秋 气 了 树 叶 片 大 飞 会 个',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第五单元（阅读）',
          title: '会写字\n了 子 人 大',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第五单元（阅读）',
          title: '词语\n秋天 树叶 一片片 飞来飞去',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第五单元（阅读）',
      title: '江南',
      // 字词取课本三张表原文（识字表/写字表/词语表，2024新课标）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第五单元（阅读）',
          title: '会认字\n江 南 可 莲 鱼 东 西 北',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第五单元（阅读）',
          title: '会写字\n可 东 西',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第五单元（阅读）',
          title: '词语\n江南 莲叶 鱼儿 东西',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第五单元（阅读）',
      title: '雪地里的小画家',
      // 字词取课本三张表原文（识字表/写字表/词语表，2024新课标）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第五单元（阅读）',
          title: '会认字\n群 竹 牙 用 几 步 为 参 加 洞 着',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第五单元（阅读）',
          title: '会写字\n竹 牙 用 几',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第五单元（阅读）',
          title: '词语\n雪地 小画家 竹叶 青蛙 睡觉',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第五单元（阅读）',
      title: '四季',
      // 字词取课本三张表原文（识字表/写字表/词语表，2024新课标）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第五单元（阅读）',
          title: '会认字\n说 春 青 蛙 夏 弯 地 就 冬',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第五单元（阅读）',
          title: '会写字\n四 是 天 大',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第五单元（阅读）',
          title: '词语\n四季 春天 青蛙 雪人',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第五单元（阅读）',
      title: '小松鼠找花生（和大人一起读）',
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第五单元（阅读）',
      title: '语文园地五',
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第五单元（阅读）',
          title: '识字加油站',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第五单元（阅读）',
          title: '字词句运用',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第五单元（阅读）',
          title: '书写提示',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第五单元（阅读）',
          title: '悯农·其二（日积月累）',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第五单元（阅读）',
          title: '拔萝卜（和大人一起读）',
        ),
      ],
    ),

    // 第六单元（课文）
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第六单元（识字）',
      title: '对韵歌',
      // 字词取课本三张表原文（识字表/写字表/词语表，2024新课标）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第六单元（识字）',
          title: '会认字\n对 云 雨 风 花 鸟 虫',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第六单元（识字）',
          title: '会写字\n对 云 雨 风',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第六单元（识字）',
          title: '词语\n风雨 风花 鸟虫 山清水秀',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第六单元（识字）',
      title: '日月明',
      // 字词取课本三张表原文（识字表/写字表/词语表，2024新课标）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第六单元（识字）',
          title: '会认字\n明 力 尘 从 众 双 木 林 森 条',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第六单元（识字）',
          title: '会写字\n木 林 土 力',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第六单元（识字）',
          title: '词语\n日月明 众人 森林 一条',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第六单元（识字）',
      title: '小书包',
      // 字词取课本三张表原文（识字表/写字表/词语表，2024新课标）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第六单元（识字）',
          title: '会认字\n书 包 尺 作 业 本 笔 刀 课 早 校',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第六单元（识字）',
          title: '会写字\n书 本 尺 刀',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第六单元（识字）',
          title: '词语\n书包 尺子 作业本 铅笔 小刀',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第六单元（识字）',
      title: '升国旗',
      // 字词取课本三张表原文（识字表/写字表/词语表，2024新课标）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第六单元（识字）',
          title: '会认字\n升 国 旗 中 红 歌 起 么 美 丽 立',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第六单元（识字）',
          title: '会写字\n升 国 旗 中 红',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第六单元（识字）',
          title: '词语\n升国旗 中国 红旗 国歌 多么美丽',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第六单元（识字）',
      title: '拔萝卜（和大人一起读）',
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第六单元（识字）',
      title: '语文园地六',
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第六单元（识字）',
          title: '字词句运用',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第六单元（识字）',
          title: '展示台',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第六单元（识字）',
          title: '古朗月行（日积月累）',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第六单元（识字）',
          title: '谁会飞（和大人一起读）',
        ),
      ],
    ),

    // 第七单元（课文）
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第七单元（阅读）',
      title: '小小的船',
      // 字词取课本三张表原文（识字表/写字表/词语表，2024新课标）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第七单元（阅读）',
          title: '会认字\n船 两 头 看 见 闪 星',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第七单元（阅读）',
          title: '会写字\n月 儿 头 里',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第七单元（阅读）',
          title: '词语\n小小的船 两头 看见 闪闪的星星',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第七单元（阅读）',
      title: '影子',
      // 字词取课本三张表原文（识字表/写字表/词语表，2024新课标）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第七单元（阅读）',
          title: '会认字\n影 前 后 黑 狗 左 右 它 好 朋 友',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第七单元（阅读）',
          title: '会写字\n后 好 左 右',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第七单元（阅读）',
          title: '词语\n影子 前后 左右 好朋友 黑狗',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第七单元（阅读）',
      title: '两件宝',
      // 字词取课本三张表原文（识字表/写字表/词语表，2024新课标）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第七单元（阅读）',
          title: '会认字\n两 件 宝 双 手 大 脑',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第七单元（阅读）',
          title: '会写字\n两 宝 双 手',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第七单元（阅读）',
          title: '词语\n两件宝 双手 大脑 会做事',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第七单元（阅读）',
      title: '谁会飞（和大人一起读）',
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第七单元（阅读）',
      title: '语文园地七',
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第七单元（阅读）',
          title: '识字加油站',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第七单元（阅读）',
          title: '字词句运用',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第七单元（阅读）',
          title: '书写提示',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第七单元（阅读）',
          title: '处世名言（日积月累）',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第七单元（阅读）',
          title: '猴子捞月亮（和大人一起读）',
        ),
      ],
    ),

    // 第八单元（课文）
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第八单元（阅读）',
      title: '比尾巴',
      // 字词取课本三张表原文（识字表/写字表/词语表，2024新课标）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第八单元（阅读）',
          title: '会认字\n比 尾 巴 谁 长 短 把 伞 兔 公 最',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第八单元（阅读）',
          title: '会写字\n比 巴 把 伞',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第八单元（阅读）',
          title: '词语\n比尾巴 长短 伞 兔子 公鸡',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第八单元（阅读）',
      title: '乌鸦喝水',
      // 字词取课本三张表原文（识字表/写字表/词语表，2024新课标）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第八单元（阅读）',
          title: '会认字\n乌 鸦 处 找 办 法 许 放 进 高 住 玩 吧',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第八单元（阅读）',
          title: '会写字\n只 石 多 出 见',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第八单元（阅读）',
          title: '词语\n乌鸦 喝水 办法 石子 放进',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第八单元（阅读）',
      title: '雨点儿',
      // 字词取课本三张表原文（识字表/写字表/词语表，2024新课标）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第八单元（阅读）',
          title: '会认字\n数 彩 半 空 问 到 方 没 更 出 长',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第八单元（阅读）',
          title: '会写字\n问 有 半 从 你',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第八单元（阅读）',
          title: '词语\n雨点儿 半空 地方 没有 更长',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第八单元（阅读）',
      title: '猴子捞月亮（和大人一起读）',
    ),
    PrimaryChineseLesson(
      grade: 1,
      term: '上册',
      unit: '第八单元（阅读）',
      title: '语文园地八',
      subLessons: [
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第八单元（阅读）',
          title: '识字加油站',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第八单元（阅读）',
          title: '字词句运用',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第八单元（阅读）',
          title: '书写提示',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第八单元（阅读）',
          title: '风（日积月累）',
        ),
        PrimaryChineseLesson(
          grade: 1,
          term: '上册',
          unit: '第八单元（阅读）',
          title: '春节童谣（和大人一起读）',
        ),
      ],
    ),

    // ==============================================================
    // 一年级下册 (统编版官方完整目次)
    // ==============================================================
    // 第一单元（识字）
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第一单元（识字）', title: '春夏秋冬', lessonId: 'g1b-chunxiaqiudong-b-dual'),
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第一单元（识字）', title: '姓氏歌'),
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第一单元（识字）', title: '小青蛙'),
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第一单元（识字）', title: '猜字谜'),

    // 第二单元
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第二单元', title: '热爱中国共产党'),
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第二单元', title: '吃水不忘挖井人'),
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第二单元', title: '我多想去看看'),

    // 第三单元
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第三单元', title: '小公鸡和小鸭子'),
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第三单元', title: '树和喜鹊'),
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第三单元', title: '怎么都快乐'),

    // 第四单元
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第四单元', title: '静夜思'),
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第四单元', title: '夜色'),
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第四单元', title: '端午粽'),

    // 第五单元（识字）
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第五单元（识字）', title: '动物儿歌'),
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第五单元（识字）', title: '古对今'),
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第五单元（识字）', title: '操场上'),
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第五单元（识字）', title: '人之初'),

    // 第六单元
    PrimaryChineseLesson(
      grade: 1,
      term: '下册',
      unit: '第六单元',
      title: '古诗二首（池上·小池）',
    ),
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第六单元', title: '浪花'),
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第六单元', title: '荷叶圆圆'),
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第六单元', title: '要下雨了'),

    // 第七单元
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第七单元', title: '文具的家'),
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第七单元', title: '一分钟'),
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第七单元', title: '动物王国开大会'),
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第七单元', title: '小猴子下山'),

    // 第八单元
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第八单元', title: '棉花姑娘'),
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第八单元', title: '咕咚', lessonId: 'g1b-gudong-b-dual'),
    PrimaryChineseLesson(grade: 1, term: '下册', unit: '第八单元', title: '小壁虎借尾巴'),

    // ==============================================================
    // 🔒【数据已锁定·严禁擅自修改/回退】二年级上册 (统编版官方完整目次·每单元园地标准四栏目·名师原声双模全量激活)
    // 经用户与多轮真机审核已全部就绪（含《葡萄沟》《黄山奇石》《我要的是葫芦》等课题与标点规范），后续 Agent 严禁改坏或覆盖！
    // ==============================================================
    // 第一单元（课文）
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第一单元',
      title: '课文1 小蝌蚪找妈妈',
      lessonId: 'xiaokedou-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第一单元',
          title: '会认字\n蝌 蚪 脑 袋 灰 甩 活 腿 教 迎 嘴 龟 披 蹲 肚 鼓',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第一单元',
          title: '会写字\n两 条 哪 宽 那 短 孩 成',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第一单元',
          title: '词语\n妈妈 他们 看见 我们 哪里 那边 雪白 过去 孩子 什么',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第一单元',
      title: '课文2 我是什么',
      lessonId: 'woshishenme-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第一单元',
          title: '会认字\n汽 越 温 滴 奔 海 洋 发 坏 没 庄 稼 屋 带 灾 种 管',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第一单元',
          title: '会写字\n升 连 起 海 洋 许 作 法',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第一单元',
          title: '词语\n太阳 天空 一起 冬天 花朵 池子 江河 海洋 许多 田地 工作 办法 你们',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第一单元',
      title: '课文3 植物妈妈有办法',
      lessonId: 'zhiwumama-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第一单元',
          title: '会认字\n植 如 为 脚 旅 准 备 送 纷 挂 挺 钻 底 炸 离 粗 得',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第一单元',
          title: '会写字\n如 果 已 经 别 轻 发 胆 肚 识',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第一单元',
          title: '词语\n如果 已经 告别 四海为家 自己 出发 动物 胆子 肚子 那里 知识',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第一单元',
      title: '语文园地一',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第一单元',
          title: '识字加油站',
          lessonId: 'yuandi1-shizi-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第一单元',
          title: '字词句运用',
          lessonId: 'yuandi1-zici-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第一单元',
          title: '梅花（日积月累）',
          lessonId: 'meihua-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第一单元',
          title: '企鹅寄冰（我爱阅读）',
          lessonId: 'qiejibing-b-dual',
          isDualMode: true,
        ),        // 语文园地的字取课本识字表/写字表同名行（无词语表条目）；既有 4 板块保持不动；无 lessonId
],
    ),

    // 第二单元（识字）
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第二单元',
      title: '识字1 场景歌',
      lessonId: 'changjingge-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第二单元',
          title: '会认字\n帆 港 湾 塘 稻 行 垂 园 溪 丛 翠 群 队 铜 号',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第二单元',
          title: '会写字\n处 块 座 园 群 队 领',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第二单元',
          title: '词语\n花园 飞鸟 红领巾 欢笑',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第二单元',
      title: '识字2 树之歌',
      lessonId: 'shuzhige-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第二单元',
          title: '会认字\n榕 壮 梧 桐 掌 枫 松 柏 桦 守 银 杏 杉 化 桂',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第二单元',
          title: '会写字\n树 之 杨 松 柏 化 金 桂',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第二单元',
          title: '词语\n杨树 树叶 松柏 化石 开花',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第二单元',
      title: '识字3 拍手歌',
      lessonId: 'paishouge-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第二单元',
          title: '会认字\n世 界 孔 雀 锦 雄 鹰 翔 雁 深 猛 灵 休 猫',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第二单元',
          title: '会写字\n拍 世 界 彩 丛 休 朋 友 保 护',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第二单元',
          title: '词语\n拍手 世界 云彩 丛林 竹林 朋友 保护',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第二单元',
      title: '识字4 田家四季歌',
      lessonId: 'tianjiasijige-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第二单元',
          title: '会认字\n季 蝴 蝶 麦 嫩 肥 农 勤 归 戴 场 谷 虽 辛 苦 制',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第二单元',
          title: '会写字\n季 肥 农 事 谷 体 辛 苦 初 年',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第二单元',
          title: '词语\n四季 春风 农事 月光 身体 辛苦 心里 大家',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第二单元',
      title: '语文园地二',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第二单元',
          title: '识字加油站',
          lessonId: 'yuandi2-shizi-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第二单元',
          title: '字词句运用（部首查字·示范朗读录制中）',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第二单元',
          title: '数九歌（日积月累）',
          lessonId: 'shujiuge-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第二单元',
          title: '十二月花名歌（我爱阅读）',
          lessonId: 'shierfanamingge-b-dual',
          isDualMode: true,
        ),        // 语文园地的字取课本识字表/写字表同名行（无词语表条目）；既有 4 板块保持不动；无 lessonId
],
    ),

    // 第三单元（课文）
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第三单元',
      title: '课文4 彩虹',
      lessonId: 'caihong-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第三单元',
          title: '会认字\n虹 浇 壶 提 洒 挑 镜 拿 系 荡 裙',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第三单元',
          title: '会写字\n丽 提 吗 圆 哥 秋 挂 啊',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第三单元',
          title: '词语\n天上 美丽 爸爸 下来 不用 高兴 哥哥 秋千 彩云',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第三单元',
      title: '课文5 去外婆家',
      lessonId: 'quwaipojia-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第三单元',
          title: '会认字\n婆 候 趣 舅 或 留 份 喂 逃 曲 者 服 扑 鼻',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第三单元',
          title: '会写字\n宝 玩 活 些 总 给 诉 曲 名 香',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第三单元',
          title: '词语\n宝贝 干活 回来 一些 天气 欢快 它们 告诉 名字 出门',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第三单元',
      title: '课文6 数星星的孩子',
      lessonId: 'shuxingxing-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第三单元',
          title: '会认字\n珍 碧 靠 仰 颗 距 变 祖 勺 绕 转 楚 汉 刻 研',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第三单元',
          title: '会写字\n数 晚 奶 您 爷 很 变 勺 张 汉',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第三单元',
          title: '词语\n星星 晚上 无数 奶奶 中间 总是 爷爷 北边 勺子 转动 这个 后来',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第三单元',
      title: '语文园地三',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第三单元',
          title: '识字加油站',
          lessonId: 'yuandi3-shizi-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第三单元',
          title: '字词句运用',
          lessonId: 'yuandi3-zici-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第三单元',
          title: '小儿垂钓（日积月累）',
          lessonId: 'xiaoerchuidiao-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第三单元',
          title: '王二小（我爱阅读）',
          lessonId: 'wangerxiao-b-dual',
          isDualMode: true,
        ),        // 语文园地的字取课本识字表/写字表同名行（无词语表条目）；既有 4 板块保持不动；无 lessonId
],
    ),

    // 第四单元（课文）
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第四单元',
      title: '课文7 古诗二首（登鹳雀楼·望庐山瀑布）',
      lessonId: 'gushi2-b-dual',
      isDualMode: true,
      // 字词为教材三张表原文（识字表/写字表/课后读一读，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第四单元',
          title: '会认字\n登 唐 依 尽 欲 穷 层 瀑 布 炉 紫 烟 遥',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第四单元',
          title: '会写字\n依 尽 穷 层 照 炉 烟 川 直 银',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第四单元',
          title: '词语\n穷尽 山穷水尽 层叠 层林叠翠 烟云 烟消云散 山川 名山大川',
        ),


      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第四单元',
      title: '课文8 黄山奇石',
      lessonId: 'huangshanqishi-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第四单元',
          title: '会认字\n闻 景 区 省 秀 神 仙 盘 指 巨 伸 都 著 抢 状 岩',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第四单元',
          title: '会写字\n仙 顶 巨 位 闪 狗 形 状',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第四单元',
          title: '词语\n那些 山顶 山头 云海 仙人 前方 仙女',
        ),


      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第四单元',
      title: '课文9 日月潭',
      lessonId: 'riyuantan-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第四单元',
          title: '会认字\n潭 茂 盛 胜 央 岛 隐 约 倒 映 整 童 吸 引 客',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第四单元',
          title: '会写字\n湖 区 胜 岛 弯 现 就 外',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第四单元',
          title: '词语\n山区 群山 树木 灯光 中午 眼前 细雨 风光 中外',
        ),


      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第四单元',
      title: '课文10 葡萄沟',
      lessonId: 'putaogou-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第四单元',
          title: '会认字\n葡 萄 沟 坡 密 枝 淡 好 族 够 收 市 干 钉 分 颜 味',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第四单元',
          title: '会写字\n份 枝 客 城 市 孔 钉 味',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第四单元',
          title: '词语\n地方 水果 月份 枝叶 五光十色 好客 老乡 有的 城市 空气 水分 这里 味道 有名',
        ),


      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第四单元',
      title: '语文园地四',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第四单元',
          title: '识字加油站（车票识字·示范朗读录制中）',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第四单元',
          title: '字词句运用',
          lessonId: 'yuandi4-zici-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第四单元',
          title: '风景对联（日积月累）',
          lessonId: 'yuandi4-mingju-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第四单元',
          title: '画家乡（我爱阅读）',
          lessonId: 'huajiaxiang-b-dual',
          isDualMode: true,
        ),        // 语文园地的字取课本识字表/写字表同名行（无词语表条目）；既有 4 板块保持不动；无 lessonId
],
    ),

    // 第五单元（课文）
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第五单元',
      title: '课文11 坐井观天',
      lessonId: 'zuojingguantian-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第五单元',
          title: '会认字\n观 沿 渴 话 弄 错 际 抬 信',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第五单元',
          title: '会写字\n观 呀 答 话 抬 能 信',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第五单元',
          title: '词语\n坐井观天 哪儿 回答 大话 不过 那么 抬头',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第五单元',
      title: '课文12 寒号鸟',
      lessonId: 'hanhaoniao-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第五单元',
          title: '会认字\n号 当 鹊 寻 枯 却 劝 刮 死 将 且 狂 冷 重 复 哀 唤',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第五单元',
          title: '会写字\n阵 做 冻 第 像 冷 冰 亮',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第五单元',
          title: '词语\n当作 前面 面对面 出去 过冬 知道 赶快 正好 明天 清早 好像 一样 天亮 出来',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第五单元',
      title: '课文13 我要的是葫芦',
      lessonId: 'hulu-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第五单元',
          title: '会认字\n葫 芦 谢 以 盯 赛 怪 慢',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第五单元',
          title: '会写字\n种 棵 以 次 想 邻 居 吧 奇 怪',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第五单元',
          title: '词语\n从前 以后 多么 那个 叶子 虫子 自言自语 邻居 奇怪',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第五单元',
      title: '语文园地五',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第五单元',
          title: '识字加油站',
          lessonId: 'yuandi5-shizi-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第五单元',
          title: '字词句运用',
          lessonId: 'yuandi5-zici-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第五单元',
          title: '勤学名言（日积月累）',
          lessonId: 'yuandi5-mingyan-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第五单元',
          title: '刻舟求剑（我爱阅读）',
          lessonId: 'kezhouqiujian-b-dual',
          isDualMode: true,
        ),        // 语文园地的字取课本识字表/写字表同名行（无词语表条目）；既有 4 板块保持不动；无 lessonId
],
    ),

    // 第六单元（课文）
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第六单元',
      title: '课文14 八角楼上',
      lessonId: 'bajiaoloushang-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第六单元',
          title: '会认字\n楼 艰 斗 代 临 腊 军 薄 章 握 凝 觉 油 辉 革 命 利',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第六单元',
          title: '会写字\n楼 代 穿 视 利 路',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第六单元',
          title: '词语\n年代 明亮 星星之火 中国 胜利 道路',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第六单元',
      title: '课文15 朱德的扁担',
      lessonId: 'zhudedebiandan-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第六单元',
          title: '会认字\n朱 德 扁 担 同 志 伍 敌 根 据 抽 陡 鞋 疼 敬',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第六单元',
          title: '会写字\n同 志 军 敌 常 非 每 战 士 戴',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第六单元',
          title: '词语\n同志 红军 敌人 生产 常常 来回 非常 战士 一块儿 白天',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第六单元',
      title: '课文16 难忘的泼水节',
      lessonId: 'nanwangdeposhuijie-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第六单元',
          title: '会认字\n泼 民 度 特 周 恩 敲 铺 龙 串 容 踩 始 盛 碗 祝 寿',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第六单元',
          title: '会写字\n难 忘 民 因 理 串 裤 令',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第六单元',
          title: '词语\n难忘 火红 人民 因为 总理 人们 四面八方 为了 人群 欢乐 开心',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第六单元',
      title: '课文17 刘胡兰',
      lessonId: 'liuhulan-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第六单元',
          title: '会认字\n刘 兰 派 由 于 卖 员 捕 买 似 踏 烈 荣 岁 题',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第六单元',
          title: '会写字\n反 村 由 于 员 被 声 岁 消 息',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第六单元',
          title: '词语\n由于 年轻 共产党员 共产党 现在 一点儿 消息',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第六单元',
      title: '语文园地六',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第六单元',
          title: '识字加油站',
          lessonId: 'yuandi6-shizi-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第六单元',
          title: '字词句运用',
          lessonId: 'yuandi6-zici-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第六单元',
          title: '立志名言（日积月累）',
          lessonId: 'yuandi6-mingju-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第六单元',
          title: '大禹治水（我爱阅读）',
          lessonId: 'dayuzhishui-b-dual',
          isDualMode: true,
        ),        // 语文园地的字取课本识字表/写字表同名行（无词语表条目）；既有 4 板块保持不动；无 lessonId
],
    ),

    // 第七单元（课文）
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第七单元',
      title: '课文18 古诗二首（江雪·敕勒歌）',
      lessonId: 'gushiershou-2-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第七单元',
          title: '会认字\n绝 径 踪 灭 舟 钓 似 庐 笼 盖 苍 茫',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第七单元',
          title: '会写字\n绝 灭 舟 独 阴 似 野 低',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第七单元',
      title: '课文19 雾在哪里',
      lessonId: 'wuzainali-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第七单元',
          title: '会认字\n论 暗 岸 街 梁 甚 至 切 躲 该 悠 闲 散 失',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第七单元',
          title: '会写字\n论 船 猫 切 该 散 步 失',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第七单元',
          title: '词语\n于是 无论 船只 同时 行人 一切 上空 看来 不久 路上 出现 散步 消失',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第七单元',
      title: '课文20 雪孩子',
      lessonId: 'xuehaizi-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第七单元',
          title: '会认字\n堆 累 添 柴 烧 旺 闭 哎 旁 冲 哇 终 浑 淋 晒',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第七单元',
          title: '会写字\n要 伙 伴 歌 得 闭 忙 谁 汽',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第七单元',
          title: '词语\n空地 伙伴 唱歌 回家 一会儿 着火 火星 一边 连忙 树林 水汽 白云',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第七单元',
      title: '语文园地七',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第七单元',
          title: '识字加油站',
          lessonId: 'yuandi7-shizi-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第七单元',
          title: '字词句运用',
          lessonId: 'yuandi7-zici-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第七单元',
          title: '夜宿山寺（日积月累）',
          lessonId: 'yesushansi-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第七单元',
          title: '分不清是鸭还是霞（我爱阅读）',
          lessonId: 'fenbuqingshiyahaishixia-b-dual',
          isDualMode: true,
        ),        // 语文园地的字取课本识字表/写字表同名行（无词语表条目）；既有 4 板块保持不动；无 lessonId
],
    ),

    // 第八单元（课文）
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第八单元',
      title: '课文21 称赞',
      lessonId: 'chengzan-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第八单元',
          title: '会认字\n称 赞 刺 猬 板 凳 但 极 傍 苹 泄 接 除 疲 劳',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第八单元',
          title: '会写字\n拿 仔 极 送 椅 怎 拉 收 接',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第八单元',
          title: '词语\n果子 木工 身边 仔细 能干 椅子 怎么 自信 从来 这么',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第八单元',
      title: '课文22 纸船和风筝',
      lessonId: 'zhichuanhefengzheng-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第八单元',
          title: '会认字\n筝 鼠 折 漂 扎 乘 抓 线 莓 俩 架 受 愿 朝 取',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第八单元',
          title: '会写字\n纸 抓 线 吵 但 受 句 哭',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第八单元',
          title: '词语\n上面 快乐 可是 难过 但是 和好',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第八单元',
      title: '课文23 快乐的小河',
      lessonId: 'kuailexiaohe-b-dual',
      isDualMode: true,
      // 字词取课本三张表原文（识字表/写字表/词语表，2025秋统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第八单元',
          title: '会认字\n撞 怨 软 呜 慈 祥 量 跌 摔 擦 咱 推 驶 坚 硬 冲',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第八单元',
          title: '会写字\n游 戏 爱 呢 跳 咱',
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第八单元',
          title: '词语\n眼泪 水花 青草 游戏 只有 可爱 可以 多少 咱们 田野 大地 远方',
        ),

      ],
    ),
    PrimaryChineseLesson(
      grade: 2,
      term: '上册',
      unit: '第八单元',
      title: '语文园地八',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第八单元',
          title: '识字加油站',
          lessonId: 'yuandi8-shizi-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第八单元',
          title: '字词句运用',
          lessonId: 'yuandi8-zici-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第八单元',
          title: '处世名言（日积月累）',
          lessonId: 'yuandi8-chengyu-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 2,
          term: '上册',
          unit: '第八单元',
          title: '狐假虎威（我爱阅读）',
          lessonId: 'hujiahuwei-b-dual',
          isDualMode: true,
        ),        // 语文园地的字取课本识字表/写字表同名行（无词语表条目）；既有 4 板块保持不动；无 lessonId
],
    ),

    // ==============================================================
    // 二年级下册 (统编版官方完整目次)
    // ==============================================================
    // 第一单元
    PrimaryChineseLesson(
      grade: 2,
      term: '下册',
      unit: '第一单元',
      title: '古诗二首（村居·咏柳）',
    ),
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第一单元', title: '找春天'),
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第一单元', title: '开满鲜花的小路'),
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第一单元', title: '邓小平爷爷植树'),

    // 第二单元
    PrimaryChineseLesson(
      grade: 2,
      term: '下册',
      unit: '第二单元',
      title: '雷锋叔叔，你在哪里',
    ),
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第二单元', title: '千人糕'),
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第二单元', title: '一匹出色的马'),

    // 第三单元（识字）
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第三单元（识字）', title: '神州谣'),
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第三单元（识字）', title: '传统节日'),
    PrimaryChineseLesson(
      grade: 2,
      term: '下册',
      unit: '第三单元（识字）',
      title: '“贝”的故事',
    ),
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第三单元（识字）', title: '中国美食'),

    // 第四单元
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第四单元', title: '彩色的梦'),
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第四单元', title: '枫树上的喜鹊'),
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第四单元', title: '沙滩上的童话'),
    PrimaryChineseLesson(
      grade: 2,
      term: '下册',
      unit: '第四单元',
      title: '我不是最弱小的',
      // 2026-10-15 由单入口制课器首次产出：pipeline/build_course.py
      // 教材原文为文本真源，ASR 只出时间轴；卡口 PASS（初读 60 行 / 熟读 27 行）
      lessonId: 'g2x-wozuixiaode-b-dual',
      isDualMode: true,
    ),

    // 第五单元
    PrimaryChineseLesson(
      grade: 2,
      term: '下册',
      unit: '第五单元',
      title: '寓言二则（亡羊补牢·揠苗助长）',
    ),
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第五单元', title: '画杨桃'),
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第五单元', title: '小马过河'),

    // 第六单元
    PrimaryChineseLesson(
      grade: 2,
      term: '下册',
      unit: '第六单元',
      title: '古诗二首（晓出净慈寺送林子方·绝句）',
    ),
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第六单元', title: '雷雨'),
    PrimaryChineseLesson(
      grade: 2,
      term: '下册',
      unit: '第六单元',
      title: '要是你在野外迷了路',
    ),
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第六单元', title: '太空生活趣事多'),

    // 第七单元
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第七单元', title: '大象的耳朵'),
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第七单元', title: '蜘蛛开店'),
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第七单元', title: '青蛙卖泥塘'),
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第七单元', title: '小毛虫'),

    // 第八单元
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第八单元', title: '羿射九日'),
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第八单元', title: '黄帝的传说'),
    PrimaryChineseLesson(grade: 2, term: '下册', unit: '第八单元', title: '大禹治水'),

    // ==============================================================
    // 三年级上册 (统编版官方完整目次)
    // ==============================================================
    // 第一单元
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第一单元',
      title: '大青树下的小学',
      lessonId: 'daqingshu-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第一单元',
          title: '会认字\n绒 汉 艳 扮 扬 摔 跤 凤 墙',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第一单元',
          title: '会写字\n坡 球 汉 招 钟 读 音 粗 壮 洁 校',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第一单元',
          title: '词语\n枝干 学校 招引 洁白 粗壮 山坡 声音 热闹 飘扬 古老 课文',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第一单元',
      title: '花的学校',
      lessonId: 'huadexuexiao-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第一单元',
          title: '会认字\n轰 荒 笛 罚 假',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第一单元',
          title: '会写字\n轰 湿 润 笛 狂 功 罚 互 急 扬 动',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第一单元',
          title: '词语\n放学 湿润 阵雨 风笛 老师 急急忙忙 狂欢 轰响 觉得 功课',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第一单元',
      title: '不懂就要问',
      lessonId: 'budongjiouwen-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第一单元',
          title: '会认字\n孙 诵 例 圈 遍 糊 涂 戒 厉 挨 楚',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第一单元',
          title: '会写字\n庭',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第一单元',
      title: '语文园地一',
      lessonId: 'g3a-yuandi1-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第一单元',
          title: '词句段运用',
          lessonId: 'g3a-yuandi1-zici-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第一单元',
          title: '所见（日积月累）',
          lessonId: 'g3a-yuandi1-suojian-b-dual',
          isDualMode: true,
        ),
      ],
    ),

    // 第二单元
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第二单元',
      title: '古诗三首（山行·望洞庭·夜书所见）',
      lessonId: 'gushi3-1-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第二单元',
          title: '会认字\n庭 未 磨 螺 斜 萧 挑 促',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第二单元',
          title: '会写字\n相 未 径 斜 爱 霜 挑 落 业 朗 珠 年',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第二单元',
      title: '铺满金色巴掌的水泥道',
      lessonId: 'jinsebazhang-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第二单元',
          title: '会认字\n粘 印 凌 增 添 棕 靴',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第二单元',
          title: '会写字\n印 案 列 规 则 凌 乱 双 凉 柔 枚',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第二单元',
          title: '词语\n秋风 迟到 亮晶晶 规则 尽头 明朗 排列 落叶 闪闪发光 图案 凌乱 放晴 歌唱 地面',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第二单元',
      title: '秋天的雨',
      lessonId: 'qiutiandeyu-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第二单元',
          title: '会认字\n钥 匙 枚 爽 频 梨 萝 勾 喇 叭',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第二单元',
          title: '会写字\n票 爽 给 争 频 勾 诉 挖 丰 乌 板',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第二单元',
          title: '词语\n果树 频频 丰收 菊花 炎热 枫树 清凉 气味 香甜 凉爽 松果 邮票 秋天 仙子',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第二单元',
      title: '听听，秋的声音',
      lessonId: 'qiudeshengyin-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第二单元',
          title: '会认字\n抖 振 韵 掠 吟 辽 阔',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第二单元',
          title: '会写字\n备 等',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第二单元',
      title: '语文园地二',
      lessonId: 'g3a-yuandi2-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(grade: 3, term: '上册', unit: '第二单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第二单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第二单元',
          title: '秋天的成语（日积月累）',
        ),
      ],
    ),

    // 第三单元
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第三单元',
      title: '总也倒不了的老屋',
      lessonId: 'laowu-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第三单元',
          title: '会认字\n眯 哦 喵 孵 叽 缝 偶 尔',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第三单元',
          title: '会写字\n载 呀 钻 肚 饿 宝 晒 耀',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第三单元',
          title: '词语\n准备 暴风雨 母鸡 屋子 意思 漂亮 门板 因此 旁边 吃力 低头 注意 安心 再见',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第三单元',
      title: '犟龟',
      lessonId: 'jinggu-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第三单元',
          title: '会认字\n陶 谈 婚 庆 典 史 震 倍 坚 持 暂',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第三单元',
          title: '会写字\n玩 胜 轴 阁 旋 妥 陪',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第三单元',
      title: '小狗学叫',
      lessonId: 'xiaogouxuejiao-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第三单元',
          title: '会认字\n吗 惹 讨 厌 访 忍 默 中 砰 弹 疯 汪 搞',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第三单元',
          title: '会写字\n厘 旅 另 级',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第三单元',
      title: '语文园地三',
      lessonId: 'g3a-yuandi3-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(grade: 3, term: '上册', unit: '第三单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第三单元',
          title: '识字加油站',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第三单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第三单元',
          title: '处世名言（日积月累）',
        ),
      ],
    ),

    // 第四单元
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第四单元',
      title: '宝葫芦的秘密（节选）',
      lessonId: 'baohulu-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第四单元',
          title: '会认字\n普 矩 宝 秘密 葫芦 绍 述 妖 规 劈',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第四单元',
          title: '会写字\n命 拼 经 伟 齿 胃 管 刚',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第四单元',
          title: '词语\n神仙 要是 科学 同学 衣服 指甲 得到 让步 所以 最好 条件 可怜 声明 普通',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第四单元',
      title: '在牛肚子里旅行',
      lessonId: 'niuduzi-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第四单元',
          title: '会认字\n咱 偷 答 应 骨 碌 齿 嚼 吞 胃 贮 悲 咽',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第四单元',
          title: '会写字\n乎 咬 蚂 蚁 武 宣 抢 担 纪 虑 钉',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第四单元',
          title: '词语\n救命 肚皮 当然 刚才 答应 要好 来得及 牙齿 知觉 尾巴 旅行 光亮 做梦 消化 食物 大吃一惊',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第四单元',
      title: '一块奶酪',
      lessonId: 'nailao-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第四单元',
          title: '会认字\n伍 宣 处 恐 诱 毅 纪 渣 惜 犯 禁 聚',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第四单元',
          title: '会写字\n犯 禁 令 赤 旧 怜 卷 政 钱 抽',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第四单元',
      title: '语文园地四',
      lessonId: 'g3a-yuandi4-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(grade: 3, term: '上册', unit: '第四单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第四单元',
          title: '识字加油站',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第四单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第四单元',
          title: '团结谚语（日积月累）',
        ),
      ],
    ),

    // 第五单元（习作单元）
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第五单元',
      title: '搭船的鸟',
      lessonId: 'dachuan-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第五单元',
          title: '会认字\n舱 啦 橹 鹦 鹉 衔',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第五单元',
          title: '会写字\n望 富 声 奶 申 介 绍 宗 祖 止 乏 占 搭',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第五单元',
          title: '词语\n羽毛 静悄悄 外祖父 翠绿 船夫 捕鱼 翠鸟 母亲',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第五单元',
      title: '金色的草地',
      lessonId: 'jinsecaodi-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第五单元',
          title: '会认字\n蒲 英 耍 欠 拢',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第五单元',
          title: '会写字\n沙 披 摇 羽 翠 静 悄 吞 捕 葡 英 胜 耍',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第五单元',
          title: '词语\n玩耍 观察 盛开 喜爱 合拢 张开 使劲 钓鱼 草地 蒲公英 一本正经',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第五单元',
      title: '习作例文与初试身手',
      subLessons: [
        PrimaryChineseLesson(grade: 3, term: '上册', unit: '第五单元', title: '初试身手'),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第五单元',
          title: '我家的小狗（习作例文）',
          lessonId: 'g3a-u5-xiaogou-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第五单元',
          title: '我爱故乡的杨梅（习作例文）',
          lessonId: 'g3a-u5-yangmei-b-dual',
          isDualMode: true,
        ),
      ],
    ),

    // 第六单元
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第六单元',
      title: '富饶的西沙群岛',
      lessonId: 'xishaqundao-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第六单元',
          title: '会认字\n饶 优 岩 绽 参 武 插 栖 厚 粪 辈',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第六单元',
          title: '会写字\n容 脸 欠 潮 拢 洗 井 优 淡 浅 错 抵',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第六单元',
          title: '词语\n皮球 布满 祖国 岩石 风景 茂密 条纹 成群结队 发展 鹿角 交错 事业 周身 物产 优美 肥料',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第六单元',
      title: '海滨小城',
      lessonId: 'haibinxiaocheng-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第六单元',
          title: '会认字\n滨 胳 臂 睬 载 逢',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第六单元',
          title: '会写字\n岩 鹿 画 刺 冒 密 厚 滨 棕 帆 灰 渔',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第六单元',
          title: '词语\n朝阳 机帆船 银光闪闪 汽笛 出海 街道 渔民 亚热带 海滨 庭院 贝壳 交界 水平线 来来往往 打扫 干净 散发',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第六单元',
      title: '美丽的小兴安岭',
      lessonId: 'xinganling-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第六单元',
          title: '会认字\n兴 融 侧 欣 封 浸 乳 梢 宿 舍 药 膝 眠',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第六单元',
          title: '会写字\n壳 院 亚 透 除 封 严 挡 谈 显 参 材 软',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第六单元',
          title: '词语\n山谷 宝库 各种各样 苍翠 照射 花坛 景色 野兔 药材 捕捉 密密层层 东北 严严实实 显得 起来 视线',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第六单元',
      title: '香港，璀璨的明珠',
      lessonId: 'xianggang-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第六单元',
          title: '会认字\n贸 愧 宴 验 议 赠 幻 溢 洲 澳 角',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第六单元',
          title: '会写字\n',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第六单元',
      title: '语文园地六',
      lessonId: 'g3a-yuandi6-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(grade: 3, term: '上册', unit: '第六单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第六单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第六单元',
          title: '早发白帝城（日积月累）',
        ),
      ],
    ),

    // 第七单元
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第七单元',
      title: '古诗三首（鹿柴·望天门山·饮湖上初晴后雨）',
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第七单元',
          title: '会认字\n返 苔 亦 抹 宜',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第七单元',
          title: '会写字\n刮 捉 库 反 望',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第七单元',
      title: '大自然的声音',
      lessonId: 'dazirandeshengyin-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第七单元',
          title: '会认字\n妙 奏 呢 喃 伟 充 量 击 汇 哩',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第七单元',
          title: '会写字\n断 楚 至 暗 孤 引 议 欲 抹 宜 妙 琴',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第七单元',
          title: '词语\n合奏 充满 歌手 乐器 手风琴 河流 屋顶 威力 水塘 大自然 音乐家 合唱 美妙 温柔 轻快 感受',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第七单元',
      title: '读不完的大书',
      lessonId: 'dubuwanddashu-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第七单元',
          title: '会认字\n麻 旋 序 贞 姿 态 笋 寸 副 奥 秘',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第七单元',
          title: '会写字\n感 充 威 场 汇 鸣 虾 紧 序 紫 姿 态 窄',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第七单元',
          title: '词语\n奥秘 精神 无穷 秋高气爽 井然有序 池塘 鲜美 搬家 千姿百态 昆虫 无尽 游玩 沉思 植物 倒映 万物 画册',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第七单元',
      title: '语文园地七',
      lessonId: 'g3a-yuandi7-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(grade: 3, term: '上册', unit: '第七单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第七单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第七单元',
          title: '采莲曲（日积月累）',
        ),
      ],
    ),

    // 第八单元
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第八单元',
      title: '司马光',
      lessonId: 'simaguang-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第八单元',
          title: '会认字\n司 跌 皆 弃',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第八单元',
          title: '会写字\n梨 侧 奥 秘 螺 蝌 蚪 螃 蟹 鲤 鲫 鲨',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第八单元',
      title: '一定要争气',
      lessonId: 'zhengqi-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第八单元',
          title: '会认字\n浙 县 差 均 资 授 项 剥 卵 膜 励',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第八单元',
          title: '会写字\n丝 登 跌 皆 弃 持 击 之 念 差 考 试',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第八单元',
          title: '词语\n同意 环节 刻苦 留学 生物 考试 成就 地位 再三 落后 努力 值班 难度 学期 难得 国家 兴奋 从事',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第八单元',
      title: '手术台就是阵地',
      lessonId: 'shoushutaizhendi-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第八单元',
          title: '会认字\n棒 恩 大 血 势 瓦 帘 担 迅 速 夺 秒',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第八单元',
          title: '会写字\n均 退 或 努 留 育 度 术 焰 挨 血 仍',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第八单元',
          title: '词语\n争分夺秒 战斗 匆匆 陆续 迅速 转告 血丝 打响 连续 阵地 伤员 赶忙 消灭 手术台 医生',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第八单元',
      title: '一个粗瓷大碗',
      lessonId: 'cucidawan-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第八单元',
          title: '会认字\n陈 联 政 束 缸 还 顿 灶 饥 沾 禁 锅 侦',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第八单元',
          title: '会写字\n曲 盘 迅 速 夺 秒 睁 眨 瞪 丑 怒 眶 呆 睹',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '上册',
      unit: '第八单元',
      title: '语文园地八',
      lessonId: 'g3a-yuandi8-b-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(grade: 3, term: '上册', unit: '第八单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第八单元',
          title: '识字加油站',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第八单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '上册',
          unit: '第八单元',
          title: '仁爱名句（日积月累）',
        ),
      ],
    ),

    // ==============================================================
    // 三年级下册 (统编版官方完整目次)
    // ==============================================================
    // 第一单元
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第一单元',
      title: '古诗三首（绝句·惠崇春江晚景·三衢道中）',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第一单元',
          title: '会认字\n豚 曾',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第一单元',
          title: '会写字\n融 燕 鸳 鸯 惠 崇 芽 梅 泛 减',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第一单元',
      title: '燕子',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第一单元',
          title: '会认字\n伶 俐 旷 横 翼 漾 倦 散 痕',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第一单元',
          title: '会写字\n凑 泼 集 偶 尔 沾 闲 纤 杆',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第一单元',
          title: '词语\n燕子 乌黑 剪刀 活泼 轻风 洒落 赶集 光彩夺目 春光 偶尔 闲散 纤细 电线',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第一单元',
      title: '荷花',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第一单元',
          title: '会认字\n裳 翩 蜻 蜓',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第一单元',
          title: '会写字\n荷 挨 紧 蓬 胀 裂 势 微 记',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第一单元',
          title: '词语\n荷花 公园 清香 赶紧 荷叶 莲蓬 破裂 姿势 画家 本领 了不起 微风 停止',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第一单元',
      title: '昆虫备忘录',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第一单元',
          title: '会认字\n录 琢 敏 款 膜 瞎 益 辆 蚂 斑 褐',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第一单元',
      title: '语文园地一',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第一单元',
          title: '交流平台',
        ),
PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第一单元',
          title: '词句段运用',
        ),
PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第一单元',
          title: '日积月累',
        ),
PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第一单元',
          title: '词语\n匕首 乙方 冗长 军犬 兑换 争执',
        ),
      ],
    ),
    // 第二单元
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第二单元',
      title: '守株待兔',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第二单元',
          title: '会认字\n冀 为',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第二单元',
          title: '会写字\n守 株 待 宋 耕 折 颈 释 其 复',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第二单元',
      title: '会摇尾巴的狼',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第二单元',
          title: '会认字\n模 毫 犹 豫 狡 猾 相',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第二单元',
          title: '会写字\n装 驯 良 善 伸 谢 尘 凶 恶 狠 猎 拾',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第二单元',
          title: '词语\n友情 认识 忠诚 驯良 善良 温和 答谢 花言巧语 着急 相信 尘土 凶恶 恶狠狠 猎人 收拾',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第二单元',
      title: '鹿角和鹿腿',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第二单元',
          title: '会认字\n皱 逼 撒',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第二单元',
          title: '会写字\n渴 喝 匀 称 致 束 配 甩 丧 追 扯 叹 逃',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第二单元',
      title: '池子与河流',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第二单元',
          title: '会认字\n滔 贯 妇 垫 忧 虑 凭 哲 遵 循 逸 尊 衰',
        ),
      ],
    ),
    // 第三单元
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第三单元',
      title: '海底世界',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第三单元',
          title: '会认字\n缩 差 藻 胞 煤 储 属',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第三单元',
          title: '会写字\n官 否 窃 私 汪 危 险 肌 攻 免 费 异 达',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第三单元',
          title: '词语\n宁静 器官 是否 窃窃私语 危险 方法 肌肉 攻击 利用 后退 免费 差异 清楚 奇异',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第三单元',
      title: '石蜂',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第三单元',
          title: '会认字\n概 殊',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第三单元',
          title: '会写字\n验 证 阻 约 括 检 查 迷 误 逆 陌',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第三单元',
          title: '词语\n实验 验证 记号 减少 阻力 大约 包括 检查 至少 迷失 无误 逆风 陌生 景物 能力',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第三单元',
      title: '小虾',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第三单元',
          title: '会认字\n隙 稍 逐 副 钳 翘 搏 捡 较 腹 卵',
        ),
      ],
    ),
    // 第四单元
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第四单元',
      title: '古诗三首（元日·清明·九月九日忆山东兄弟）',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第四单元',
          title: '会写字\n旧 符 牧 妆 纷 魂 借 酒 遥 兄 逢 佳 倍',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第四单元',
      title: '纸的发明',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第四单元',
          title: '会认字\n笨 阅 蔡 伦 切 便 鲜',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第四单元',
          title: '会写字\n伟 贡 献 创 尤 存 累 改 价 促 社',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第四单元',
          title: '词语\n文明 伟大 贡献 祖先 创造 材料 尤其 保存 吸收 积累 经验 改进 价格 便宜 满足 促进 社会',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第四单元',
      title: '赵州桥',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第四单元',
          title: '会认字\n县 匠 砌 爪 抵 智 慧 遗',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第四单元',
          title: '会写字\n赵 桥 拱 济 设 计 史 坚 固 且 栏 贵 历',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第四单元',
          title: '词语\n闻名 设计 创举 减轻 不但 坚固 而且 美观 体现 才干 宝贵 历史 文化',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第四单元',
      title: '一幅名扬中外的画',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第四单元',
          title: '会写字\n择 摊 贩 吏 驴 乘 笼 拽 扰 貌',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第四单元',
      title: '语文园地四',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第四单元',
          title: '交流平台',
        ),
PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第四单元',
          title: '词句段运用',
        ),
PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第四单元',
          title: '日积月累',
        ),
PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第四单元',
          title: '词语\n援助 投掷 打捞 拆分 搅动 拓展',
        ),
      ],
    ),
    // 第五单元
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第五单元',
      title: '胡萝卜先生的长胡子',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第五单元',
          title: '会认字\n晾 尿 肩 掏',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第五单元',
          title: '会写字\n萝 卜 愁 浓 够 确 段 系 姐',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第五单元',
          title: '词语\n胡萝卜 胡子 发愁 浓密 面包 完全 结实 确定 足够 确实',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第五单元',
      title: '我变成了一棵树',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第五单元',
          title: '会认字\n嗓 痒 椭 菱 鳄 啃 醋 馋',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第五单元',
          title: '会写字\n希 担 容 易 震 零 肠 麻 烦',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第五单元',
          title: '词语\n希望 形状 喜欢 担心 容易 丁零 失望 巧克力 香肠 花生 牛奶 互相 想念 饭菜 可能 麻烦 眼睛 秘密',
        ),
      ],
    ),
    // 第六单元
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第六单元',
      title: '童年的水墨画',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第六单元',
          title: '会认字\n墨 溅',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第六单元',
          title: '会写字\n垂 染 碎 翅 膀 拔 浪 抖',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第六单元',
          title: '词语\n童年 垂柳 平静 翅膀 戏耍 葫芦 松树 清爽 泥土 开放',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第六单元',
      title: '肥皂泡',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第六单元',
          title: '会认字\n剩 和 悬 屏 巅 婴',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第六单元',
          title: '会写字\n皂 泡 类 弄 溶 套 悠 若 骄 傲',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第六单元',
          title: '词语\n肥皂泡 种类 其中 溶化 网球 分裂 形式 圆满 夕阳 目送 骄傲',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第六单元',
      title: '灰雀',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第六单元',
          title: '会认字\n胸 脯 婉',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第六单元',
          title: '会写字\n雀 养 粉 惹 仰 粒 遍 者 惜',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第六单元',
          title: '词语\n养病 粉红 仰望 或者 严寒 本来 可惜 肯定 微笑 诚实',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第六单元',
      title: '我不能失信',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第六单元',
          title: '会认字\n耀 示 歉 诺',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第六单元',
      title: '语文园地六',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第六单元',
          title: '交流平台',
        ),
PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第六单元',
          title: '词句段运用',
        ),
PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第六单元',
          title: '日积月累',
        ),
PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第六单元',
          title: '词语\n旭日 岛屿 海岸 浪花 军舰 铁锚 瞭望 巡航',
        ),
      ],
    ),
    // 第七单元
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第七单元',
      title: '火烧云',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第七单元',
          title: '会认字\n檀 猪 跪 庙 揉',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第七单元',
          title: '会写字\n烧 盈 乘 寿 形 颜 钟 武 镇 偏',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第七单元',
          title: '词语\n火烧云 笑盈盈 乘凉 高寿 红彤彤 变化 金灿灿 颜色 似乎 威武 镇静 其实 沉静 偏偏 等待 爱好',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第七单元',
      title: '暴风雨来临之前',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第七单元',
          title: '会认字\n蔓 延 汹',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第七单元',
          title: '会写字\n临 越 闷 昏 暗 况 报 梢 隆',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第七单元',
          title: '词语\n来临 沉闷 奇形怪状 昏暗 轻微 情况 动静 赶路 抖动 树梢 乱蓬蓬 轰隆隆',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第七单元',
      title: '我们奇妙的世界',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第七单元',
          title: '会认字\n蔚 雕 注 烁 蜡 烛 略 劲',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第七单元',
          title: '会写字\n呈 幻 季 夏 辉 芒 建 柱 剑',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第七单元',
          title: '词语\n奇妙 生命 呈现 变幻 圆润 李子 夏日 感叹 光辉 神奇 光芒 建造 冰柱 锋利 刀剑 融化',
        ),
      ],
    ),
    // 第八单元
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第八单元',
      title: '慢性子裁缝和急性子顾客',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第八单元',
          title: '会认字\n缝 箱 夹 讶',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第八单元',
          title: '会写字\n性 顾 夸 奖 承 袖 衬 衫 负 责 泄 恼',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第八单元',
          title: '词语\n性子 顾客 笑话 大方 夸奖 承认 提前 服务 满意 袖子 衬衫 负责 名声 泄气 放心 手艺 感动 恼怒',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第八单元',
      title: '漏',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第八单元',
          title: '会认字\n脊 贼 晕 颠 旋 嫌',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第八单元',
          title: '会写字\n漏 胖 驴 爪 莫 厉 害 闯 摸 歪 胶 纵',
        ),
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第八单元',
          title: '词语\n莫非 厉害 走南闯北 听说 发抖 害怕 松手 骨头 逃命 甘心 逃跑',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第八单元',
      title: '枣核',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
        PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第八单元',
          title: '会认字\n核 妻 爹 犁 聪 旱 纳 搜 折 困 岂 涨',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 3,
      term: '下册',
      unit: '第八单元',
      title: '语文园地八',
      // 字词取课本三张表原文（识字表/写字表/词语表，26春统编版）；无 lessonId，仅供查看
      subLessons: [
PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第八单元',
          title: '交流平台',
        ),
PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第八单元',
          title: '词句段运用',
        ),
PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第八单元',
          title: '日积月累',
        ),
PrimaryChineseLesson(
          grade: 3,
          term: '下册',
          unit: '第八单元',
          title: '词语\n呼吸 咳嗽 唠叨 吆喝 诉说 讽刺 告诫 辩论',
        ),
      ],
    ),

    // 四年级上册 (统编版官方完整目次)
    // ==============================================================
    // 第一单元
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第一单元',
      title: '观潮',
      lessonId: 'g4a-guanchao-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第一单元',
          title: '会认字\n盐 屹 昂 顿 鼎 沸 贯 浩 崩 震 霎 余',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第一单元',
          title: '会写字\n潮 据 堤 阔 盼 滚 顿 逐 渐 堵 犹 崩 震 霎 余',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第一单元',
          title: '词语\n奇观 农历 据说 大堤 宽阔 笼罩 人山人海 顿时 逐渐 犹如 齐头并进 山崩地裂 余波 依旧',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第一单元',
      title: '现代诗二首（秋晚的江上·花牛歌）',
      lessonId: 'g4a-huaniuge-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第一单元',
          title: '会认字\n巢 苇 罗 眠 霸 占',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第一单元',
      title: '繁星',
      lessonId: 'g4a-fanxing-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第一单元',
          title: '会认字\n昧 坠 怀',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第一单元',
      title: '语文园地一',
      lessonId: 'g4a-u1-yuandi-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第一单元',
          title: '词句段运用',
          lessonId: 'g4a-yuandi1-zici-b-dual',
          isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第一单元',
          title: '鹿柴（日积月累）',
          lessonId: 'luchai-b-dual',
          isDualMode: true,
        ),
      ],
    ),

    // 第二单元
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第二单元',
      title: '一个豆荚里的五粒豆',
      lessonId: 'g4a-doudoulidawulidou-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第二单元',
          title: '会认字\n荚 豌 按 僵 苔 囚 框 溢',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第二单元',
          title: '会写字\n豌 按 舒 适 恐 僵 硬 枪 耐 探 愉 曾',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第二单元',
          title: '词语\n豌豆 按照 暖洋洋 舒适 黑暗 恐怕 僵硬 丰满 等待 玩具枪 虚弱 耐心 温和 暖和 愉快 兴奋 曾经',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第二单元',
      title: '夜间飞行的秘密',
      lessonId: 'g4a-yejianfeixing-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第二单元',
          title: '会认字\n蝙 蝠 即 锐 系 铛 蝇 证 障 荧 屏',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第二单元',
          title: '会写字\n蚊 即 科 横 竖 绳 系 蝇 证 研 究 达 驾 驶',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第二单元',
          title: '词语\n蚊子 即使 灵巧 科学家 横七竖八 绳子 苍蝇 证明 反复 研究 雷达 显示 驾驶员',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第二单元',
      title: '方帽子店',
      lessonId: 'g4a-fangmaozidian-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第二单元',
          title: '会认字\n橱 蕉 扣 嚷 溜 筒 董',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第二单元',
          title: '会写字\n帽 脑 袋 假 扣 懂 溜 筒 摆 玻 璃',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第二单元',
          title: '词语\n帽子 脑袋 舒服 假如 设法 懂事 一溜烟 各式各样 摆放 玻璃',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第二单元',
      title: '田忌赛马',
      lessonId: 'g4a-tianjisaima-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第二单元',
          title: '会认字\n忌 获 赢 拳 跃 测 输 谋 策 荐',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第二单元',
      title: '语文园地二',
      lessonId: 'g4a-u2-yuandi-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第二单元',
          title: '交流平台',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第二单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第二单元',
          title: '善问好学名句（日积月累）',
          lessonId: 'g4a-u2-yuandi-dual',
          isDualMode: true,
        ),
      ],
    ),

    // 第三单元
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第三单元',
      title: '古诗三首（暮江吟·题西林壁·雪梅）',
      lessonId: 'g4a-mujiangyin-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第三单元',
          title: '会认字\n暮 瑟 缘 降 骚 逊 输',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第三单元',
          title: '会写字\n残 铺 壁 横 侧 峰 庐 缘 降 评 章 输',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第三单元',
      title: '爬山虎的脚',
      lessonId: 'g4a-pashanhu-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第三单元',
          title: '会认字\n均 茎 柄 蜗 曲 萎',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第三单元',
          title: '会写字\n虎 脚 操 嫩 隙 柄 触 痕 迹 瞧',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第三单元',
          title: '词语\n爬山虎 操场 嫩叶 嫩红 舒服 均匀 重叠 空隙 叶柄 反面 触角 弯曲 细小 痕迹 瞧不起 牢固',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第三单元',
      title: '蟋蟀的住宅',
      lessonId: 'g4a-xishudezhuzhai-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第三单元',
          title: '会认字\n蟋 蟀 宅 慎 址 畅 倾 骤 置 糙 朴 燥',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第三单元',
          title: '会写字\n宅 毫 重 选 择 址 厅 专 修 较 腿 增',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第三单元',
          title: '词语\n蟋蟀 住宅 慎重 选择 住址 大厅 柔弱 通畅 倾斜 骤雨 布置 粗糙 平坦 简朴 干燥 光滑 修理 重要 增长',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第三单元',
      title: '语文园地三',
      lessonId: 'g4a-u3-yuandi-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(grade: 4, term: '上册', unit: '第三单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第三单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第三单元',
          title: '节气气象谚语（日积月累）',
        ),
      ],
    ),

    // 第四单元
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第四单元',
      title: '盘古开天地',
      lessonId: 'g4a-pangu-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第四单元',
          title: '会认字\n劈 缓 浊 丈 隆 肢 躯 液',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第四单元',
          title: '会写字\n睁 翻 斧 劈 缓 浊 丈 撑 竭 累 液 奔 茂 滋',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第四单元',
          title: '词语\n睁眼 翻身 斧头 劈开 缓缓上升 浑浊 一丈 撑起 精疲力竭 累倒 血液 奔流不息 茂盛 滋润',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第四单元',
      title: '精卫填海',
      lessonId: 'g4a-jingweitianhai-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第四单元',
          title: '会认字\n帝 少 曰 溺 返',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第四单元',
          title: '会写字\n帝 溺 返 衔',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第四单元',
      title: '普罗米修斯',
      lessonId: 'g4a-puluomixiusi-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第四单元',
          title: '会认字\n斯 惨 盗 驰 恕 坚 押 锁 遭 恶 脏 愤 砸',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第四单元',
          title: '会写字\n悲 惨 兽 佩 坚 违 抗 环 锁 既 狠 著 愤 获',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第四单元',
          title: '词语\n人间 悲惨 情景 危害 猛兽 严厉 敬佩 悄悄 坚定 违抗 狠心 尖利 著名 愤愤不平 获得',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第四单元',
      title: '女娲补天',
      lessonId: 'g4a-nuwaputian-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第四单元',
          title: '会认字\n败 措 混 项 熄 塌 杀 颂 绩',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第四单元',
      title: '语文园地四',
      lessonId: 'g4a-u4-yuandi-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(grade: 4, term: '上册', unit: '第四单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第四单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第四单元',
          title: '嫦娥（日积月累）',
        ),
      ],
    ),

    // 第五单元（习作单元）
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第五单元',
      title: '麻雀',
      lessonId: 'g4a-maque-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第五单元',
          title: '会认字\n嗅 奈 拯 嘶 哑 庞',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第五单元',
          title: '会写字\n嗅 呆 奈 巢 齿 躯 掩 护 幼 搏 庞 量 愣',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第五单元',
          title: '词语\n打猎 猛烈 无可奈何 拍打 嘴角 分明 牙齿 绝望 尖叫 身躯 掩护 幼儿 搏斗 庞大 安然 强大 力量',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第五单元',
      title: '爬天都峰',
      lessonId: 'g4a-patiandfeng-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第五单元',
          title: '会认字\n级 链 攀 相 辫 呵',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第五单元',
          title: '会写字\n哩 级 链 颤 攀 猴 鲫 念 辫 呵',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第五单元',
          title: '词语\n假日 云彩 石级 发颤 年纪 奋力 猴子 纪念 辫子 笑呵呵 鼓舞 居然',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第五单元',
      title: '习作例文与初试身手',
      subLessons: [
        PrimaryChineseLesson(grade: 4, term: '上册', unit: '第五单元', title: '初试身手'),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第五单元',
          title: '我家的杏熟了（习作例文）',
      lessonId: 'g4a-xingshizuowen1-dual',
      isDualMode: true,
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第五单元',
          title: '小木船（习作例文）',
          lessonId: 'g4a-xingshizuowen2-dual',
          isDualMode: true,
        ),
      ],
    ),

    // 第六单元
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第六单元',
      title: '长城',
      lessonId: 'g4a-changcheng-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第五单元',
          title: '会认字\n崇 峻 嘉 峪 瞭 屯 垒 魄',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第五单元',
          title: '会写字\n崇 旋 嘉 砖 隔 屯 堡 垒 仗 扶 智 慧 魄',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第五单元',
          title: '词语\n盘旋 城砖 城墙 屯兵 堡垒 打仗 呼应 肩膀 智慧 凝结 气魄雄伟',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第六单元',
      title: '颐和园',
      lessonId: 'g4a-yiheyuan-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第五单元',
          title: '会认字\n颐 耸 阁 舫 眺 堤 态',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第五单元',
          title: '会写字\n殿 廊 柱 栽 筑 阁 朱 堤 雕 狮 态',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第五单元',
          title: '词语\n长廊 柱子 神清气爽 建筑 佛香阁 金碧辉煌 宫殿 葱郁 掩映 朱红 隐隐约约 堤岸 雕刻 狮子 姿态不一',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第六单元',
      title: '秦兵马俑',
      lessonId: 'g4a-qinbingmayong-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第五单元',
          title: '会认字\n誉 瞰 统 率 征 靡 魁 搏',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第六单元',
      title: '语文园地六',
      lessonId: 'g4a-u6-yuandi-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(grade: 4, term: '上册', unit: '第六单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第六单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第六单元',
          title: '处世格言（日积月累）',
        ),
      ],
    ),

    // 第七单元
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第七单元',
      title: '牛和鹅',
      lessonId: 'g4a-niuhe-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第六单元',
          title: '会认字\n谓 拳 捶 顽 吁 襟 膊 瓶 怖 凭 欺 掐',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第六单元',
          title: '会写字\n摸 甚 跪 捶 绕 顽 脖 脱 概 惹 昏 握 摔 凭 掐',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第六单元',
          title: '词语\n甚至 顽皮 故意 脖子 扑打 忙乱 大概 助威 昏乱 结实 汉子 可笑 无缘无故 平白',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第七单元',
      title: '一只窝囊的大老虎',
      lessonId: 'g4a-wonangdelaohu-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第六单元',
          title: '会认字\n囊 露 羡 角 殷 豁 撇 霉 亏 哄 拙 唉 砸 啊',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第六单元',
          title: '会写字\n段 俩 练 裤 逃 罩 亏 挖 撤 堂 砸 锅',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第六单元',
          title: '词语\n文艺 表演 角色 期待 排练 危机 通情达理 充分 自信 提示 撤换 紧张 哄堂大笑 砸锅 至今',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第七单元',
      title: '陀螺',
      lessonId: 'g4a-tuolu-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第六单元',
          title: '会认字\n钉 况 败 恨 帅 彻 溃 誉 丑 豪',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第六单元',
          title: '会写字\n否 旋 况 败 椅 尤 恨 帅 预 溃 品 丑 豪',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第六单元',
          title: '词语\n冰天雪地 否则 旋转 重整旗鼓 况且 得心应手 椅子 仍然 尤其 手舞足蹈 恨不得 预料 摇头晃脑 不动声色 顽强 溃败 自豪',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第八单元',
      title: '王戎不取道旁李',
      lessonId: 'g4a-wangrong-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第八单元',
          title: '会认字\n戎 诸 竞 唯',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第八单元',
          title: '会写字\n戎 尝 诸 竞 唯',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第七单元',
      title: '语文园地七',
      lessonId: 'g4a-u7-yuandi-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(grade: 4, term: '上册', unit: '第七单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第七单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第七单元',
          title: '别董大（日积月累）',
        ),
      ],
    ),

    // 第八单元
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第八单元',
      title: '我将无我，不负人民',
      lessonId: 'g4a-wojiangwuwu-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第八单元',
          title: '会认字\n菲 抛 奉 亿 邀',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第八单元',
          title: '会写字\n席 抛 激 奉 训 亿 勤 邀',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第七单元',
      title: '为中华之崛起而读书',
      lessonId: 'g4a-weihuoming-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第七单元',
          title: '会认字\n崛 范 魏 晰 效 淮 惑 惩 训 斥 难',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第七单元',
          title: '会写字\n肃 默 晰 振 胸 怀 赞 效 凡 顾 训 斥',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第七单元',
          title: '词语\n严肃 清晰 抱负 胸怀 赞叹 表情 忘怀 果真 非凡 指望 训斥 体会 分量 响亮 光耀门楣 疑惑不解 中华不振 左顾右盼',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第八单元',
      title: '延安，我把你追寻',
      lessonId: 'g4a-yanan-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第八单元',
          title: '会认字\n昔 茅 炕 旦 媚',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第八单元',
      title: '古诗三首（凉州词·出塞·夏日绝句）',
      lessonId: 'g4a-chusai-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第八单元',
          title: '会认字\n塞 秦 征 将 杰',
        ),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第八单元',
          title: '会写字\n塞 秦 征 词 催 醉 杰 亦 雄 项',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 4,
      term: '上册',
      unit: '第八单元',
      title: '语文园地八',
      lessonId: 'g4a-u8-yuandi-dual',
      isDualMode: true,
      subLessons: [
        PrimaryChineseLesson(grade: 4, term: '上册', unit: '第八单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第八单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(grade: 4, term: '上册', unit: '第八单元', title: '书写提示'),
        PrimaryChineseLesson(
          grade: 4,
          term: '上册',
          unit: '第八单元',
          title: '浪淘沙·其七（日积月累）',
        ),
      ],
    ),

    // ==============================================================
    // 四年级下册 (统编版官方完整目次)
    // ==============================================================
    // 第一单元
    PrimaryChineseLesson(
      grade: 4,
      term: '下册',
      unit: '第一单元',
      title: '古诗词三首（四时田园杂兴·宿新市徐公店·清平乐·村居）',
    ),
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第一单元', title: '乡下人家'),
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第一单元', title: '天窗'),
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第一单元', title: '三月桃花水'),

    // 第二单元
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第二单元', title: '琥珀'),
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第二单元', title: '飞向蓝天的恐龙'),
    PrimaryChineseLesson(
      grade: 4,
      term: '下册',
      unit: '第二单元',
      title: '纳米技术就在我们身边',
    ),
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第二单元', title: '千年梦圆在今朝'),

    // 第三单元
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第三单元', title: '短诗三首（繁星）'),
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第三单元', title: '绿'),
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第三单元', title: '白桦'),
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第三单元', title: '在天晴了的时候'),

    // 第四单元
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第四单元', title: '猫'),
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第四单元', title: '母鸡'),
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第四单元', title: '白鹅'),

    // 第五单元
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第五单元', title: '海上日出'),
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第五单元', title: '记金华的双龙洞'),

    // 第六单元
    PrimaryChineseLesson(
      grade: 4,
      term: '下册',
      unit: '第六单元',
      title: '文言文二则（囊萤夜读·铁杵成针）',
    ),
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第六单元', title: '小英雄雨来'),
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第六单元', title: '我们家的男子汉'),
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第六单元', title: '芦花鞋'),

    // 第七单元
    PrimaryChineseLesson(
      grade: 4,
      term: '下册',
      unit: '第七单元',
      title: '古诗三首（芙蓉楼送辛渐·塞下曲·墨梅）',
    ),
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第七单元', title: '黄继光'),
    PrimaryChineseLesson(
      grade: 4,
      term: '下册',
      unit: '第七单元',
      title: '“诺曼底号”遇难记',
    ),
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第七单元', title: '挑山工'),

    // 第八单元
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第八单元', title: '宝葫芦的秘密'),
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第八单元', title: '巨人的花园'),
    PrimaryChineseLesson(grade: 4, term: '下册', unit: '第八单元', title: '海的女儿'),

    // ==============================================================
    // 五年级上册 (统编版官方完整目次)
    // ==============================================================
    // 第一单元
    PrimaryChineseLesson(grade: 5, term: '上册', unit: '第一单元', title: '桂花雨',
      lessonId: 'g5a-guihuayu-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第一单元', title: '会认字\n箩 杭'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第一单元', title: '会写字\n懂 兰 箩 婆 糕 饼 浸 缠 茶 捡'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第一单元', title: '词语\n桂花 懂得 糕饼 茶叶 箩筐 外婆 浸泡 沉浸 缠绕 捡起 杭州 尤其 欣赏 姿态 香飘十里'),
      ],
    ),
    PrimaryChineseLesson(grade: 5, term: '上册', unit: '第一单元', title: '落花生',
      lessonId: 'g5a-luohuasheng-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第一单元', title: '会认字\n亩 吩 咐 榨 矮 榴'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第一单元', title: '会写字\n亩 播 浇 吩 咐 亭 慕 矮 榨 谈'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第一单元', title: '词语\n播种 浇水 吩咐 榨油 爱慕 体面 开辟 居然 便宜 可贵 收获 茅亭 高矮'),
      ],
    ),
    PrimaryChineseLesson(grade: 5, term: '上册', unit: '第一单元', title: '珍珠鸟',
      lessonId: 'g5a-zhenzhuniao-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第一单元', title: '会认字\n蔓 幽 悉 雏 柜 享 陪 待 趴 睑 眸'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 5,
      term: '上册',
      unit: '第一单元',
      title: '语文园地一',
      lessonId: 'g5a-diyidanyuanyuwenyuandi-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第一单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 5,
          term: '上册',
          unit: '第一单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 5,
          term: '上册',
          unit: '第一单元',
          title: '蝉（日积月累）',
        ),
      ],
    ),

    // 第二单元（阅读策略单元）
    PrimaryChineseLesson(grade: 5, term: '上册', unit: '第二单元', title: '冀中的地道战',
      lessonId: 'g5a-jizhongdedidaozhan-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第二单元', title: '会认字\n侵 略 垒 任 丘 搁 陷 拐 岔'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第二单元', title: '会写字\n侵 略 筑 堡 党 丘 妨 蔽 陷 拐'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第二单元', title: '词语\n修筑 拐弯 陷坑 隐蔽 游击 坚持'),
      ]),
    PrimaryChineseLesson(
      grade: 5,
      term: '上册',
      unit: '第二单元',
      title: '将相和',
      lessonId: 'g5a-jiangxianghe-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第二单元', title: '会认字\n璧 臣 强 诺 划 典 罪 廉 抵 御 辞 辱 擅 卿 削 袍'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第二单元', title: '会写字\n召 臣 议 缺 宫 献 诺 典 抄 罪 怯 拒 荆'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第二单元', title: '词语\n大臣 职位 拒绝 示弱 胆怯 得罪 典礼 允诺 商量 称赞 召集 解决'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 5,
      term: '上册',
      unit: '第二单元',
      title: '什么比猎豹的速度更快',
      lessonId: 'g5a-shenmebiliebaodesudugengkuai-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第二单元', title: '会认字\n鸵 隼 瀚 啸'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第二单元', title: '会写字\n冠 俯 喷 枚 箭 浩 筒 束 赤 圈 置'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第二单元', title: '词语\n猎豹 冠军 陆地 俯冲 搭乘 火箭 发动机 呼啸 手电筒 赤道 难以置信 鸵鸟 游隼 浩瀚 一束 放置 圆圈'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 5,
      term: '上册',
      unit: '第二单元',
      title: '“诺曼底号”遇难记',
      lessonId: 'g5a-nuomandihaoyunanji-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第二单元', title: '会认字\n弥 脉 剖 裸 泣 汹 酣 械 卑 岗 宰 遣 嘶'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第二单元', title: '会写字\n伦 腹 剖 窟 窿 混 维 秩 卑 岗 宰 措 遣 践'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第二单元', title: '词语\n弥漫 山脉 剖开 半裸 汹涌 酣睡 机械 岗位 主宰 调遣 维持 秩序 卑微 措施 实践 窟窿 混乱 腹部 伦理'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 5,
      term: '上册',
      unit: '第二单元',
      title: '语文园地二',
      lessonId: 'g5a-dierdanyuanyuwenyuandi-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第二单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 5,
          term: '上册',
          unit: '第二单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 5,
          term: '上册',
          unit: '第二单元',
          title: '惜时名句（日积月累）',
        ),
      ],
    ),

    // 第三单元
    PrimaryChineseLesson(grade: 5, term: '上册', unit: '第三单元', title: '猎人海力布',
      lessonId: 'g5a-lierenhailibu-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第三单元', title: '会认字\n酬 誓 谎 牺 牲'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第三单元', title: '会写字\n酬 珍 叮 嘱 塌 焦 誓 谎 延 悔 扶'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第三单元', title: '词语\n猎物 酬谢 珍宝 感激 叮嘱 复活 议论 崩塌 搬家 焦急 发誓 谎话 迟延 镇定 后悔 悲痛 牺牲'),
      ],
    ),
    PrimaryChineseLesson(grade: 5, term: '上册', unit: '第三单元', title: '牛郎织女（一）',
      lessonId: 'g5a-niulangzhinvyi-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第三单元', title: '会认字\n嫂 恳 筛 歹 罕 梭 婚 趟 泳 托 辈 瞌 酿'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第三单元', title: '会写字\n郎 爹 嫂 辆 歹 罕 纱 妻 趟 托 狱 婚 辈 挨'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第三单元', title: '词语\n嫂子 爹娘 剩饭 床铺 亲密 好歹 稀罕 妻子 晚霞 游泳 结婚 一辈子 车辆 纱衣 托付 监狱 挨近'),
      ],
    ),
    PrimaryChineseLesson(grade: 5, term: '上册', unit: '第三单元', title: '牛郎织女（二）',
      lessonId: 'g5a-niulangzhinver-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第三单元', title: '会认字\n俭 皇 偎 衰 泰 珊 瑚 礁 筐 拗 惩 簪'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第三单元', title: '词语\n节俭 依偎 衰老 泰山 珊瑚 礁石 竹筐 惩罚 玉簪 富丽堂皇 执拗 拗不过 怒气冲冲 好歹 察访 鹊桥 天河 男耕女织 日久天长 惊天动地'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 5,
      term: '上册',
      unit: '第三单元',
      title: '语文园地三',
      lessonId: 'g5a-disandanyuanyuwenyuandi-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第三单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 5,
          term: '上册',
          unit: '第三单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 5,
          term: '上册',
          unit: '第三单元',
          title: '乞巧（日积月累）',
        ),
      ],
    ),

    // 第四单元
    PrimaryChineseLesson(
      grade: 5,
      term: '上册',
      unit: '第四单元',
      title: '古诗三首（示儿·题临安邸·己亥杂诗）',
      lessonId: 'g5a-gushisanshou1shier-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第四单元', title: '会认字\n邸 熏 亥 恃 喑 擞 龚'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第四单元', title: '会写字\n祭 乃 熏 杭 亥 恃 哀 拘'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第四单元', title: '词语\n家祭 乃翁 杭州 熏陶 己亥 恃风雷 悲哀 拘束'),
      ],
    ),
    PrimaryChineseLesson(grade: 5, term: '上册', unit: '第四单元', title: '少年中国说',
      lessonId: 'g5a-shaonianzhongguoshuojiexuan-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第四单元', title: '会认字\n鳞 惶 哉 渊 隼 矞 硎'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第四单元', title: '会写字\n泻 潜 试 胎 皇 履 疆'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第四单元', title: '词语\n一泻汪洋 潜龙腾渊 鳞爪飞扬 鹰隼试翼 风尘翕张 奇花初胎 矞矞皇皇 干将发硎 有作其芒 天戴其苍 地履其黄 纵有千古 横有八荒 前途似海 来日方长 壮哉 震惶 边疆'),
      ],
    ),
    PrimaryChineseLesson(grade: 5, term: '上册', unit: '第四单元', title: '圆明园的毁灭',
      lessonId: 'g5a-yuanmingyuandehuimie-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第四单元', title: '会认字\n珑 剔 澜 陵 宏 烬 奉 瑰 闯 统'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第四单元', title: '会写字\n毁 估 损 拱 辉 煌 殿 陵 览 境 宏 唐 闯 销 奉'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第四单元', title: '词语\n毁灭 不可估量 损失 殿堂 象征 仿照 建筑 漫游 饱览 境界 宏伟 瑰宝 销毁 罪证 奉命 统统'),
      ],
    ),
    PrimaryChineseLesson(grade: 5, term: '上册', unit: '第四单元', title: '梅兰芳蓄须明志',
      lessonId: 'g5a-meilanfangxuxumingzhi-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第四单元', title: '会认字\n蓄 租 剃 纠 缠 邀 斩 妄 烫 扰'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第四单元', title: '词语\n蓄须 租界 剃刀 纠缠 骚扰 拒绝 卖房度日 登台 妄想 滚烫 要挟 邀请'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 5,
      term: '上册',
      unit: '第四单元',
      title: '语文园地四',
      lessonId: 'g5a-disidanyuanyuwenyuandi-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第四单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 5,
          term: '上册',
          unit: '第四单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 5,
          term: '上册',
          unit: '第四单元',
          title: '政通人和名句（日积月累）',
        ),
      ],
    ),

    // 第五单元（习作单元）
    PrimaryChineseLesson(grade: 5, term: '上册', unit: '第五单元', title: '太阳',
      lessonId: 'g5a-taiyang-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第五单元', title: '会认字\n摄 氏 殖 炭 疗 兽 蔬 较'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第五单元', title: '会写字\n抵 氏 殖 粮 炭 区 杀 菌 疗'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第五单元', title: '词语\n传说 摄氏度 繁殖 粮食 煤炭 地区 杀菌 治疗 漂浮 摄取 蔬菜 野兽 比较 密切 吸收 预防'),
      ],
    ),
    PrimaryChineseLesson(grade: 5, term: '上册', unit: '第五单元', title: '金字塔',
      lessonId: 'g5a-jinzita-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第五单元', title: '会认字\n译 愧 熠 遐 刃 埃 滥 淤 湛 黏'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第五单元', title: '词语\n埃及 译名 不愧 遐想 刀刃 淤泥 泛滥 精湛 黏土 黏着物 熠熠发光 幽思 矗立 轮廓 陵墓 开凿 不可思议'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 5,
      term: '上册',
      unit: '第五单元',
      title: '习作例文与初试身手',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第五单元', title: '初试身手'),
        PrimaryChineseLesson(
          grade: 5,
          term: '上册',
          unit: '第五单元',
          title: '鲸（习作例文）',
      lessonId: 'g5a-liwen1jing-dual',
        ),
        PrimaryChineseLesson(
          grade: 5,
          term: '上册',
          unit: '第五单元',
          title: '风向袋的制作（习作例文）',
      lessonId: 'g5a-liwen2fengxiangdaidezhizuo-dual',
        ),
      ],
    ),

    // 第六单元
    PrimaryChineseLesson(grade: 5, term: '上册', unit: '第六单元', title: '慈母情深',
      lessonId: 'g5a-cimuqingshen-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第六单元', title: '会认字\n魄 抑 颓 纫 噪 褐 惫 耽 兜 龟'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第六单元', title: '会写字\n辞 抑 碌 吊 酷 暑 噪 脊 竟 龟 忍 酸 权 挣 茧'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第六单元', title: '词语\n连续 广播 铁路 辞退 挣钱 压抑 潮湿 忙碌 阴暗 酷暑 炎夏 蒸笼 噪声 瘦弱 脊背 口罩 龟裂 忍心 数落 权利 衣兜 疲惫 耽误 褐色 颓败'),
      ],
    ),
    PrimaryChineseLesson(grade: 5, term: '上册', unit: '第六单元', title: '父爱之舟',
      lessonId: 'g5a-fuaizhizhou-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第六单元', title: '会认字\n茧 栈 冤 枉 惚 跷 僻 迪 嫁 缴 榜 兼 嘲 枕'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第六单元', title: '会写字\n蚕 考 疼 席 糖 屑 启 迪'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第六单元', title: '词语\n渔船 报考 教训 心疼 席子 庙会 彩排 糖果 抽象 启迪 毕业 寄宿 师范 路费 轮换 领略 意境 磨灭 精致 蚕茧 纸屑 客栈 偏僻 嘲笑 枕头 缴费'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 5,
      term: '上册',
      unit: '第六单元',
      title: '航天员写给孩子的信',
      lessonId: 'g5a-hangtianyuanxiegeihaizidexin-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第六单元', title: '会认字\n涟 漪 谅 铠 肋 赴 辰 姥 尚 凯 淖 憾'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第六单元', title: '词语\n涟漪 原谅 铠甲 软肋 奔赴 星辰 姥姥 尚未 凯旋 泥淖 遗憾 牵挂 嘱托 使命 困境 自律 守时'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 5,
      term: '上册',
      unit: '第六单元',
      title: '语文园地六',
      lessonId: 'g5a-diliudanyuanyuwenyuandi-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第六单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 5,
          term: '上册',
          unit: '第六单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 5,
          term: '上册',
          unit: '第六单元',
          title: '勤俭节约名言（日积月累）',
        ),
      ],
    ),

    // 第七单元
    PrimaryChineseLesson(
      grade: 5,
      term: '上册',
      unit: '第七单元',
      title: '古诗词三首（山居秋暝·枫桥夜泊·早春呈水部张十八员外）',
      lessonId: 'g5a-gushisanshou    1shanjuqiuming-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第七单元', title: '会认字\n暝 浣 愈 酥'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第七单元', title: '会写字\n孙 泊 愁 寺 畔'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第七单元', title: '词语\n暝色 浣女 王孙 停泊 忧愁 寺庙 河畔 霜天 渔火 姑苏 天街 润如酥 绝胜 皇都'),
      ],
    ),
    PrimaryChineseLesson(grade: 5, term: '上册', unit: '第七单元', title: '第一场雪',
      lessonId: 'g5a-diyichangxue-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第七单元', title: '会认字\n骤 凛 冽 彤 屑 谚 馒 吱'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第七单元', title: '会写字\n侵 铅 妆 俗 虹 枕 瑞'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第七单元', title: '词语\n骤然 凛冽 彤云 铅色 侵入 俗话 瑞雪 彩虹 枕头 雪屑 馒头 咯吱 簌簌 笼罩 覆盖 毛茸茸 沉甸甸'),
      ],
    ),
    PrimaryChineseLesson(grade: 5, term: '上册', unit: '第七单元', title: '白鹭',
      lessonId: 'g5a-bailu-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第七单元', title: '会认字\n鹭 嫌 喙 黛 嵌 匣 嗜 澄'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第七单元', title: '会写字\n宜 鹤 嫌 朱 嵌 框 匣 哨 嗜 恩 韵'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第七单元', title: '词语\n精巧 配合 身段 适宜 白鹤 生硬 寻常 忘却 镜匣 清澄 孤独 悠然 黄昏 恩惠 白鹭 色素 蓑毛 长喙 黛色 望哨 铿锵'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 5,
      term: '上册',
      unit: '第七单元',
      title: '语文园地七',
      lessonId: 'g5a-diqidanyuanyuwenyuandi-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第七单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 5,
          term: '上册',
          unit: '第七单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 5,
          term: '上册',
          unit: '第七单元',
          title: '渔歌子（日积月累）',
        ),
      ],
    ),

    // 第八单元
    PrimaryChineseLesson(grade: 5, term: '上册', unit: '第八单元', title: '古人谈读书',
      lessonId: 'g5a-gurentandushu-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第八单元', title: '会认字\n识 矣 岂 寝'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第八单元', title: '会写字\n耻 诲 谓 诵 岂'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第八单元', title: '词语\n羞耻 教诲 诵读 所谓 岂敢 默而识之 心到 眼到 口到'),
      ],
    ),
    PrimaryChineseLesson(grade: 5, term: '上册', unit: '第八单元', title: '忆读书',
      lessonId: 'g5a-yidushu-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第八单元', title: '会认字\n舅 宴 斩 凯 葛 鲁 寇 贾 呻 煞 某'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第八单元', title: '会写字\n舅 津 斩 限 凯 葛 述 衰 刊 琐 朴 篇 某 贾'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第八单元', title: '词语\n舅父 津津有味 英雄 无限 质朴 一知半解 述说 厌烦 荒唐 辛酸 访问 书刊 烦琐 真情实感 凯旋 诸葛亮 水浒传 荡寇志 呻吟 某年'),
      ],
    ),
    PrimaryChineseLesson(grade: 5, term: '上册', unit: '第八单元', title: '走遍天下书为侣',
      lessonId: 'g5a-zoubiantianxiashuweilv-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第八单元', title: '会认字\n侣 娱 趟 诵 零 某 豫'),
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第八单元', title: '词语\n伴侣 娱乐 一趟 背诵 忽略 零分 编写 某种 回味 品味 思考 篇章'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 5,
      term: '上册',
      unit: '第八单元',
      title: '语文园地八',
      lessonId: 'g5a-dibadanyuanyuwenyuandi-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 5, term: '上册', unit: '第八单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 5,
          term: '上册',
          unit: '第八单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 5,
          term: '上册',
          unit: '第八单元',
          title: '观书有感二首（日积月累）',
        ),
      ],
    ),

    // ==============================================================
    // 五年级下册 (统编版官方完整目次)
    // ==============================================================
    // 第一单元
    PrimaryChineseLesson(
      grade: 5,
      term: '下册',
      unit: '第一单元',
      title: '古诗三首（四时田园杂兴·稚子弄冰·村晚）',
    ),
    PrimaryChineseLesson(grade: 5, term: '下册', unit: '第一单元', title: '祖父的园子'),
    PrimaryChineseLesson(grade: 5, term: '下册', unit: '第一单元', title: '月是故乡明'),
    PrimaryChineseLesson(grade: 5, term: '下册', unit: '第一单元', title: '梅花魂'),

    // 第二单元
    PrimaryChineseLesson(grade: 5, term: '下册', unit: '第二单元', title: '草船借箭'),
    PrimaryChineseLesson(grade: 5, term: '下册', unit: '第二单元', title: '景阳冈'),
    PrimaryChineseLesson(grade: 5, term: '下册', unit: '第二单元', title: '猴王出世'),
    PrimaryChineseLesson(grade: 5, term: '下册', unit: '第二单元', title: '红楼春趣'),

    // 第三单元（综合性学习）
    PrimaryChineseLesson(
      grade: 5,
      term: '下册',
      unit: '第三单元（综合性学习）',
      title: '汉字真有趣',
    ),
    PrimaryChineseLesson(
      grade: 5,
      term: '下册',
      unit: '第三单元（综合性学习）',
      title: '我爱你，汉字',
    ),

    // 第四单元
    PrimaryChineseLesson(
      grade: 5,
      term: '下册',
      unit: '第四单元',
      title: '古诗三首（从军行·秋夜将晓出篱门迎凉有感·闻官军收河南河北）',
    ),
    PrimaryChineseLesson(grade: 5, term: '下册', unit: '第四单元', title: '青山处处埋忠骨'),
    PrimaryChineseLesson(grade: 5, term: '下册', unit: '第四单元', title: '军神'),
    PrimaryChineseLesson(grade: 5, term: '下册', unit: '第四单元', title: '清贫'),

    // 第五单元
    PrimaryChineseLesson(
      grade: 5,
      term: '下册',
      unit: '第五单元',
      title: '人物描写一组（摔跤·他像一棵挺脱的树·两茎灯草）',
    ),
    PrimaryChineseLesson(grade: 5, term: '下册', unit: '第五单元', title: '刷子李'),

    // 第六单元
    PrimaryChineseLesson(grade: 5, term: '下册', unit: '第六单元', title: '自相矛盾'),
    PrimaryChineseLesson(grade: 5, term: '下册', unit: '第六单元', title: '田忌赛马'),
    PrimaryChineseLesson(grade: 5, term: '下册', unit: '第六单元', title: '跳水'),

    // 第七单元
    PrimaryChineseLesson(grade: 5, term: '下册', unit: '第七单元', title: '威尼斯的小艇'),
    PrimaryChineseLesson(grade: 5, term: '下册', unit: '第七单元', title: '牧场之国'),
    PrimaryChineseLesson(grade: 5, term: '下册', unit: '第七单元', title: '金字塔'),

    // 第八单元
    PrimaryChineseLesson(grade: 5, term: '下册', unit: '第八单元', title: '杨氏之子'),
    PrimaryChineseLesson(grade: 5, term: '下册', unit: '第八单元', title: '手指'),
    PrimaryChineseLesson(grade: 5, term: '下册', unit: '第八单元', title: '童年的发现'),

    // ==============================================================
    // 六年级上册 (统编版官方完整目次)
    // ==============================================================
    // 第一单元
    PrimaryChineseLesson(
      grade: 6,
      term: '上册',
      unit: '第一单元',
      title: '草原',
      lessonId: 'g6a-caoyuan-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第一单元', title: '会写字\n毯 玻 璃 裳 虹 蹄 腐 稍 微'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第一单元', title: '词语\n绿毯 线条 柔美 惊叹 回味 乐趣 目的地 洒脱 衣裳 彩虹 马蹄 热乎乎 奶豆腐 礼貌 拘束 举杯 感人 会心 微笑'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 6,
      term: '上册',
      unit: '第一单元',
      title: '丁香结',
      lessonId: 'g6a-dingxiangjie-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第一单元', title: '会写字\n缀 窥 幽 雅 案 拙 薄 糊 蕾 恰 襟 恍 怨'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第一单元', title: '词语\n宅院 幽雅 伏案 浑浊 笨拙 参差 眼帘 单薄 照耀 文思 梦想 迷蒙 妩媚 模糊 花苞 衣襟 恍然 愁怨 顺心 平淡'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 6,
      term: '上册',
      unit: '第一单元',
      title: '古诗词三首（宿建德江·六月二十七日望湖楼醉书·西江月·夜行黄沙道中）',
      lessonId: 'g6a-gushicisanshou1sujiandejiang-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第一单元', title: '会写字\n德 鹊 蝉'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 6,
      term: '上册',
      unit: '第一单元',
      title: '语文园地一',
      lessonId: 'g6a-diyidanyuanyuwenyuandi-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第一单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 6,
          term: '上册',
          unit: '第一单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 6,
          term: '上册',
          unit: '第一单元',
          title: '过故人庄（日积月累）',
        ),
      ],
    ),

    // 第二单元
    PrimaryChineseLesson(
      grade: 6,
      term: '上册',
      unit: '第二单元',
      title: '七律·长征',
      lessonId: 'g6a-qilvchangzheng-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第二单元', title: '会写字\n律 崖 渡 索'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 6,
      term: '上册',
      unit: '第二单元',
      title: '狼牙山五壮士',
      lessonId: 'g6a-langyashanwuzhuangshi-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第二单元', title: '会写字\n寇 副 榴 弹 抡 贯 棋 悬 沸 涧 雹 屹 悦 迈 屈'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第二单元', title: '词语\n日寇 奋战 险要 手榴弹 全神贯注 悬崖 斩钉截铁 热血沸腾 攀登 居高临下 山涧 粉身碎骨 雹子 屹立 眺望 喜悦 壮烈 豪迈 不屈 惊天动地'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 6,
      term: '上册',
      unit: '第二单元',
      title: '开国大典',
      lessonId: 'g6a-kaiguodadian-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第二单元', title: '会写字\n政 府 宾 盏 栏 汇 爆 宣 阅 制 坦 距 隆 射'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第二单元', title: '词语\n协商 汇集 预定 爆发 排山倒海 宣布 就位 宣告 雄伟 肃静 旗帜 语调 完毕 检阅 制服 坦克 一致 距离 高潮 次序'),
      ],
    ),
    PrimaryChineseLesson(grade: 6, term: '上册', unit: '第二单元', title: '我的战友邱少云',
      lessonId: 'g6a-wodezhanyouqiushaoyun-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第二单元', title: '会认字\n坳 蜷 蔓 伪 摧 蔽 趴 搜 幕 液 缩 熄 呻'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第二单元', title: '词语\n山坳 潜伏 隐蔽 伪装 趴下 搜索 蔓延 蜷缩 熄灭 呻吟 摧毁 火力警戒 烈火 千斤巨石'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 6,
      term: '上册',
      unit: '第二单元',
      title: '语文园地二',
      lessonId: 'g6a-dierdanyuanyuwenyuandi-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第二单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 6,
          term: '上册',
          unit: '第二单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 6,
          term: '上册',
          unit: '第二单元',
          title: '爱国名言（日积月累）',
        ),
      ],
    ),

    // 第三单元（阅读策略单元）
    PrimaryChineseLesson(grade: 6, term: '上册', unit: '第三单元', title: '竹节人',
      lessonId: 'g6a-zhujieren-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第三单元', title: '会认字\n颓 疙 瘩 棍 俨 鏖 咤 蟠 窦 敦 叉 靡 拙'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第三单元', title: '会写字\n豁 凛 疙 瘩 棍 橡 雕 跺 颓 沮 丧 趴 屉 疲 倦 裁'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第三单元', title: '词语\n豁开 疙瘩 冰棍 橡皮 雕刻 疲倦 抽屉 跺脚 颓然 沮丧 趴下 鏖战 风靡 俨然 叉腿'),
      ],
    ),
    PrimaryChineseLesson(grade: 6, term: '上册', unit: '第三单元', title: '宇宙生命之谜',
      lessonId: 'g6a-yuzhoushengmingzhimi-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第三单元', title: '会认字\n嫦 娥 轨 辐 壤 陨 粟 薄'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第三单元', title: '会写字\n谜 尚 氧 倾 揭 斑 燥 漠 磁 抵 御 素 盗 培'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第三单元', title: '词语\n发达 理论 类似 猜测 起源 适当 氧气 提供 能源 昼夜 神秘 观测 拍摄 斑点 枯萎 干燥 沙漠 磁场 抵御 因素 考察 培养 轨道 辐射 土壤 陨石'),
      ],
    ),
    PrimaryChineseLesson(grade: 6, term: '上册', unit: '第三单元', title: '故宫博物院',
      lessonId: 'g6a-gugongbowuyuan-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第三单元', title: '会认字\n矗 鳌 湛 琉 蟠 轴 銮 磬 檀 乾 坤 穆 枋 藻 矫 嫔 迥 攒'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第三单元', title: '词语\n矗立 鳌头 湛蓝 琉璃 蟠龙 中轴线 金銮殿 击磬 檀香 额枋 藻井 矫健 妃嫔 肃穆 攒聚 雕镂 斗拱 玉玺 水榭'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 6,
      term: '上册',
      unit: '第三单元',
      title: '语文园地三',
      lessonId: 'g6a-disandanyuanyuwenyuandi-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第三单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 6,
          term: '上册',
          unit: '第三单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 6,
          term: '上册',
          unit: '第三单元',
          title: '春日（日积月累）',
        ),
      ],
    ),

    // 第四单元
    PrimaryChineseLesson(grade: 6, term: '上册', unit: '第四单元', title: '桥',
      lessonId: 'g6a-qiao-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第四单元', title: '会认字\n咆 哮 狞 淌 呻 奠'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第四单元', title: '会写字\n咆 哮 疯 狞 淌 哑 呻 奠'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第四单元', title: '词语\n山洪 咆哮 狂奔 狞笑 拥戴 沙哑 呻吟 搀扶 祭奠 洪水 惊慌 放肆 吞没 塌败'),
      ],
    ),
    PrimaryChineseLesson(grade: 6, term: '上册', unit: '第四单元', title: '穷人',
      lessonId: 'g6a-qiongren-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第四单元', title: '会认字\n搁 魁 寡 蜷 忐 忑 黧 熬'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第四单元', title: '会写字\n汹 涌 澎 湃 熄 掀 唉 淋 糟 嘛 皱 勺'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第四单元', title: '词语\n渔夫 风暴 轰鸣 汹涌澎湃 沉思 抱怨 倾听 探望 照顾 阴冷 湿淋淋 渔网 糟糕 忧虑 搁板 魁梧 寡妇 蜷缩 黧黑'),
      ],
    ),
    PrimaryChineseLesson(grade: 6, term: '上册', unit: '第四单元', title: '金色的鱼钩',
      lessonId: 'g6a-jinsedeyugou-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第四单元', title: '会认字\n颧 鬓 稞 搪 胁 敛 疙 瘩 搀 噎 奄 瞻 锈 炊'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第四单元', title: '词语\n颧骨 两鬓 青稞 搪瓷 衰弱 宿营地 鱼饵 收敛 疙瘩 搀扶 抽噎 瞻仰 生锈 熬粥 保姆'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 6,
      term: '上册',
      unit: '第四单元',
      title: '语文园地四',
      lessonId: 'g6a-disidanyuanyuwenyuandi-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第四单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 6,
          term: '上册',
          unit: '第四单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 6,
          term: '上册',
          unit: '第四单元',
          title: '回乡偶书·其一（日积月累）',
        ),
      ],
    ),

    // 第五单元（习作单元）
    PrimaryChineseLesson(grade: 6, term: '上册', unit: '第五单元', title: '灯光',
      lessonId: 'g6a-dengguang-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第五单元', title: '会认字\n歼 钮 憧 憬 璀 璨 郝 魆 钧 皖'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第五单元', title: '词语\n漫步 照耀 宏伟 围歼 电钮 倚靠 微弱 暴露 牺牲 憧憬 璀璨 黑魆魆 豫皖苏平原'),
      ],
    ),
    PrimaryChineseLesson(grade: 6, term: '上册', unit: '第五单元', title: '盼',
      lessonId: 'g6a-pan-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第五单元', title: '会认字\n袖 筒 篷 缩 疯 瓦 柜 喧 甩 嚷 酱 唇 蹦 梯 瞟 囔 痱 窸 窣'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第五单元', title: '会写字\n袖 篷 缩 疯 瓦 柜 喧 甩 嚷 酱 唇 蹦 梯'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第五单元', title: '词语\n斗篷 袖筒 瓦蓝 衣柜 预报 喧闹 遮盖 逗引 酱油 嘴唇 楼梯 嘟囔 痱子 瞟一眼 玛瑙'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 6,
      term: '上册',
      unit: '第五单元',
      title: '习作例文与初试身手',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第五单元', title: '初试身手'),
        PrimaryChineseLesson(
          grade: 6,
          term: '上册',
          unit: '第五单元',
          title: '爸爸的计划（习作例文）',
      lessonId: 'g6a-liwenbabadejihua-dual',
        ),
        PrimaryChineseLesson(
          grade: 6,
          term: '上册',
          unit: '第五单元',
          title: '小站（习作例文）',
      lessonId: 'g6a-liwenxiaozhan-dual',
        ),
      ],
    ),

    // 第六单元
    PrimaryChineseLesson(
      grade: 6,
      term: '上册',
      unit: '第六单元',
      title: '古诗三首（浪淘沙·江南春·书湖阴先生壁）',
      lessonId: 'g6a-gushisanshou1langtaoshaqiyi-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第六单元', title: '会认字\n涯 簸 迢 郭 苔 畦 闼'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第六单元', title: '会写字\n涯 簸 苔 畦 闼 绕'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第六单元', title: '词语\n天涯 颠簸 城郭 青苔 菜畦 排闼 环绕 银河 酒旗 花木'),
      ],
    ),
    PrimaryChineseLesson(grade: 6, term: '上册', unit: '第六单元', title: '只有一个地球',
      lessonId: 'g6a-zhiyouyigediqiu-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第六单元', title: '会认字\n莹 裹 篮 蔼 资 矿 赐 慷 慨 滥 睹'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第六单元', title: '会写字\n莹 裹 篮 蔼 资 矿 赐 慷 慨 滥 睹'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第六单元', title: '词语\n晶莹 摇篮 壮观 和蔼 资源 矿产 恩赐 慷慨 枯竭 贡献 毁坏 滥用 威胁 目睹 包裹 渺小 破碎'),
      ],
    ),
    PrimaryChineseLesson(grade: 6, term: '上册', unit: '第六单元', title: '青山不老',
      lessonId: 'g6a-qingshanbulao-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第六单元', title: '会认字\n粼 虐 踞 淤 擎 锹 劲 拄 载'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第六单元', title: '词语\n肆虐 盘踞 绿洲 劲挺 淤泥 荡漾 记载 铁锹 拐杖 归宿 领悟 波光粼粼'),
      ],
    ),
    PrimaryChineseLesson(grade: 6, term: '上册', unit: '第六单元', title: '三黑和土地',
      lessonId: 'g6a-sanheihetudi-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第六单元', title: '会认字\n荞 耙 蹚 闺 蝈 茬'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第六单元', title: '词语\n土疙瘩 顺溜 松散 麦籽 荞麦 耙地 蹚坏 闺女 麦茬 白霎霎 痒抓抓 蝈蝈儿 翻身'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 6,
      term: '上册',
      unit: '第六单元',
      title: '语文园地六',
      lessonId: 'g6a-diliudanyuanyuwenyuandi-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第六单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 6,
          term: '上册',
          unit: '第六单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 6,
          term: '上册',
          unit: '第六单元',
          title: '传统常识五行五谷（日积月累）',
        ),
      ],
    ),

    // 第七单元
    PrimaryChineseLesson(
      grade: 6,
      term: '上册',
      unit: '第七单元',
      title: '文言文二则（两小儿辩日·曹冲称象）',
      lessonId: 'g6a-wenyanwenerze1liangxiaoerbianri-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第七单元', title: '会认字\n辩 盂 沧 汤 孰 汝 知 岐 致'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第七单元', title: '会写字\n辩 仓 聪 置 施'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第七单元', title: '词语\n辩斗 盘盂 沧沧凉凉 探汤 孰为汝多知乎 聪慧 巨象 水痕 施行 置象'),
      ],
    ),
    PrimaryChineseLesson(grade: 6, term: '上册', unit: '第七单元', title: '表里的生物',
      lessonId: 'g6a-biaolideshengwu-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第七单元', title: '会认字\n蝎 钵 蝈 蜇 恶 蟋 蟀'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第七单元', title: '会写字\n脆 拦 玻 璃 恶 怖 蟋 蟀'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第七单元', title: '词语\n机器 钟楼 街心 坚硬 玻璃 齿轮 单调 清脆 唯恐 丑恶 恐怖 证实 蝎子 钵子 蝈蝈 蜇人'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 6,
      term: '上册',
      unit: '第七单元',
      title: '他们那时候多有趣啊',
      lessonId: 'g6a-tamennashihouduoyouqua-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第七单元', title: '会认字\n鄙 屑 憎 恶 玛 荧 屏 调'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第七单元', title: '词语\n玛琪 托米 测验 装置 屏幕 调整 高傲 憎恶 荧光屏'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 6,
      term: '上册',
      unit: '第七单元',
      title: '语文园地七',
      lessonId: 'g6a-diqidanyuanyuwenyuandi-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第七单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 6,
          term: '上册',
          unit: '第七单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 6,
          term: '上册',
          unit: '第七单元',
          title: '高山流水艺术成语（日积月累）',
        ),
      ],
    ),

    // 第八单元
    PrimaryChineseLesson(grade: 6, term: '上册', unit: '第八单元', title: '少年闰土',
      lessonId: 'g6a-shaonianruntu-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第八单元', title: '会认字\n猹 弶 匾 秕 鸪 獾 毡 缚 猬 伶 俐 窜 汛'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第八单元', title: '会写字\n郑 拜 租 厨 毡 羞 撒 缚 猬 伶 俐 窜'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第八单元', title: '词语\n家景 郑重 祭祀 供品 讲究 厨房 毡帽 银项圈 怕羞 竹匾 秕谷 鹁鸪 獾猪 刺猬 束缚 伶俐 潮汛 沙土地'),
      ],
    ),
    PrimaryChineseLesson(grade: 6, term: '上册', unit: '第八单元', title: '好的故事',
      lessonId: 'g6a-haodegushi-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第八单元', title: '会认字\n搁 萍 藻 漾 瞬 凝 骤 掷'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第八单元', title: '会写字\n搁 萍 藻 漾 瞬 凝 掷 陡'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第八单元', title: '词语\n昏沉 搁置 萍藻 荡漾 瞬间 凝视 陡然 投掷 云锦 斑驳 闪烁 碎影 黑影'),
      ],
    ),
    PrimaryChineseLesson(grade: 6, term: '上册', unit: '第八单元', title: '我的伯父鲁迅先生',
      lessonId: 'g6a-wodebofuluxunxiansheng-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第八单元', title: '会认字\n殡 悼 唁 囫 囵 瀚 镊 硼 敷 佣 逝'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第八单元', title: '词语\n殡仪馆 追悼 吊唁 团聚 爱抚 失声痛哭 囫囵吞枣 张冠李戴 饱经风霜 镊子 硼酸水 敷药 女佣 深奥 咳嗽 枯瘦'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 6,
      term: '上册',
      unit: '第八单元',
      title: '有的人——纪念鲁迅有感',
      lessonId: 'g6a-youderen—jinianluxunyougan-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第八单元', title: '会认字\n朽 摔 垮 俯 铭 臧'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第八单元', title: '会写字\n朽 摔 垮 俯'),
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第八单元', title: '词语\n活着 不朽 摔垮 俯身 抬举 情愿 下场 名字 尸首'),
      ],
    ),
    PrimaryChineseLesson(
      grade: 6,
      term: '上册',
      unit: '第八单元',
      title: '语文园地八',
      lessonId: 'g6a-dibadanyuanyuwenyuandi-dual',
      subLessons: [
        PrimaryChineseLesson(grade: 6, term: '上册', unit: '第八单元', title: '交流平台'),
        PrimaryChineseLesson(
          grade: 6,
          term: '上册',
          unit: '第八单元',
          title: '词句段运用',
        ),
        PrimaryChineseLesson(
          grade: 6,
          term: '上册',
          unit: '第八单元',
          title: '鲁迅名言名句（日积月累）',
        ),
      ],
    ),

    // ==============================================================
    // 六年级下册 (统编版官方完整目次)
    // ==============================================================
    // 第一单元
    PrimaryChineseLesson(grade: 6, term: '下册', unit: '第一单元', title: '北京的春节'),
    PrimaryChineseLesson(grade: 6, term: '下册', unit: '第一单元', title: '腊八粥'),
    PrimaryChineseLesson(
      grade: 6,
      term: '下册',
      unit: '第一单元',
      title: '古诗三首（寒食·迢迢牵牛星·十五夜望月）',
    ),
    PrimaryChineseLesson(grade: 6, term: '下册', unit: '第一单元', title: '藏戏'),

    // 第二单元
    PrimaryChineseLesson(grade: 6, term: '下册', unit: '第二单元', title: '鲁滨逊漂流记'),
    PrimaryChineseLesson(grade: 6, term: '下册', unit: '第二单元', title: '骑鹅旅行记'),
    PrimaryChineseLesson(grade: 6, term: '下册', unit: '第二单元', title: '汤姆·索亚历险记'),

    // 第三单元
    PrimaryChineseLesson(grade: 6, term: '下册', unit: '第三单元', title: '匆匆'),
    PrimaryChineseLesson(grade: 6, term: '下册', unit: '第三单元', title: '那个星期天'),

    // 第四单元
    PrimaryChineseLesson(
      grade: 6,
      term: '下册',
      unit: '第四单元',
      title: '古诗三首（马诗·石灰吟·竹石）',
    ),
    PrimaryChineseLesson(grade: 6, term: '下册', unit: '第四单元', title: '十六年前的回忆'),
    PrimaryChineseLesson(grade: 6, term: '下册', unit: '第四单元', title: '为人民服务'),
    PrimaryChineseLesson(grade: 6, term: '下册', unit: '第四单元', title: '金色的鱼钩'),

    // 第五单元
    PrimaryChineseLesson(
      grade: 6,
      term: '下册',
      unit: '第五单元',
      title: '文言文二则（学弈·两小儿辩日）',
    ),
    PrimaryChineseLesson(
      grade: 6,
      term: '下册',
      unit: '第五单元',
      title: '真理诞生于一百个问号之后',
    ),
    PrimaryChineseLesson(grade: 6, term: '下册', unit: '第五单元', title: '表里的生物'),
    PrimaryChineseLesson(
      grade: 6,
      term: '下册',
      unit: '第五单元',
      title: '他们那时候多有趣啊',
    ),

    // 第六单元（综合性学习）
    PrimaryChineseLesson(
      grade: 6,
      term: '下册',
      unit: '第六单元（综合性学习）',
      title: '难忘小学生活',
    ),

    // ==============================================================
    // 七年级上册（统编版初中语文 · 全册六单元完整目录）
    // ==============================================================
    // 第一单元
    PrimaryChineseLesson(grade: 7, term: '上册', unit: '第一单元', title: '春'),
    PrimaryChineseLesson(grade: 7, term: '上册', unit: '第一单元', title: '济南的冬天'),
    PrimaryChineseLesson(grade: 7, term: '上册', unit: '第一单元', title: '雨的四季'),
    PrimaryChineseLesson(
      grade: 7,
      term: '上册',
      unit: '第一单元',
      title: '古代诗歌四首（观沧海·闻王昌龄左迁龙标遥有此寄·次北固山下·天净沙秋思）',
    ),
    PrimaryChineseLesson(
      grade: 7,
      term: '上册',
      unit: '第一单元',
      title: '单元综合与拓展一',
      subLessons: [
        PrimaryChineseLesson(
          grade: 7,
          term: '上册',
          unit: '第一单元',
          title: '写作：热爱生活，热爱写作',
        ),
      ],
    ),

    // 第二单元
    PrimaryChineseLesson(grade: 7, term: '上册', unit: '第二单元', title: '秋天的怀念'),
    PrimaryChineseLesson(grade: 7, term: '上册', unit: '第二单元', title: '散步'),
    PrimaryChineseLesson(
      grade: 7,
      term: '上册',
      unit: '第二单元',
      title: '散文诗二首（金色花·荷叶母亲）',
    ),
    PrimaryChineseLesson(
      grade: 7,
      term: '上册',
      unit: '第二单元',
      title: '《世说新语》二则（咏雪·陈太丘与友期行）',
      // 2026-10-20 初中样板课：文言实词作为「词语」子栏目
      // （沿用小学的字词表展开交互；逐词释义见 docs/design/7-9年级学段落地清单）
      subLessons: [
        PrimaryChineseLesson(
          grade: 7,
          term: '上册',
          unit: '第二单元',
          title: '词语\n'
              '期 约定（期行·期日中）\n'
              '舍 舍弃、丢下（太丘舍去）\n'
              '至 到（过中不至）\n'
              '顾 回头看（元方入门不顾）\n'
              '引 拉、牵拉（下车引之）\n'
              '信 讲信用（则是无信）\n'
              '委 丢下、舍弃（相委而去）\n'
              '君 对对方的尊称（君与家君）\n'
              '家君 对人称自己的父亲\n'
              '尊君 对别人父亲的尊称\n'
              '不 通「否」，表疑问（尊君在不）\n'
              '惭 感到惭愧（友人惭）',
        ),
      ],
    ),
    PrimaryChineseLesson(
      grade: 7,
      term: '上册',
      unit: '第二单元',
      title: '单元综合与拓展二',
      subLessons: [
        PrimaryChineseLesson(
          grade: 7,
          term: '上册',
          unit: '第二单元',
          title: '写作：学会记事',
        ),
        PrimaryChineseLesson(
          grade: 7,
          term: '上册',
          unit: '第二单元',
          title: '综合性学习：有朋自远方来',
        ),
      ],
    ),

    // 第三单元
    PrimaryChineseLesson(
      grade: 7,
      term: '上册',
      unit: '第三单元',
      title: '从百草园到三味书屋',
    ),
    PrimaryChineseLesson(grade: 7, term: '上册', unit: '第三单元', title: '往事依依'),
    PrimaryChineseLesson(grade: 7, term: '上册', unit: '第三单元', title: '再塑生命的人'),
    PrimaryChineseLesson(grade: 7, term: '上册', unit: '第三单元', title: '《论语》十二章'),
    PrimaryChineseLesson(
      grade: 7,
      term: '上册',
      unit: '第三单元',
      title: '单元综合与拓展三',
      subLessons: [
        PrimaryChineseLesson(
          grade: 7,
          term: '上册',
          unit: '第三单元',
          title: '写作：写人要抓住特点',
        ),
        PrimaryChineseLesson(
          grade: 7,
          term: '上册',
          unit: '第三单元',
          title: '名著导读：《朝花夕拾》——消除与经典的隔阂',
        ),
        PrimaryChineseLesson(
          grade: 7,
          term: '上册',
          unit: '第三单元',
          title: '课外古诗词诵读一（峨眉山月歌·江南逢李龟年·行军九日思长安故园·夜上受降城闻笛）',
        ),
      ],
    ),

    // 第四单元
    PrimaryChineseLesson(grade: 7, term: '上册', unit: '第四单元', title: '纪念白求恩'),
    PrimaryChineseLesson(grade: 7, term: '上册', unit: '第四单元', title: '回忆我的母亲'),
    PrimaryChineseLesson(grade: 7, term: '上册', unit: '第四单元', title: '梅岭三章'),
    PrimaryChineseLesson(grade: 7, term: '上册', unit: '第四单元', title: '诫子书'),
    PrimaryChineseLesson(
      grade: 7,
      term: '上册',
      unit: '第四单元',
      title: '单元综合与拓展四',
      subLessons: [
        PrimaryChineseLesson(
          grade: 7,
          term: '上册',
          unit: '第四单元',
          title: '写作：思路要清晰',
        ),
        PrimaryChineseLesson(
          grade: 7,
          term: '上册',
          unit: '第四单元',
          title: '综合性学习：少年正是读书时',
        ),
      ],
    ),

    // 第五单元
    PrimaryChineseLesson(grade: 7, term: '上册', unit: '第五单元', title: '猫'),
    PrimaryChineseLesson(grade: 7, term: '上册', unit: '第五单元', title: '我的白鸽'),
    PrimaryChineseLesson(grade: 7, term: '上册', unit: '第五单元', title: '大雁归来'),
    PrimaryChineseLesson(grade: 7, term: '上册', unit: '第五单元', title: '狼'),
    PrimaryChineseLesson(
      grade: 7,
      term: '上册',
      unit: '第五单元',
      title: '单元综合与拓展五',
      subLessons: [
        PrimaryChineseLesson(
          grade: 7,
          term: '上册',
          unit: '第五单元',
          title: '写作：如何突出中心',
        ),
      ],
    ),

    // 第六单元
    PrimaryChineseLesson(grade: 7, term: '上册', unit: '第六单元', title: '小圣施威降大圣'),
    PrimaryChineseLesson(grade: 7, term: '上册', unit: '第六单元', title: '皇帝的新装'),
    PrimaryChineseLesson(grade: 7, term: '上册', unit: '第六单元', title: '女娲造人'),
    PrimaryChineseLesson(
      grade: 7,
      term: '上册',
      unit: '第六单元',
      title: '寓言四则（赫耳墨斯和雕像者·蚊子和狮子·穿井得一人·杞人忧天）',
    ),
    PrimaryChineseLesson(
      grade: 7,
      term: '上册',
      unit: '第六单元',
      title: '单元综合与拓展六',
      subLessons: [
        PrimaryChineseLesson(
          grade: 7,
          term: '上册',
          unit: '第六单元',
          title: '写作：发挥联想和想象',
        ),
        PrimaryChineseLesson(
          grade: 7,
          term: '上册',
          unit: '第六单元',
          title: '名著导读：《西游记》——精读和跳读',
        ),
        PrimaryChineseLesson(
          grade: 7,
          term: '上册',
          unit: '第六单元',
          title: '课外古诗词诵读二（秋词·夜雨寄北·十一月四日风雨大作·潼关）',
        ),
      ],
    ),

    // ==============================================================
    // 七年级下册（统编版初中语文 · 全册六单元完整目录）
    // ==============================================================
    PrimaryChineseLesson(grade: 7, term: '下册', unit: '第一单元', title: '邓稼先'),
    PrimaryChineseLesson(
      grade: 7,
      term: '下册',
      unit: '第一单元',
      title: '说和做——记闻一多先生言行片段',
    ),
    PrimaryChineseLesson(grade: 7, term: '下册', unit: '第一单元', title: '列夫·托尔斯泰'),
    PrimaryChineseLesson(grade: 7, term: '下册', unit: '第一单元', title: '孙权劝学'),
    PrimaryChineseLesson(grade: 7, term: '下册', unit: '第二单元', title: '黄河颂'),
    PrimaryChineseLesson(grade: 7, term: '下册', unit: '第二单元', title: '老山界'),
    PrimaryChineseLesson(grade: 7, term: '下册', unit: '第二单元', title: '谁是最可爱的人'),
    PrimaryChineseLesson(grade: 7, term: '下册', unit: '第二单元', title: '土地的誓言'),
    PrimaryChineseLesson(grade: 7, term: '下册', unit: '第二单元', title: '木兰诗'),
    PrimaryChineseLesson(grade: 7, term: '下册', unit: '第三单元', title: '阿长与《山海经》'),
    PrimaryChineseLesson(grade: 7, term: '下册', unit: '第三单元', title: '山地回忆'),
    PrimaryChineseLesson(grade: 7, term: '下册', unit: '第三单元', title: '台阶'),
    PrimaryChineseLesson(grade: 7, term: '下册', unit: '第三单元', title: '卖油翁'),
    PrimaryChineseLesson(grade: 7, term: '下册', unit: '第四单元', title: '驿路梨花'),
    PrimaryChineseLesson(grade: 7, term: '下册', unit: '第四单元', title: '青春之光'),
    PrimaryChineseLesson(grade: 7, term: '下册', unit: '第四单元', title: '有为有不为'),
    PrimaryChineseLesson(
      grade: 7,
      term: '下册',
      unit: '第四单元',
      title: '短文两篇（陋室铭·爱莲说）',
    ),
    PrimaryChineseLesson(grade: 7, term: '下册', unit: '第五单元', title: '井冈翠竹'),
    PrimaryChineseLesson(grade: 7, term: '下册', unit: '第五单元', title: '紫藤萝瀑布'),
    PrimaryChineseLesson(
      grade: 7,
      term: '下册',
      unit: '第五单元',
      title: '外国诗二首（假如生活欺骗了你·未选择的路）',
    ),
    PrimaryChineseLesson(
      grade: 7,
      term: '下册',
      unit: '第五单元',
      title: '古代诗歌五首（登幽州台歌·望岳·登飞来峰·游山西村·己亥杂诗其五）',
    ),
    PrimaryChineseLesson(grade: 7, term: '下册', unit: '第六单元', title: '太空一日'),
    PrimaryChineseLesson(grade: 7, term: '下册', unit: '第六单元', title: '“蛟龙”探海'),
    PrimaryChineseLesson(grade: 7, term: '下册', unit: '第六单元', title: '带上她的眼睛'),
    PrimaryChineseLesson(grade: 7, term: '下册', unit: '第六单元', title: '活板'),

    // ==============================================================
    // 八年级上册（统编版初中语文 · 全册六单元完整目录）
    // ==============================================================
    // 第一单元
    PrimaryChineseLesson(
      grade: 8,
      term: '上册',
      unit: '第一单元',
      title: '消息二则（我三十万大军胜利南渡长江·人民解放军百万大军横渡长江）',
    ),
    PrimaryChineseLesson(
      grade: 8,
      term: '上册',
      unit: '第一单元',
      title: '中国人首次进入自己的空间站',
    ),
    PrimaryChineseLesson(grade: 8, term: '上册', unit: '第一单元', title: '首届诺贝尔奖颁发'),
    PrimaryChineseLesson(
      grade: 8,
      term: '上册',
      unit: '第一单元',
      title: '“飞天”凌空——跳水姑娘吕伟夺魁记',
    ),
    PrimaryChineseLesson(
      grade: 8,
      term: '上册',
      unit: '第一单元',
      title: '一着惊海天——目击我国第一艘航空母舰成功着舰',
    ),
    PrimaryChineseLesson(
      grade: 8,
      term: '上册',
      unit: '第一单元',
      title: '国行公祭，为佑世界和平',
    ),
    PrimaryChineseLesson(
      grade: 8,
      term: '上册',
      unit: '第一单元',
      title: '单元综合与拓展一',
      subLessons: [
        PrimaryChineseLesson(
          grade: 8,
          term: '上册',
          unit: '第一单元',
          title: '写作：新闻写作',
        ),
        PrimaryChineseLesson(
          grade: 8,
          term: '上册',
          unit: '第一单元',
          title: '口语交际：讲述',
        ),
      ],
    ),

    // 第二单元
    PrimaryChineseLesson(grade: 8, term: '上册', unit: '第二单元', title: '藤野先生'),
    PrimaryChineseLesson(
      grade: 8,
      term: '上册',
      unit: '第二单元',
      title: '回忆鲁迅先生（节选）',
    ),
    PrimaryChineseLesson(
      grade: 8,
      term: '上册',
      unit: '第二单元',
      title: '天上有颗“南仁东星”',
    ),
    PrimaryChineseLesson(grade: 8, term: '上册', unit: '第二单元', title: '美丽的颜色'),
    PrimaryChineseLesson(
      grade: 8,
      term: '上册',
      unit: '第二单元',
      title: '单元综合与拓展二',
      subLessons: [
        PrimaryChineseLesson(
          grade: 8,
          term: '上册',
          unit: '第二单元',
          title: '写作：学写传记',
        ),
        PrimaryChineseLesson(
          grade: 8,
          term: '上册',
          unit: '第二单元',
          title: '综合性学习：人无信不立',
        ),
      ],
    ),

    // 第三单元
    PrimaryChineseLesson(grade: 8, term: '上册', unit: '第三单元', title: '三峡'),
    PrimaryChineseLesson(
      grade: 8,
      term: '上册',
      unit: '第三单元',
      title: '短文两篇（答谢中书书·记承天寺夜游）',
    ),
    PrimaryChineseLesson(grade: 8, term: '上册', unit: '第三单元', title: '与朱元思书'),
    PrimaryChineseLesson(
      grade: 8,
      term: '上册',
      unit: '第三单元',
      title: '唐诗五首（野望·黄鹤楼·使至塞上·渡荆门送别·钱塘湖春行）',
    ),
    PrimaryChineseLesson(
      grade: 8,
      term: '上册',
      unit: '第三单元',
      title: '单元综合与拓展三',
      subLessons: [
        PrimaryChineseLesson(
          grade: 8,
          term: '上册',
          unit: '第三单元',
          title: '写作：学习描写景物',
        ),
        PrimaryChineseLesson(
          grade: 8,
          term: '上册',
          unit: '第三单元',
          title: '名著导读：《红星照耀中国》——纪实作品的阅读',
        ),
        PrimaryChineseLesson(
          grade: 8,
          term: '上册',
          unit: '第三单元',
          title: '课外古诗词诵读一（庭中有奇树·龟虽寿·赠从弟·梁甫行）',
        ),
      ],
    ),

    // 第四单元
    PrimaryChineseLesson(grade: 8, term: '上册', unit: '第四单元', title: '背影'),
    PrimaryChineseLesson(grade: 8, term: '上册', unit: '第四单元', title: '白杨礼赞'),
    PrimaryChineseLesson(
      grade: 8,
      term: '上册',
      unit: '第四单元',
      title: '散文二篇（永久的生命·我为什么而活着）',
    ),
    PrimaryChineseLesson(grade: 8, term: '上册', unit: '第四单元', title: '昆明的雨'),
    PrimaryChineseLesson(
      grade: 8,
      term: '上册',
      unit: '第四单元',
      title: '单元综合与拓展四',
      subLessons: [
        PrimaryChineseLesson(
          grade: 8,
          term: '上册',
          unit: '第四单元',
          title: '写作：语言要连贯',
        ),
        PrimaryChineseLesson(
          grade: 8,
          term: '上册',
          unit: '第四单元',
          title: '综合性学习：我们的互联网时代',
        ),
      ],
    ),

    // 第五单元
    PrimaryChineseLesson(grade: 8, term: '上册', unit: '第五单元', title: '中国石拱桥'),
    PrimaryChineseLesson(grade: 8, term: '上册', unit: '第五单元', title: '苏州园林'),
    PrimaryChineseLesson(
      grade: 8,
      term: '上册',
      unit: '第五单元',
      title: '人民英雄永垂不朽——瞻仰首都人民英雄纪念碑',
    ),
    PrimaryChineseLesson(grade: 8, term: '上册', unit: '第五单元', title: '梦回繁华'),
    PrimaryChineseLesson(
      grade: 8,
      term: '上册',
      unit: '第五单元',
      title: '单元综合与拓展五',
      subLessons: [
        PrimaryChineseLesson(
          grade: 8,
          term: '上册',
          unit: '第五单元',
          title: '写作：说明事物要抓住特征',
        ),
        PrimaryChineseLesson(
          grade: 8,
          term: '上册',
          unit: '第五单元',
          title: '口语交际：复述与转述',
        ),
      ],
    ),

    // 第六单元
    PrimaryChineseLesson(
      grade: 8,
      term: '上册',
      unit: '第六单元',
      title: '《孟子》三章（富贵不能淫·生于忧患，死于安乐·得道多助，失道寡助）',
    ),
    PrimaryChineseLesson(grade: 8, term: '上册', unit: '第六单元', title: '愚公移山'),
    PrimaryChineseLesson(grade: 8, term: '上册', unit: '第六单元', title: '周亚夫军细柳'),
    PrimaryChineseLesson(
      grade: 8,
      term: '上册',
      unit: '第六单元',
      title: '诗词五首（饮酒其五·春望·雁门太守行·赤壁·渔家傲天接云涛连晓雾）',
    ),
    PrimaryChineseLesson(
      grade: 8,
      term: '上册',
      unit: '第六单元',
      title: '单元综合与拓展六',
      subLessons: [
        PrimaryChineseLesson(
          grade: 8,
          term: '上册',
          unit: '第六单元',
          title: '写作：表达要得体',
        ),
        PrimaryChineseLesson(
          grade: 8,
          term: '上册',
          unit: '第六单元',
          title: '综合性学习：身边的文化遗产',
        ),
        PrimaryChineseLesson(
          grade: 8,
          term: '上册',
          unit: '第六单元',
          title: '名著导读：《昆虫记》——科普作品的阅读',
        ),
        PrimaryChineseLesson(
          grade: 8,
          term: '上册',
          unit: '第六单元',
          title: '课外古诗词诵读二（相见欢·浣溪沙·如梦令·采桑子）',
        ),
      ],
    ),

    // ==============================================================
    // 八年级下册（统编版初中语文 · 全册六单元完整目录）
    // ==============================================================
    PrimaryChineseLesson(grade: 8, term: '下册', unit: '第一单元', title: '社戏'),
    PrimaryChineseLesson(grade: 8, term: '下册', unit: '第一单元', title: '回延安'),
    PrimaryChineseLesson(grade: 8, term: '下册', unit: '第一单元', title: '安塞腰鼓'),
    PrimaryChineseLesson(grade: 8, term: '下册', unit: '第一单元', title: '灯笼'),
    PrimaryChineseLesson(grade: 8, term: '下册', unit: '第二单元', title: '大自然的语言'),
    PrimaryChineseLesson(
      grade: 8,
      term: '下册',
      unit: '第二单元',
      title: '阿西莫夫短文两篇（恐龙无处不有·被压扁的沙子）',
    ),
    PrimaryChineseLesson(grade: 8, term: '下册', unit: '第二单元', title: '大雁归来'),
    PrimaryChineseLesson(grade: 8, term: '下册', unit: '第二单元', title: '时间的脚印'),
    PrimaryChineseLesson(grade: 8, term: '下册', unit: '第三单元', title: '桃花源记'),
    PrimaryChineseLesson(grade: 8, term: '下册', unit: '第三单元', title: '小石潭记'),
    PrimaryChineseLesson(grade: 8, term: '下册', unit: '第三单元', title: '核舟记'),
    PrimaryChineseLesson(
      grade: 8,
      term: '下册',
      unit: '第三单元',
      title: '《诗经》二首（关雎·蒹葭）',
    ),
    PrimaryChineseLesson(grade: 8, term: '下册', unit: '第四单元', title: '最后一次讲演'),
    PrimaryChineseLesson(grade: 8, term: '下册', unit: '第四单元', title: '应有格物致知精神'),
    PrimaryChineseLesson(
      grade: 8,
      term: '下册',
      unit: '第四单元',
      title: '我一生中的重要抉择',
    ),
    PrimaryChineseLesson(
      grade: 8,
      term: '下册',
      unit: '第四单元',
      title: '庆祝奥林匹克运动复兴25周年',
    ),
    PrimaryChineseLesson(grade: 8, term: '下册', unit: '第五单元', title: '壶口瀑布'),
    PrimaryChineseLesson(
      grade: 8,
      term: '下册',
      unit: '第五单元',
      title: '在长江源头各拉丹冬',
    ),
    PrimaryChineseLesson(grade: 8, term: '下册', unit: '第五单元', title: '登勃朗峰'),
    PrimaryChineseLesson(grade: 8, term: '下册', unit: '第五单元', title: '一滴水经过丽江'),
    PrimaryChineseLesson(
      grade: 8,
      term: '下册',
      unit: '第六单元',
      title: '《庄子》二则（北冥有鱼·庄子与惠子游于濠梁之上）',
    ),
    PrimaryChineseLesson(
      grade: 8,
      term: '下册',
      unit: '第六单元',
      title: '《礼记》二则（虽有嘉肴·大道之行也）',
    ),
    PrimaryChineseLesson(grade: 8, term: '下册', unit: '第六单元', title: '马说'),
    PrimaryChineseLesson(
      grade: 8,
      term: '下册',
      unit: '第六单元',
      title: '唐诗三首（石壕吏·茅屋为秋风所破歌·卖炭翁）',
    ),

    // ==============================================================
    // 九年级上册（统编版初中语文 · 全册六单元完整目录）
    // ==============================================================
    // 第一单元
    PrimaryChineseLesson(grade: 9, term: '上册', unit: '第一单元', title: '沁园春·雪'),
    PrimaryChineseLesson(grade: 9, term: '上册', unit: '第一单元', title: '周总理，你在哪里'),
    PrimaryChineseLesson(grade: 9, term: '上册', unit: '第一单元', title: '我爱这土地'),
    PrimaryChineseLesson(grade: 9, term: '上册', unit: '第一单元', title: '乡愁'),
    PrimaryChineseLesson(
      grade: 9,
      term: '上册',
      unit: '第一单元',
      title: '你是人间的四月天——一句爱的赞颂',
    ),
    PrimaryChineseLesson(grade: 9, term: '上册', unit: '第一单元', title: '我看'),
    PrimaryChineseLesson(
      grade: 9,
      term: '上册',
      unit: '第一单元',
      title: '单元综合与拓展一',
      subLessons: [
        PrimaryChineseLesson(
          grade: 9,
          term: '上册',
          unit: '第一单元',
          title: '写作：尝试创作诗歌',
        ),
        PrimaryChineseLesson(
          grade: 9,
          term: '上册',
          unit: '第一单元',
          title: '活动·探究：诗歌朗诵与创作',
        ),
      ],
    ),

    // 第二单元
    PrimaryChineseLesson(grade: 9, term: '上册', unit: '第二单元', title: '敬业与乐业'),
    PrimaryChineseLesson(
      grade: 9,
      term: '上册',
      unit: '第二单元',
      title: '就英法联军远征中国致巴特勒上尉的信',
    ),
    PrimaryChineseLesson(grade: 9, term: '上册', unit: '第二单元', title: '论教养'),
    PrimaryChineseLesson(grade: 9, term: '上册', unit: '第二单元', title: '精神的三间小屋'),
    PrimaryChineseLesson(
      grade: 9,
      term: '上册',
      unit: '第二单元',
      title: '单元综合与拓展二',
      subLessons: [
        PrimaryChineseLesson(
          grade: 9,
          term: '上册',
          unit: '第二单元',
          title: '写作：观点要明确',
        ),
        PrimaryChineseLesson(
          grade: 9,
          term: '上册',
          unit: '第二单元',
          title: '综合性学习：君子自强不息',
        ),
      ],
    ),

    // 第三单元
    PrimaryChineseLesson(grade: 9, term: '上册', unit: '第三单元', title: '岳阳楼记'),
    PrimaryChineseLesson(grade: 9, term: '上册', unit: '第三单元', title: '醉翁亭记'),
    PrimaryChineseLesson(grade: 9, term: '上册', unit: '第三单元', title: '湖心亭看雪'),
    PrimaryChineseLesson(
      grade: 9,
      term: '上册',
      unit: '第三单元',
      title: '诗词三首（行路难其一·酬乐天扬州初逢席上见赠·水调歌头明月几时有）',
    ),
    PrimaryChineseLesson(
      grade: 9,
      term: '上册',
      unit: '第三单元',
      title: '单元综合与拓展三',
      subLessons: [
        PrimaryChineseLesson(
          grade: 9,
          term: '上册',
          unit: '第三单元',
          title: '写作：议论要言之有据',
        ),
        PrimaryChineseLesson(
          grade: 9,
          term: '上册',
          unit: '第三单元',
          title: '名著导读：《艾青诗选》——如何读诗',
        ),
        PrimaryChineseLesson(
          grade: 9,
          term: '上册',
          unit: '第三单元',
          title: '课外古诗词诵读一（月夜·商山早行·行香子·丑奴儿）',
        ),
      ],
    ),

    // 第四单元
    PrimaryChineseLesson(grade: 9, term: '上册', unit: '第四单元', title: '故乡'),
    PrimaryChineseLesson(grade: 9, term: '上册', unit: '第四单元', title: '我的叔叔于勒'),
    PrimaryChineseLesson(grade: 9, term: '上册', unit: '第四单元', title: '孤独之旅'),
    PrimaryChineseLesson(
      grade: 9,
      term: '上册',
      unit: '第四单元',
      title: '单元综合与拓展四',
      subLessons: [
        PrimaryChineseLesson(
          grade: 9,
          term: '上册',
          unit: '第四单元',
          title: '写作：学习缩写',
        ),
        PrimaryChineseLesson(
          grade: 9,
          term: '上册',
          unit: '第四单元',
          title: '综合性学习：走进小说天地',
        ),
      ],
    ),

    // 第五单元
    PrimaryChineseLesson(
      grade: 9,
      term: '上册',
      unit: '第五单元',
      title: '中国人失掉自信力了吗',
    ),
    PrimaryChineseLesson(grade: 9, term: '上册', unit: '第五单元', title: '怀疑与学问'),
    PrimaryChineseLesson(grade: 9, term: '上册', unit: '第五单元', title: '谈创造性思维'),
    PrimaryChineseLesson(grade: 9, term: '上册', unit: '第五单元', title: '创造宣言'),
    PrimaryChineseLesson(
      grade: 9,
      term: '上册',
      unit: '第五单元',
      title: '单元综合与拓展五',
      subLessons: [
        PrimaryChineseLesson(
          grade: 9,
          term: '上册',
          unit: '第五单元',
          title: '写作：论证要合理',
        ),
        PrimaryChineseLesson(
          grade: 9,
          term: '上册',
          unit: '第五单元',
          title: '口语交际：讨论',
        ),
      ],
    ),

    // 第六单元
    PrimaryChineseLesson(grade: 9, term: '上册', unit: '第六单元', title: '智取生辰纲'),
    PrimaryChineseLesson(grade: 9, term: '上册', unit: '第六单元', title: '范进中举'),
    PrimaryChineseLesson(grade: 9, term: '上册', unit: '第六单元', title: '三顾茅庐'),
    PrimaryChineseLesson(grade: 9, term: '上册', unit: '第六单元', title: '刘姥姥进大观园'),
    PrimaryChineseLesson(
      grade: 9,
      term: '上册',
      unit: '第六单元',
      title: '单元综合与拓展六',
      subLessons: [
        PrimaryChineseLesson(
          grade: 9,
          term: '上册',
          unit: '第六单元',
          title: '写作：学习改写',
        ),
        PrimaryChineseLesson(
          grade: 9,
          term: '上册',
          unit: '第六单元',
          title: '名著导读：《水浒传》——古典长篇白话小说',
        ),
        PrimaryChineseLesson(
          grade: 9,
          term: '上册',
          unit: '第六单元',
          title: '课外古诗词诵读二（从军行·送东阳马生序节选·武陵春·醉花阴）',
        ),
      ],
    ),

    // ==============================================================
    // 九年级下册（统编版初中语文 · 全册六单元完整目录）
    // ==============================================================
    PrimaryChineseLesson(
      grade: 9,
      term: '下册',
      unit: '第一单元',
      title: '祖国啊，我亲爱的祖国',
    ),
    PrimaryChineseLesson(grade: 9, term: '下册', unit: '第一单元', title: '梅岭三章'),
    PrimaryChineseLesson(
      grade: 9,
      term: '下册',
      unit: '第一单元',
      title: '短诗五首（月夜·萧红墓畔口占·断章·风雨·统一）',
    ),
    PrimaryChineseLesson(grade: 9, term: '下册', unit: '第一单元', title: '海燕'),
    PrimaryChineseLesson(grade: 9, term: '下册', unit: '第二单元', title: '孔乙己'),
    PrimaryChineseLesson(grade: 9, term: '下册', unit: '第二单元', title: '变色龙'),
    PrimaryChineseLesson(grade: 9, term: '下册', unit: '第二单元', title: '溜索'),
    PrimaryChineseLesson(grade: 9, term: '下册', unit: '第二单元', title: '蒲柳人家'),
    PrimaryChineseLesson(grade: 9, term: '下册', unit: '第三单元', title: '鱼我所欲也'),
    PrimaryChineseLesson(grade: 9, term: '下册', unit: '第三单元', title: '唐雎不辱使命'),
    PrimaryChineseLesson(grade: 9, term: '下册', unit: '第三单元', title: '送东阳马生序'),
    PrimaryChineseLesson(
      grade: 9,
      term: '下册',
      unit: '第三单元',
      title: '词四首（渔家傲秋思·江城子密州出猎·破阵子为陈同甫赋壮词以寄之·满江红小住京华）',
    ),
    PrimaryChineseLesson(
      grade: 9,
      term: '下册',
      unit: '第四单元',
      title: '短文两篇（谈读书·不求甚解）',
    ),
    PrimaryChineseLesson(grade: 9, term: '下册', unit: '第四单元', title: '山水画的意境'),
    PrimaryChineseLesson(grade: 9, term: '下册', unit: '第四单元', title: '无言之美'),
    PrimaryChineseLesson(grade: 9, term: '下册', unit: '第四单元', title: '驱遣我们的想象'),
    PrimaryChineseLesson(grade: 9, term: '下册', unit: '第四单元', title: '口语交际：辩论'),
    PrimaryChineseLesson(grade: 9, term: '下册', unit: '第五单元', title: '屈原（节选）'),
    PrimaryChineseLesson(
      grade: 9,
      term: '下册',
      unit: '第五单元',
      title: '天下第一楼（节选）',
    ),
    PrimaryChineseLesson(grade: 9, term: '下册', unit: '第五单元', title: '枣儿'),
    PrimaryChineseLesson(
      grade: 9,
      term: '下册',
      unit: '第五单元',
      title: '任务二：准备与排练',
    ),
    PrimaryChineseLesson(
      grade: 9,
      term: '下册',
      unit: '第五单元',
      title: '任务三：演出与评议',
    ),
    PrimaryChineseLesson(grade: 9, term: '下册', unit: '第六单元', title: '曹刿论战'),
    PrimaryChineseLesson(grade: 9, term: '下册', unit: '第六单元', title: '邹忌讽齐王纳谏'),
    PrimaryChineseLesson(grade: 9, term: '下册', unit: '第六单元', title: '陈涉世家'),
    PrimaryChineseLesson(grade: 9, term: '下册', unit: '第六单元', title: '出师表'),
    PrimaryChineseLesson(
      grade: 9,
      term: '下册',
      unit: '第六单元',
      title: '诗词五首（十五从军征·白雪歌送武判官归京·南乡子登京口北固亭有怀·过零丁洋·山坡羊潼关怀古）',
    ),
  ];

  /// Filter lessons by grade (1..6) and term ('上册' | '下册').
  static List<PrimaryChineseLesson> getLessons(int grade, String term) {
    return allLessons.where((l) => l.grade == grade && l.term == term).toList();
  }

  /// 按 lessonId 反查它所属的年级与册（含子栏目）。
  /// 精听页的「上一课 / 下一课」播放列表原先写死二年级上册，导致其他年级
  /// 切课失效；改由当前 lessonId 动态反查，一处修复全局生效。
  /// 找不到时返回 null，由调用方走 fallback。
  static ({int grade, String term})? locateGradeTerm(String? lessonId) {
    if (lessonId == null || lessonId.isEmpty) return null;
    for (final l in allLessons) {
      if (l.lessonId == lessonId) return (grade: l.grade, term: l.term);
      for (final sub in l.subLessons) {
        if (sub.lessonId == lessonId) return (grade: sub.grade, term: sub.term);
      }
    }
    return null;
  }

  /// Global search across all grades, terms, units, and titles (including subLessons).
  static List<PrimaryChineseLesson> search(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return const [];
    final List<PrimaryChineseLesson> results = [];
    for (final l in allLessons) {
      final matchesParent =
          l.title.toLowerCase().contains(clean) ||
          l.unit.toLowerCase().contains(clean) ||
          l.gradeLabel.contains(clean) ||
          '${l.grade}'.contains(clean) ||
          l.term.contains(clean) ||
          '${l.gradeLabel}${l.term}'.contains(clean);
      if (matchesParent) {
        results.add(l);
      }
      for (final sub in l.subLessons) {
        if (sub.title.toLowerCase().contains(clean) ||
            sub.displayTitle.toLowerCase().contains(clean)) {
          if (!results.contains(sub)) {
            results.add(sub);
          }
        }
      }
    }
    return results;
  }
}
