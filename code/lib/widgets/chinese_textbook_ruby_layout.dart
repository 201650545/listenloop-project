import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/listenloop_theme.dart';
import '../utils/chinese_pinyin.dart';

enum RubyCharStatus {
  unread,
  correct,
  wrong,
}

/// 小学语文课本级拼音汉字行行相间排版组件 (Chinese Textbook Ruby Layout)
/// ---------------------------------------------------------------------------
/// 严格还原统编版小学语文课本官方印刷排版：
/// 1. 拼音字体采用官方教材标准规范拼音字母（Roboto / 标准拉丁），声调清晰饱满；
/// 2. 彻底杜绝顶部截断遮挡：给声调预留充足空间，overflow 设为 visible，字母 100% 完整显示；
/// 3. 【连续后鼻音断开写】（2026-10-20 郭老师新规）：
///    韵母为 ang/eng/ing/ong 的音节连续出现时（「长长」「长成青」），相邻
///    音节之间的**视觉间距**要比正常标准间距再宽 1/4 —— 否则 cháng cháng
///    连成一团，孩子会读成一个词。视觉间距 = 格间距 + 拼音左留白 + 右留白；
///    长拼音（chuáng）撑满格子、左右几乎无留白，所以只加格间距是不够的。
/// 4. 每个汉字与其对应拼音同轴垂直居中对齐，标点符号顶端留空；
/// 5. 换行时严格交替呈现：第一行拼音 -> 第一行汉字 -> 第二行拼音 -> 第二行汉字；
/// 6. 随全局字号设置 (textScale) 实时动态缩放。
class ChineseTextbookRubyLayout extends StatelessWidget {
  const ChineseTextbookRubyLayout({
    super.key,
    required this.text,
    this.charSize,
    this.charStyle,
    this.chineseFontFamily,
    this.textAlign = TextAlign.center,
    this.wordSpacing = 6.0,
    this.lineSpacing = 16.0,
    this.pinyinRatio = 0.52,
    this.pinyinScale = 1.0,
    this.activeCharIndex,
    this.charStatuses,
    this.highlightColor,
    this.unplayedColor,
    this.pinyinHighlightColor,
    this.pinyinUnplayedColor,
  });

  /// 课文句子内容
  final String text;

  /// 汉字基准字号（默认 28.0，随全局 textScale 缩放）
  final double? charSize;

  /// 汉字基础样式
  final TextStyle? charStyle;

  /// 中文字体（宋体 / 仿宋 / 系统）
  final String? chineseFontFamily;

  /// 整体居中或居左对齐
  final TextAlign textAlign;

  /// 字与字之间的基础水平间距
  final double wordSpacing;

  /// 行与行之间的垂直呼吸间距
  final double lineSpacing;

  /// 拼音相对于汉字的字号比例（默认 0.52，即 52%）
  final double pinyinRatio;

  /// 拼音大小的**独立**倍率（2026-10-20 郭老师：字体控制再加一个拼音大小）。
  ///
  /// 1.0 = 跟随上面的比例；0.8 = 拼音小一点（低年级刚开始学拼）；1.25 = 拼音
  /// 大一点（看得清声调）。它只改拼音，不动汉字。
  final double pinyinScale;

  /// 随音逐字高亮：当前读到的字符索引（>= 该索引的为未读，< 该索引的为已读/高亮）。
  /// 为 null 时表示常规排版渲染。
  final int? activeCharIndex;

  /// 朗读评测单字状态（绿=读对，红=读错，未读=浅墨色）
  final Map<int, RubyCharStatus>? charStatuses;

  /// 已读/高亮状态的汉字颜色（默认采用 [charStyle?.color] 或 [ll.textPrimary]）
  final Color? highlightColor;

  /// 未读状态的汉字颜色（默认采用未激活浅灰色）
  final Color? unplayedColor;

  /// 已读/高亮状态的拼音颜色（默认与高亮汉字一致或为 [ll.textPrimary]）
  final Color? pinyinHighlightColor;

  /// 未读状态的拼音颜色（默认采用未激活浅灰色）
  final Color? pinyinUnplayedColor;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    final ll = context.ll;
    final tokens = ChinesePinyin.format(text);
    if (tokens.isEmpty) return const SizedBox.shrink();

