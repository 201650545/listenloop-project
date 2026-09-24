/// Anki `.apkg` 导出器 —— 03 号文档 §三 契约的落地。
///
/// 包结构（100% 兼容桌面 Anki / AnkiMobile / AnkiDroid）：
///   * `collection.anki2` —— SQLite（Anki 2 legacy 格式，ver=11，
///     新版 Anki 打开时自动升级）；
///   * `media` —— JSON：包内编号文件名 → 真实音频文件名；
///   * 音频切片二进制（编号命名）。
///
/// 卡面模型对齐 03 号 §二 模板标准：
///   正面 = 音频 + 英文挖空句（零中文）；
///   背面 = 目标词 + 完整原句 + 中文释义（唯一中文位）。
///
/// 分层：本文件分两半 ——
///   * **纯函数**（schema JSON、guid、csum、字段拼接）可单测；
///   * `createCollectionDb` 依赖 sqflite 运行时（真机/模拟器），不进单测。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// ------------------------------------------------------------------ 数据

/// 一张待导出的卡（= 生词本里的一个词条）。
class AnkiExportNote {
  const AnkiExportNote({
    required this.targetWord,
    required this.sentenceCloze,
    required this.fullSentence,
    required this.sentenceZh,
    this.audioPath,
    this.audioImportName,
  });

  final String targetWord;
  final String sentenceCloze;
  final String fullSentence;

  /// 唯一中文位（03 红线：中文只出现在背面）。
  final String sentenceZh;

  /// 原片句轴切片的本地路径；null/不存在 = 该卡无音频。
  final String? audioPath;

  /// 音频进包后的真实文件名（media 映射的值）；与 [audioPath] 同时给出。
  /// Audio 字段将写成 `[sound:<audioImportName>]`。
  final String? audioImportName;
}

// -------------------------------------------------------------- 纯函数区

/// Anki guid 的 base91 字符集（官方顺序）。
const String _guidAlphabet =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    r'!#$%&()*+,-./:;<=>?@[]^_`{|}~';

/// 生成 10 位随机 guid（冲突概率可忽略；Anki 导入以 guid 判重）。
String genGuid(Random rng) => List.generate(
  10,
  (_) => _guidAlphabet[rng.nextInt(_guidAlphabet.length)],
).join();

/// Anki csum：首字段 UTF-8 SHA1 的前 8 位十六进制转整数。
int fieldChecksum(String firstField) {
  final digest = crypto.sha1.convert(utf8.encode(firstField));
  return int.parse(digest.toString().substring(0, 8), radix: 16);
}

/// notes.flds 的字段分隔符是 ASCII 0x1F（Anki 单元分隔）。
String joinFields(List<String> fields) => fields.join('\x1f');

/// 模型 id / 牌组 id：时间秒 + 随机，避免与用户现有集合冲突。
int ankiTimestampId(DateTime now, Random rng) =>
    now.millisecondsSinceEpoch ~/ 1000 * 1000 + rng.nextInt(1000);

/// col.models 的 JSON（单模型）。字段顺序必须与 notes.flds 一致。
String buildModelsJson({
  required int modelId,
  required int mod,
  required String deckName,
}) {
  String field(String name, int ord) =>
      '{"name":"$name","ord":$ord,"sticky":false,"rtl":false,"font":"Arial",'
      '"size":20,"description":"","plainText":false,"media":[]}';
  final css =
      '.card { font-family: arial; font-size: 20px; text-align: center; '
      'color: black; background-color: white; }'
      '.cloze { font-weight: 600; }'
      '.hint { color: #888; font-size: 14px; }'
      '.zh { color: #555; }';
  final model =
      '{"id":$modelId,"name":"ListenLoop Vocabulary","type":0,"mod":$mod,'
      '"usn":-1,"sortf":0,"did":1,"tmpls":[{"name":"Card 1","ord":0,'
      '"qfmt":"{{Audio}}<br><br>{{Sentence_Cloze}}<br><br><span class=hint>'
      '&#127911; recall the word</span>",'
      '"afmt":"{{FrontSide}}<hr id=answer><b>{{Target_Word}}</b><br><br>'
      '{{Full_Sentence_EN}}<br><span class=zh>{{Sentence_ZH}}</span>",'
      '"bqfmt":"","bafmt":"","did":null,"bfont":"","bsize":0}],'
      '"flds":[${field('Target_Word', 0)},${field('Sentence_Cloze', 1)},'
      '${field('Full_Sentence_EN', 2)},${field('Sentence_ZH', 3)},'
      '${field('Audio', 4)}],"css":"$css","latexPre":"\\\\documentclass[12pt]{article}\\n'
      '\\\\special{papersize=3in,5in}\\n\\\\usepackage[utf8]{inputenc}\\n'
      '\\\\usepackage{amssymb,amsmath}\\n\\\\pagestyle{empty}\\n'
      '\\\\setlength{\\\\parindent}{0in}\\n\\\\begin{document}",'
      '"latexPost":"\\\\end{document}","latexsvg":false,'
      '"req":[[0,"any",[1]]],"tags":[],"vers":[]}';
  return '{"$modelId":$model}';
}

