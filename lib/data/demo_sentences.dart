import '../models/sentence.dart';

/// Hard-coded demo sentences for Milestone 1.
///
/// The timestamps below line up with the bundled test asset
/// `assets/audio/sample.mp3` (a ~16.5s generated tone track where each
/// sentence region uses a distinct pitch and the gaps are silent). If you
/// replace `sample.mp3` with your own audio, adjust these `startMs` / `endMs`
/// values to match your recording — see README.
const List<Sentence> demoSentences = <Sentence>[
  Sentence(
    id: 's1',
    index: 0,
    startMs: 0,
    endMs: 3000,
    english: 'This is the first sentence.',
    chinese: '这是第一句话。',
  ),
  Sentence(
    id: 's2',
    index: 1,
    startMs: 3200,
    endMs: 6200,
    english: 'This is the second sentence.',
    chinese: '这是第二句话。',
  ),
  Sentence(
    id: 's3',
    index: 2,
    startMs: 6400,
    endMs: 9400,
    english: 'Listening sentence by sentence helps you catch every word.',
    chinese: '逐句精听能帮你听清每一个单词。',
  ),
  Sentence(
    id: 's4',
    index: 3,
    startMs: 9600,
    endMs: 12600,
    english: 'The player stops exactly at the end of each sentence.',
    chinese: '播放器会在每句话结束时精确停止。',
  ),
  Sentence(
    id: 's5',
    index: 4,
    startMs: 12800,
    endMs: 15800,
    english: 'This is the last sentence of the demo.',
    chinese: '这是演示的最后一句话。',
  ),
];

/// Asset path of the bundled demo audio, relative to the project root.
const String demoAudioAsset = 'assets/audio/sample.mp3';