    final effectiveCharSize = charSize ?? charStyle?.fontSize ?? 28.0;
    final scaleRatio = (effectiveCharSize / 28.0).clamp(0.2, 2.0);
    // 拼音基准字号默认提升为汉字的 52%（从 44% 优化至 52%，解决声调偏小、看不太清问题），真实等比缩放
    final effectivePinyinRatio = pinyinRatio.clamp(0.35, 0.70);
    final basePinyinSize =
        (effectiveCharSize * effectivePinyinRatio * pinyinScale.clamp(0.6, 1.6))
            .clamp(3.5, 36.0);

    // 2026-10-20 郭老师（听页「字挨字、没有呼吸感」的真正病根）：
    //
    // **系统字号缩放**（这台小米是 1.45）会放大所有 Text，但**放不大
    // SizedBox**。这个组件原来用 TextPainter 量宽（TextPainter 默认不套
    // MediaQuery 的 textScaler），量到的是"缩放前"的宽度；真正渲染时每个
    // 字都比量出来的大 45% → 全部溢出格子 → 格子之间的间距被字盖光 →
    // 看上去就是"一个字挨着一个字"。
    //
    // 修法：① 测量时带上同一个 textScaler（量到的就是真宽度）；② 间距、
    // 缓冲、拼音行高这些**不会**被缩放的量，自己乘上缩放系数。
    final textScaler = MediaQuery.textScalerOf(context);
    final scalerFactor = textScaler.scale(28) / 28;

    final effectiveWordSpacing = wordSpacing * scaleRatio * scalerFactor;
    final effectiveLineSpacing = lineSpacing * scaleRatio * scalerFactor;

    // 1. 汉字样式（跟随用户选择的 宋体/仿宋/系统 字体）
    final effectiveCharStyle = TextStyle(
      fontSize: effectiveCharSize,
      fontWeight: FontWeight.w600,
      fontFamily: chineseFontFamily ?? charStyle?.fontFamily,
      color: charStyle?.color ?? ll.textPrimary,
      height: 1.15,
    );

    // 指读跟随色彩阶梯：
    final effectiveHighlightColor = highlightColor ?? charStyle?.color ?? ll.textPrimary;
    final effectiveUnplayedColor = unplayedColor ??
        (charStyle?.color != null
            ? charStyle!.color!.withValues(alpha: 0.35)
            : ll.textTertiary);
    final effectivePinyinHighlightColor = pinyinHighlightColor ?? effectiveHighlightColor;
    final effectivePinyinUnplayedColor = pinyinUnplayedColor ?? effectiveUnplayedColor;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 32;