/// col.decks 的 JSON（默认牌组 + ListenLoop 子牌组）。
String buildDecksJson({required int deckId, required int mod}) {
  String deck(int id, String name) =>
      '{"id":$id,"name":"$name","mod":$mod,"usn":-1,"lrnToday":[0,0],'
      '"revToday":[0,0],"newToday":[0,0],"timeToday":[0,0],"collapsed":false,'
      '"browserCollapsed":false,"desc":"","dyn":0,"conf":1,"extendNew":0,'
      '"extendRev":0}';
  return '{"1":${deck(1, 'Default')},"$deckId":${deck(deckId, 'ListenLoop::Vocabulary')}}';
}

/// col.dconf 的 JSON（默认调度配置）。
String buildDconfJson() =>
    '{"1":{"id":1,"name":"Default","mod":0,"usn":-1,"maxTaken":60,'
    '"autoplay":true,"timer":0,"replayq":true,"new":{"bury":true,'
    '"delays":[1,10],"initialFactor":2500,"ints":[1,4,7],"order":1,'
    '"perDay":20},"rev":{"bury":true,"ease4":1.3,"fuzz":0.05,"ivlFct":1,'
    '"maxIvl":36500,"minSpace":1,"perDay":200},"lapse":{"delays":[10],'
    '"leechAction":0,"leechFails":8,"minInt":1,"mult":0},"dyn":false}}';

/// col.conf 的 JSON。
String buildConfJson() =>
    '{"nextPos":1,"estTimes":true,"activeDecks":[1],"sortType":"noteFld",'
    '"timeLim":0,"sortBackwards":false,"addToCur":true,"curDeck":1,'
    '"newBury":true,"newSpread":0,"dueCounts":true,"curModel":null,'
    '"collapseTime":1200}';

/// Anki 2 legacy 的建表 SQL（列名与顺序必须与官方 schema 一致）。
const List<String> ankiSchemaSql = [
  'CREATE TABLE col (id integer PRIMARY KEY, crt integer NOT NULL, '
      'mod integer NOT NULL, scm integer NOT NULL, ver integer NOT NULL, '
      'dty integer NOT NULL, usn integer NOT NULL, ls integer NOT NULL, '
      'conf text NOT NULL, models text NOT NULL, decks text NOT NULL, '
      'dconf text NOT NULL, tags text NOT NULL)',
  'CREATE TABLE notes (id integer PRIMARY KEY, guid text NOT NULL, '
      'mid integer NOT NULL, mod integer NOT NULL, usn integer NOT NULL, '
      'tags text NOT NULL, flds text NOT NULL, sfld integer NOT NULL, '
      'csum integer NOT NULL, flags integer NOT NULL, data text NOT NULL)',
  'CREATE TABLE cards (id integer PRIMARY KEY, nid integer NOT NULL, '
      'did integer NOT NULL, ord integer NOT NULL, mod integer NOT NULL, '
      'usn integer NOT NULL, type integer NOT NULL, queue integer NOT NULL, '
      'due integer NOT NULL, ivl integer NOT NULL, factor integer NOT NULL, '
      'reps integer NOT NULL, lapses integer NOT NULL, left integer NOT NULL, '
      'odue integer NOT NULL, odid integer NOT NULL, flags integer NOT NULL, '
      'data text NOT NULL)',
  'CREATE TABLE revlog (id integer PRIMARY KEY, cid integer NOT NULL, '
      'usn integer NOT NULL, ease integer NOT NULL, ivl integer NOT NULL, '
      'lastIvl integer NOT NULL, factor integer NOT NULL, time integer NOT NULL, '
      'type integer NOT NULL)',
  'CREATE TABLE graves (usn integer NOT NULL, oid integer NOT NULL, '
      'type integer NOT NULL)',
  'CREATE INDEX ix_notes_usn ON notes (usn)',
  'CREATE INDEX ix_cards_usn ON cards (usn)',
  'CREATE INDEX ix_revlog_usn ON revlog (usn)',
  'CREATE INDEX ix_cards_nid ON cards (nid)',
  'CREATE INDEX ix_cards_sched ON cards (did, queue, due)',
  'CREATE INDEX ix_revlog_cid ON revlog (cid)',
  'CREATE INDEX ix_notes_csum ON notes (csum)',
];

/// 打包 .apkg（纯函数）：collection 字节 + 各卡的音频字节 → zip 字节。
///
/// [audioEntries]：包内编号 → (真实文件名, 文件字节)。
List<int> packageApkg({
  required List<int> collectionBytes,
  required Map<String, (String, List<int>)> audioEntries,
}) {
  final archive = Archive();
  archive.addFile(
    ArchiveFile('collection.anki2', collectionBytes.length, collectionBytes),
  );
  final mediaMap = <String, String>{};
  audioEntries.forEach((index, entry) {
    final (filename, bytes) = entry;
    mediaMap[index] = filename;
    archive.addFile(ArchiveFile(index, bytes.length, bytes));
  });
  final mediaJson = jsonEncode(mediaMap);
  archive.addFile(ArchiveFile.string('media', mediaJson));
  return ZipEncoder().encode(archive)!;
}

