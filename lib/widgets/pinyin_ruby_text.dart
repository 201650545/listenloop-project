import 'package:flutter/material.dart';
import '../theme/listenloop_theme.dart';
import '../utils/chinese_pinyin.dart';

/// 小学语文课本注音排版组件（Ruby Annotation）：
/// - 每个汉字上方精准居中对齐对应声调拼音；
/// - 拼音字母紧密连贯（消除跨字体字形回退导致的字母断裂散开现象）；
/// - 标点符号顶部留白，与汉字基线严格对齐；
/// - 字号与字体跟随全局排版设置动态缩放。
class PinyinRubyText extends StatelessWidget {
  const PinyinRubyText({
    super.key,
    required this.text,
    this.charSize,
    this.charStyle,
    this.pinyinStyle,
    this.fontFamily,
    this.alignment = WrapAlignment.center,
    this.spacing = 6.0,
    this.runSpacing = 14.0,
  });

  /// 待注音展示的课文文本
  final String text;

  /// 汉字基准字号（未指定时根据 charStyle 或 28.0 决定）
  final double? charSize;

  /// 汉字文字样式（颜色、字重、字体等）
  final TextStyle? charStyle;

  /// 拼音文字样式（可选）
  final TextStyle? pinyinStyle;

  /// 中文字体家族
  final String? fontFamily;

  /// 整体换行对齐方式
  final WrapAlignment alignment;

  /// 汉字单元之间的水平间距
  final double spacing;

  /// 行与行之间的垂直间距
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final tokens = ChinesePinyin.format(text);
    if (tokens.isEmpty) return const SizedBox.shrink();

    // 1. 基准字号解析（跟随全局 textScale 缩放）
    final effectiveCharSize = charSize ?? charStyle?.fontSize ?? 28.0;
    // 拼音字号通常为汉字字号的 46%~48%，保证清晰可辨且不抢主视觉
    final effectivePinyinSize = (effectiveCharSize * 0.46).clamp(11.0, 22.0);

    // 2. 汉字样式
    final effectiveCharStyle = TextStyle(
      fontSize: effectiveCharSize,
      fontWeight: FontWeight.w600,
      fontFamily: fontFamily ?? charStyle?.fontFamily,
      color: charStyle?.color ?? ll.textPrimary,
      height: 1.15,
    );

    // 3. 拼音样式：严格消除 letterSpacing，使用统一 CJK 字体家族回退，
    // 确保声母、韵母、声调全部在同一个字形体系中渲染，紧密相连绝不断开。
    final effectivePinyinStyle = TextStyle(
      fontSize: effectivePinyinSize,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.0, // 严禁正间距，保持拼音字母紧贴
      fontFamily: fontFamily ?? 'sans-serif',
      fontFamilyFallback: const [
        'Noto Sans CJK SC',
        'Source Han Sans CN',
        'Droid Sans Fallback',
        'sans-serif',
      ],
      color: pinyinStyle?.color ?? ll.textSecondary,
      height: 1.1,
    );

    // 拼音区域固定行高，确保带拼音汉字与不带拼音标点的垂直基线绝对水平对齐
    final pinyinHeight = effectivePinyinSize * 1.25;

    return Wrap(
      alignment: alignment,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: spacing,
      runSpacing: runSpacing,
      children: tokens.map((token) {
        final hasPinyin = token.pinyin != null && token.pinyin!.isNotEmpty;
        final isPunctuation = !hasPinyin;

        return _RubyCell(
          token: token,
          hasPinyin: hasPinyin,
          isPunctuation: isPunctuation,
          charStyle: effectiveCharStyle,
          pinyinStyle: effectivePinyinStyle,
          charSize: effectiveCharSize,
          pinyinHeight: pinyinHeight,
        );
      }).toList(),
    );
  }
}

class _RubyCell extends StatelessWidget {
  const _RubyCell({
    required this.token,
    required this.hasPinyin,
    required this.isPunctuation,
    required this.charStyle,
    required this.pinyinStyle,
    required this.charSize,
    required this.pinyinHeight,
  });

  final PinyinRubyToken token;
  final bool hasPinyin;
  final bool isPunctuation;
  final TextStyle charStyle;
  final TextStyle pinyinStyle;
  final double charSize;
  final double pinyinHeight;

  @override
  Widget build(BuildContext context) {
    if (isPunctuation) {
      // 标点符号：上方保留与拼音完全等高的透明占位块，确保前后汉字基线对齐
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: pinyinHeight),
          const SizedBox(height: 2.0),
          Text(
            token.char,
            style: charStyle,
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    // 汉字+拼音单元：
    // 汉字是方块字，最小宽度为 charSize。
    // 拼音在汉字正上方居中，汉字在下方居中，整体对称。
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: charSize),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: pinyinHeight,
            child: Center(
              child: Text(
                token.pinyin!,
                style: pinyinStyle,
                textAlign: TextAlign.center,
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
          const SizedBox(height: 2.0),
          Center(
            child: Text(
              token.char,
              style: charStyle,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