        // 2. 测量每个单元格的宽度 (Cell width) 并注入自适应长拼音样式
        final cellList = <_RubyCellData>[];
        for (int i = 0; i < tokens.length; i++) {
          final token = tokens[i];
          final pinyinStr = token.pinyin ?? '';
          final hasPinyin = pinyinStr.isNotEmpty;

          // 动态长拼音字号计算：遇到 5~6 字母的长拼音（后鼻音等）适度微缩，避免过长
          final pinyinSize = _resolvePinyinSize(pinyinStr, basePinyinSize);
          final effectivePinyinFont = chineseFontFamily ?? 'SongTi';

          // 状态判定：若传入了 charStatuses 则优先按红绿评测状态上色，否则回退指读模式
          final RubyCharStatus? status = charStatuses?[i];
          final Color cellCharColor;
          final Color cellPinyinColor;

          if (charStatuses != null) {
            switch (status ?? RubyCharStatus.unread) {
              case RubyCharStatus.correct:
                // 2026-10-20（评审 P1）：写死的红绿换成语义令牌 —— 四套风格
                // 的色板里都有 success / danger，用它们才不会在别的风格里
                // 冒出"外来色"。
                cellCharColor = ll.success;
                cellPinyinColor = ll.success;
              case RubyCharStatus.wrong:
                cellCharColor = ll.danger;
                cellPinyinColor = ll.danger;
              case RubyCharStatus.unread:
                cellCharColor = unplayedColor ?? ll.textTertiary;
                cellPinyinColor = pinyinUnplayedColor ?? ll.textTertiary;
            }
          } else {
            // 指读跟随模式：判断当前字是否已被朗读到
            final isPlayed = activeCharIndex != null && i < activeCharIndex!;
            cellCharColor = activeCharIndex == null
                ? (charStyle?.color ?? ll.textPrimary)
                : (isPlayed ? effectiveHighlightColor : effectiveUnplayedColor);
            // 2026-10-20：未读拼音用二级灰（原先三级灰太淡，拼音像"飘"在汉字上方，
            // 失去与汉字成组的感觉）
            cellPinyinColor = activeCharIndex == null
                ? ll.textSecondary
                : (isPlayed ? effectivePinyinHighlightColor : (pinyinUnplayedColor ?? ll.textSecondary));
          }

          final pinyinStyle = TextStyle(
            fontSize: pinyinSize,
            fontWeight: FontWeight.w400,
            fontFamily: effectivePinyinFont,
            fontFamilyFallback: const [
              'SongTi',
              'FangSong',
              'Noto Sans',
              'Source Han Sans CN',
              'sans-serif',
            ],
            color: cellPinyinColor,
            letterSpacing: 0.1,
            height: 1.35, // 充足行高，彻底留出顶部声调空间，杜绝遮挡
          );

          final cellCharStyle = effectiveCharStyle.copyWith(
            color: cellCharColor,
          );

          double pWidth = 0.0;
          if (hasPinyin) {
            final pPainter = TextPainter(
              text: TextSpan(text: pinyinStr, style: pinyinStyle),
              textDirection: TextDirection.ltr,
              // 关键：量宽必须带上系统缩放，否则量到的是缩放前的宽度，
              // 渲染时字会撑出格子、间距被吃光（见上方说明）。
              textScaler: textScaler,
            )..layout();
            pWidth = pPainter.width;
          }

          final cPainter = TextPainter(
            text: TextSpan(text: token.char, style: effectiveCharStyle),
            textDirection: TextDirection.ltr,
            textScaler: textScaler,
          )..layout();
          final cWidth = cPainter.width;

          // 每个字的容器宽度：取汉字与拼音宽度的最大值，并增加安全呼吸缓冲（等比随字号微缩）
          final buffer = (5.0 * scaleRatio * scalerFactor).clamp(1.0, 12.0);
          final cellWidth = hasPinyin
              ? math.max(cWidth, pWidth) + buffer
              : cWidth;

          cellList.add(_RubyCellData(
            token: token,
            width: cellWidth,
            hasPinyin: hasPinyin,
            pinyinStyle: pinyinStyle,
            charStyle: cellCharStyle,
            globalIndex: i,
            pinyinWidth: pWidth,
            // 拼音在本格里的左右留白：短拼音居中（两边各半），长拼音左对齐
            // （空隙全在右边）。视觉间距 = 格间距 + 左边留白 + 右边留白。
            overhangLeft: hasPinyin
                ? (isLongPinyinOf(pinyinStr)
                    ? 0.0
                    : (cellWidth - pWidth) / 2)
                : 0.0,
            overhangRight: hasPinyin
                ? (isLongPinyinOf(pinyinStr)
                    ? (cellWidth - pWidth)
                    : (cellWidth - pWidth) / 2)
                : 0.0,
            isNasalFinal: hasPinyin && isNasalFinalPinyin(pinyinStr),
          ));
        }

        // 3. 换行断点计算
        //
        // 2026-10-20 郭老师（拼音新规）：**连续后鼻音**（ang/eng/ing/ong）
        // 的音节之间要"断开写"——cháng cháng 若连成一团，孩子会读成一个词。
        // 规矩是：这类相邻对的**视觉间距**要比正常标准间距再宽 1/4。
        //
        // 为什么不能只看"格间距"：长拼音（chuáng）比汉字宽，格子被拼音撑满，
        // 它左右几乎没有留白，所以同样大小的格间距，长拼音之间的**视觉**
        // 间距反而比短拼音小 —— 看着仍然像连着写。所以这里算的是
        // 「视觉间距 = 格间距 + 左留白 + 右留白」，再按规矩加宽。
        final lines = <_RubyLine>[];
        var currentLine = <_RubyCellData>[];
        var currentGaps = <double>[];
        double currentLineWidth = 0.0;
        // 本行「正常标准视觉间距」的滚动均值（只统计非后鼻音对）。
        double normalVisualSum = 0.0;
        int normalVisualCount = 0;