// ------------------------------------------------------------ sqflite 区

/// 在 [dbPath] 生成合法的 `collection.anki2`。
///
/// [newCardPos] 起始的 due 编号让新卡按导入顺序排队。
Future<void> createCollectionDb({
  required String dbPath,
  required List<AnkiExportNote> notes,
  required DateTime now,
  required Random rng,
}) async {
  final db = await openDatabase(dbPath, version: 1);
  try {
    await db.execute('PRAGMA journal_mode=DELETE');
    for (final sql in ankiSchemaSql) {
      await db.execute(sql);
    }

    final crt = now.millisecondsSinceEpoch ~/ 1000;
    final mod = crt;
    final modelId = ankiTimestampId(now, rng);
    final deckId = ankiTimestampId(now, rng);

    await db.insert('col', {
      'id': 1,
      'crt': crt,
      'mod': mod,
      'scm': mod,
      'ver': 11,
      'dty': 0,
      'usn': 0,
      'ls': 0,
      'conf': buildConfJson(),
      'models': buildModelsJson(modelId: modelId, mod: mod, deckName: ''),
      'decks': buildDecksJson(deckId: deckId, mod: mod),
      'dconf': buildDconfJson(),
      'tags': '{}',
    });

    var noteId = ankiTimestampId(now, rng) + 1000;
    var cardId = noteId + notes.length * 10;
    var position = 1;
    for (final note in notes) {
      final importName = note.audioImportName;
      final audioField = (importName == null || importName.isEmpty)
          ? ''
          : '[sound:$importName]';
      final firstField = note.targetWord;
      await db.insert('notes', {
        'id': noteId,
        'guid': genGuid(rng),
        'mid': modelId,
        'mod': crt,
        'usn': -1,
        'tags': '',
        'flds': joinFields([
          firstField,
          note.sentenceCloze,
          note.fullSentence,
          note.sentenceZh,
          audioField,
        ]),
        // Anki 的 sfld 列声明为 integer 但实际存首字段文本（官方同款做法）。
        'sfld': firstField,
        'csum': fieldChecksum(firstField),
        'flags': 0,
        'data': '',
      });
      await db.insert('cards', {
        'id': cardId,
        'nid': noteId,
        'did': deckId,
        'ord': 0,
        'mod': crt,
        'usn': -1,
        'type': 0,
        'queue': 0,
        'due': position,
        'ivl': 0,
        'factor': 0,
        'reps': 0,
        'lapses': 0,
        'left': 0,
        'odue': 0,
        'odid': 0,
        'flags': 0,
        'data': '',
      });
      noteId += 1;
      cardId += 1;
      position += 1;
    }
  } finally {
    await db.close();
  }
}

/// 一步到位：收集音频 → 生成 collection → 打包成 .apkg 字节。
///
/// [audioBytes] 把 note 的音频路径读成字节；返回 null 表示该卡无音频
/// （Audio 字段留空，模板自动不显示）。导入文件名由本函数统一分配。
Future<List<int>> buildApkgBytes({
  required List<AnkiExportNote> notes,
  required DateTime now,
  required String Function(AnkiExportNote note) audioFileName,
  required List<int>? Function(AnkiExportNote note) audioBytes,
  Random? rng,
}) async {
  final random = rng ?? Random.secure();
  final tmpDir = await Directory.systemTemp.createTemp('listenloop_apkg');
  try {
    // 先分配包内音频（编号 → 文件名 → 字节），与 notes 的 Audio 字段一致。
    final audioEntries = <String, (String, List<int>)>{};
    final importNames = <String, String>{};
    var index = 0;
    for (final note in notes) {
      final bytes = audioBytes(note);
      if (bytes == null || bytes.isEmpty) continue;
      final name = audioFileName(note);
      audioEntries['$index'] = (name, bytes);
      importNames[note.targetWord] = name;
      index += 1;
    }
    final withAudio = <AnkiExportNote>[
      for (final note in notes)
        AnkiExportNote(
          targetWord: note.targetWord,
          sentenceCloze: note.sentenceCloze,
          fullSentence: note.fullSentence,
          sentenceZh: note.sentenceZh,
          audioPath: note.audioPath,
          audioImportName: importNames[note.targetWord],
        ),
    ];

    final dbPath = p.join(tmpDir.path, 'collection.anki2');
    await createCollectionDb(
      dbPath: dbPath,
      notes: withAudio,
      now: now,
      rng: random,
    );
    final collectionBytes = await File(dbPath).readAsBytes();

    return packageApkg(
      collectionBytes: collectionBytes,
      audioEntries: audioEntries,
    );
  } finally {
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {
      // 清理失败不影响导出结果
    }
  }
}
