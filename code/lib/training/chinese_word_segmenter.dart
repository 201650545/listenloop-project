import '../utils/chinese_pinyin.dart';
import 'read_along_session.dart';

/// 课文词语单元（用于跟读评测以“词语”为判定单位）
class ChineseWord {
  const ChineseWord({
    required this.word,
    required this.pinyinList,
    required this.charIndices,
  });

  /// 词语汉字文本（如“小蝌蚪”、“找”、“妈妈”）
  final String word;

  /// 带调拼音列表（如 ["xiǎo", "kē", "dǒu"]）
  final List<String> pinyinList;

  /// 在原句中的字符绝对索引列表（如 [0, 1, 2]）
  final List<int> charIndices;

  /// 无调拼音列表（用于 ASR 容错比对）
  List<String> get tonelessPinyins =>
      pinyinList.map(ReadAlongSession.stripTones).toList(growable: false);

  /// 声母韵母慢速拼读示范口播文本（例如：“zh， ǎo， zhǎo， 找”）
  String get spellingSpeech {
    final sb = <String>[];
    for (var i = 0; i < word.length; i++) {
      final ch = word[i];
      final py = i < pinyinList.length ? pinyinList[i] : '';
      if (py.isEmpty) continue;
      final (initial, finalPart) = ChineseWordSegmenter.decomposePinyin(py);
      if (initial.isNotEmpty) {
        sb.add('$initial， $finalPart， $py， $ch');
      } else {
        sb.add('$py， $ch');
      }
    }
    return sb.join('； ');
  }

  @override
  String toString() => '$word($pinyinList)';
}

/// 统编版语文课文词语切分器与拼音拼读分解器
class ChineseWordSegmenter {
  const ChineseWordSegmenter._();

  static const List<String> _initials = [
    'zh', 'ch', 'sh',
    'b', 'p', 'm', 'f', 'd', 't', 'n', 'l',
    'g', 'k', 'h', 'j', 'q', 'x',
    'r', 'z', 'c', 's', 'y', 'w',
  ];

  /// 将带调音节分解为 (声母, 韵母)
  static (String initial, String finalPart) decomposePinyin(String pinyin) {
    if (pinyin.isEmpty) return ('', '');
    final toneless = ReadAlongSession.stripTones(pinyin).toLowerCase();
    for (final ini in _initials) {
      if (toneless.startsWith(ini)) {
        final finalPart = pinyin.substring(ini.length);
        return (ini, finalPart);
      }
    }
    return ('', pinyin);
  }

  /// 常见小学课文高频词汇表（优先贪婪匹配 2~4 字词，其余单字成词）
  static final Set<String> _commonTextbookWords = {
    // 课文1 小蝌蚪找妈妈
    '池塘', '一群', '小蝌蚪', '大大', '脑袋', '黑灰色', '身子', '甩着', '长长', '尾巴',
    '快活', '游来游去', '游哇游', '过了', '几天', '长出', '两条', '后腿', '前腿',
    '看见', '鲤鱼', '阿姨', '妈妈', '哪里', '宽嘴巴', '乌龟', '摆动', '连忙',
    '追上去', '笑着', '头顶', '眼睛', '披着', '绿衣裳', '雪白', '肚皮', '鼓着',
    '青蛙', '碧绿', '低头', '孩子', '跳上', '害虫',
    // 课文2 我是什么
    '我会变', '太阳', '极小', '点儿', '连成一片', '飘浮', '衣服', '有时候', '傍晚',
    '红袍', '温和', '暴躁', '灌溉', '田地', '发动', '机器', '淹没', '庄稼', '冲毁',
    // 课文3 植物妈妈有办法
    '植物', '办法', '旅行', '蒲公英', '降落伞', '乘着', '纷纷', '出发', '苍耳',
    '铠甲', '挂住', '动物', '皮毛', '豌豆', '晒得', '啪的一声', '炸开',
    // 识字与通用词
    '天地', '人们', '上下', '金木水火土', '日月', '水火', '山石', '田土', '云雾',
    '风雨', '花鸟', '虫鱼', '清秀', '秀丽', '奇石', '巨石', '神奇', '金光闪闪',
    '群山', '环绕', '树木', '茂盛', '名胜古迹', '点点', '灯光', '童话', '仙境',
  };

  /// 将课文原句切分为词语单元
  static List<ChineseWord> segment(String sentence) {
    if (sentence.trim().isEmpty) return const [];
    final tokens = ChinesePinyin.format(sentence);
    final words = <ChineseWord>[];

    int i = 0;
    while (i < tokens.length) {
      final token = tokens[i];
      // 标点符号或无拼音字符直接跳过
      if (token.pinyin == null || token.pinyin!.isEmpty) {
        i++;
        continue;
      }

      // 贪婪匹配 4 字词 -> 3 字词 -> 2 字词
      bool matched = false;
      for (int len = 4; len >= 2; len--) {
        if (i + len <= tokens.length) {
          final subChars = <String>[];
          final subPinyins = <String>[];
          final subIndices = <int>[];
          bool valid = true;

          for (int k = 0; k < len; k++) {
            final t = tokens[i + k];
            if (t.pinyin == null || t.pinyin!.isEmpty) {
              valid = false;
              break;
            }
            subChars.add(t.char);
            subPinyins.add(t.pinyin!);
            subIndices.add(i + k);
          }

          if (valid) {
            final candidate = subChars.join();
            if (_commonTextbookWords.contains(candidate)) {
              words.add(ChineseWord(
                word: candidate,
                pinyinList: subPinyins,
                charIndices: subIndices,
              ));
              i += len;
              matched = true;
              break;
            }
          }
        }
      }

      if (matched) continue;

      // 未命中多字词：单字成词
      words.add(ChineseWord(
        word: token.char,
        pinyinList: [token.pinyin!],
        charIndices: [i],
      ));
      i++;
    }

    return words;
  }
}