        for (int i = 0; i < cellList.length; i++) {
          final cell = cellList[i];
          var gap = 0.0;
          if (currentLine.isNotEmpty) {
            final prev = currentLine.last;
            final pairVisual =
                effectiveWordSpacing + prev.overhangRight + cell.overhangLeft;
            final bothNasal = prev.isNasalFinal && cell.isNasalFinal;
            if (!bothNasal && prev.hasPinyin && cell.hasPinyin) {
              normalVisualSum += pairVisual;
              normalVisualCount++;
            }
            final reference = normalVisualCount > 0
                ? normalVisualSum / normalVisualCount
                : effectiveWordSpacing * 1.25;
            final desired = bothNasal ? reference * 1.25 : pairVisual;
            gap = desired - prev.overhangRight - cell.overhangLeft;
          }
          final addedWidth = gap + cell.width;

          if (currentLine.isNotEmpty && currentLineWidth + addedWidth > availableWidth) {
            lines.add(_RubyLine(cells: currentLine, gaps: currentGaps));
            currentLine = [cell];
            currentGaps = <double>[];
            currentLineWidth = cell.width;
            normalVisualSum = 0.0;
            normalVisualCount = 0;
          } else {
            if (currentLine.isNotEmpty) currentGaps.add(gap);
            currentLine.add(cell);
            currentLineWidth += addedWidth;
          }
        }
        if (currentLine.isNotEmpty) {
          lines.add(_RubyLine(cells: currentLine, gaps: currentGaps));
        }

        // 4. 逐行渲染：拼音行 -> 汉字行 -> 下一行拼音行 -> 下一行汉字行
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: textAlign == TextAlign.center
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            for (int lineIdx = 0; lineIdx < lines.length; lineIdx++) ...[
              if (lineIdx > 0) SizedBox(height: effectiveLineSpacing),
              _buildSingleLine(
                line: lines[lineIdx],
                charStyle: effectiveCharStyle,
                // 拼音行高同样不会被系统缩放放大 → 自己乘上缩放系数。
                pinyinMinHeight: basePinyinSize * 1.22 * scalerFactor,
                textAlign: textAlign,
              ),
            ],
          ],
        );
      },
    );
  }

  /// 长拼音判定（字母数 >= 4）：左对齐排版。
  static bool isLongPinyinOf(String pinyin) => pinyin.length >= 4;

  /// 后鼻音判定（2026-10-20 郭老师拼音新规）。
  ///
  /// 韵母为 ang / eng / ing / ong 的音节算后鼻音：cháng、zhǎng、qīng、
  /// dōng …… 连续出现时（「长长」「长成青」），相邻两个音节之间要断开写。
  ///
  /// 判定前先去掉声调符号：拼音声调是带音调的字母（cháng 的 á），
  /// 不还原就没法看韵母。
  static bool isNasalFinalPinyin(String pinyin) {
    if (pinyin.isEmpty) return false;
    final plain = _stripToneMarks(pinyin.toLowerCase());
    return plain.endsWith('ang') ||
        plain.endsWith('eng') ||
        plain.endsWith('ing') ||
        plain.endsWith('ong');
  }

  /// 去掉拼音声调符号，还原成基础字母。
  static String _stripToneMarks(String s) {
    const map = <String, String>{
      'á': 'a', 'à': 'a', 'ǎ': 'a', 'â': 'a', 'ā': 'a', 'a': 'a',
      'é': 'e', 'è': 'e', 'ě': 'e', 'ê': 'e', 'ē': 'e', 'e': 'e',
      'í': 'i', 'ì': 'i', 'ǐ': 'i', 'î': 'i', 'ī': 'i', 'i': 'i',
      'ó': 'o', 'ò': 'o', 'ǒ': 'o', 'ô': 'o', 'ō': 'o', 'o': 'o',
      'ú': 'u', 'ù': 'u', 'ǔ': 'u', 'û': 'u', 'ū': 'u', 'u': 'u',
      'ǖ': 'u', 'ǘ': 'u', 'ǚ': 'u', 'ǜ': 'u', 'ü': 'u',
      'ń': 'n', 'ň': 'n', 'ǹ': 'n', 'n': 'n',
      'ḿ': 'm', 'm̄': 'm', 'm': 'm',
    };
    final buf = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      buf.write(map[ch] ?? ch);
    }
    return buf.toString();
  }

  /// 计算单个拼音的自适应字号（后鼻音等超长拼音适度微缩）
  static double _resolvePinyinSize(String pinyin, double baseSize) {
    final len = pinyin.length;
    if (len >= 6) {
      // 6 字母：例如 zhuāng, chuáng，微缩至 88%
      return (baseSize * 0.88).clamp(3.5, 30.0);
    } else if (len == 5) {
      // 5 字母：例如 zhǎng, chéng, liàng，微缩至 91%
      return (baseSize * 0.91).clamp(3.8, 30.0);
    } else if (len == 4) {
      // 4 字母：例如 qīng, biān, kuài，微缩至 96%
      return (baseSize * 0.96).clamp(4.0, 30.0);
    }
    return baseSize;
  }

  /// 渲染单行：上行拼音、下行汉字，每个字同轴对齐
  Widget _buildSingleLine({
    required _RubyLine line,
    required TextStyle charStyle,
    required double pinyinMinHeight,
    required TextAlign textAlign,
  }) {
    final lineCells = line.cells;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: textAlign == TextAlign.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        // 1. 该行的拼音行（间距在断行时已算好，overflow 为 visible 绝不丢字）
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (int i = 0; i < lineCells.length; i++) ...[
              if (i > 0) SizedBox(width: line.gaps[i - 1]),
              SizedBox(
                width: lineCells[i].width,
                child: lineCells[i].hasPinyin
                    ? Container(
                        constraints: BoxConstraints(minHeight: pinyinMinHeight),
                        alignment: lineCells[i].isLongPinyin
                            ? Alignment.bottomLeft
                            : Alignment.bottomCenter,
                        child: Text(
                          lineCells[i].token.pinyin!,
                          style: lineCells[i].pinyinStyle,
                          textAlign: lineCells[i].isLongPinyin
                              ? TextAlign.left
                              : TextAlign.center,
                          softWrap: false,
                          overflow: TextOverflow.visible, // 绝不裁切任何字母
                        ),
                      )
                    : SizedBox(height: pinyinMinHeight), // 标点符号上方留白
              ),
            ],
          ],
        ),

        const SizedBox(height: 0), // 拼音与汉字紧贴成组（2026-10-20：原先 2px 显得松散飘着）

        // 2. 该行的汉字行（长拼音汉字左边缘齐平，短拼音汉字同轴居中）
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            for (int i = 0; i < lineCells.length; i++) ...[
              if (i > 0) SizedBox(width: line.gaps[i - 1]),
              SizedBox(
                width: lineCells[i].width,
                child: Text(
                  lineCells[i].token.char,
                  style: lineCells[i].charStyle,
                  textAlign: lineCells[i].isLongPinyin
                      ? TextAlign.left
                      : TextAlign.center,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// 一行：格子 + 格子之间的间距（断行时算好，渲染时直接用）。
class _RubyLine {
  const _RubyLine({required this.cells, required this.gaps});

  final List<_RubyCellData> cells;

  /// gaps[i] 是 cells[i] 与 cells[i+1] 之间的间距。
  final List<double> gaps;
}

class _RubyCellData {
  const _RubyCellData({
    required this.token,
    required this.width,
    required this.hasPinyin,
    required this.pinyinStyle,
    required this.charStyle,
    required this.globalIndex,
    this.pinyinWidth = 0.0,
    this.overhangLeft = 0.0,
    this.overhangRight = 0.0,
    this.isNasalFinal = false,
  });

  final PinyinRubyToken token;
  final double width;
  final bool hasPinyin;
  final TextStyle pinyinStyle;
  final TextStyle charStyle;
  final int globalIndex;

  /// 拼音本身的宽度。
  final double pinyinWidth;

  /// 拼音在本格里左侧的空隙（长拼音左对齐 → 0）。
  final double overhangLeft;

  /// 拼音在本格里右侧的空隙。
  final double overhangRight;

  /// 该音节是否是后鼻音（ang/eng/ing/ong）。
  final bool isNasalFinal;

  /// 用户新定排版规则：拼音字母数 >= 4 为长拼音（左对齐），< 4 为短拼音（居中对齐）
  bool get isLongPinyin => (token.pinyin?.length ?? 0) >= 4;
}
