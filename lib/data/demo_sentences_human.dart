import '../models/sentence.dart';

/// Round 2 (Milestone 1B): real human English speech.
///
/// Source: The Gettysburg Address by Abraham Lincoln, read by 'shurtagal',
/// from LibriVox via archive.org. License: Public Domain.
/// https://archive.org/details/gettysburg_shurtagal_librivox
///
/// Sentence boundaries below are APPROXIMATE — derived by distributing the
/// total active-audio duration proportional to each sentence's word count
/// (silence-based segmentation was not possible: this reader speaks the
/// whole address continuously with no meaningful inter-sentence pauses).
/// They are intentionally approximate: the point of Round 2 is for a human
/// listener to label each boundary as start_too_early / start_too_late /
/// end_too_early / end_too_late / good, and use that data to decide
/// whether to introduce preBufferMs / postBufferMs in a later milestone.
const List<Sentence> demoSentencesHuman = <Sentence>[
  Sentence(
    id: 'h1',
    index: 0,
    startMs: 20,
    endMs: 10859,
    english: 'Four score and seven years ago our fathers brought forth on this continent, a new nation, conceived in Liberty, and dedicated to the proposition that all men are created equal.',
    chinese: '八十七年前，我们的先辈在这块大陆上创立了一个新的国家，它孕育于自由之中，奉行人人生而平等的信条。',
  ),
  Sentence(
    id: 'h2',
    index: 1,
    startMs: 10859,
    endMs: 19531,
    english: 'Now we are engaged in a great civil war, testing whether that nation, or any nation so conceived and so dedicated, can long endure.',
    chinese: '现在我们正从事一场伟大的内战，以考验这个国家，或者说任何一个如此孕育、如此奉行的国家，能否长治久安。',
  ),
  Sentence(
    id: 'h3',
    index: 2,
    startMs: 19531,
    endMs: 23145,
    english: 'We are met on a great battle-field of that war.',
    chinese: '我们在这场战争的一个大战场上相聚。',
  ),
  Sentence(
    id: 'h4',
    index: 3,
    startMs: 23145,
    endMs: 32900,
    english: 'We have come to dedicate a portion of that field, as a final resting place for those who here gave their lives that that nation might live.',
    chinese: '我们来到这里，是要把这个战场的一部分奉献出来，作为那些在这里献出生命、换取国家生存的人最后的安息之地。',
  ),
  Sentence(
    id: 'h5',
    index: 4,
    startMs: 32900,
    endMs: 36875,
    english: 'It is altogether fitting and proper that we should do this.',
    chinese: '我们这样做是完全恰当而且应该的。',
  ),
  Sentence(
    id: 'h6',
    index: 5,
    startMs: 36875,
    endMs: 43740,
    english: 'But, in a larger sense, we can not dedicate, we can not consecrate, we can not hallow, this ground.',
    chinese: '但是，从更深层的意义上说，我们无法奉献，我们无法圣化，我们无法使这片土地变得神圣。',
  ),
  Sentence(
    id: 'h7',
    index: 6,
    startMs: 43740,
    endMs: 51328,
    english: 'The brave men, living and dead, who struggled here, have consecrated it, far above our poor power to add or detract.',
    chinese: '那些在这里奋战的勇士，无论生者还是死者，已经使这片土地神圣，远非我们微薄的力量所能增减。',
  ),
  Sentence(
    id: 'h8',
    index: 7,
    startMs: 51328,
    endMs: 58916,
    english: 'The world will little note, nor long remember what we say here, but it can never forget what they did here.',
    chinese: '世人不会注意，也不会久记我们在这里所说的话，但永远不会忘记他们在这里所做的一切。',
  ),
  Sentence(
    id: 'h9',
    index: 8,
    startMs: 58916,
    endMs: 68311,
    english: 'It is for us the living, rather, to be dedicated here to the unfinished work which they who fought here have thus far so nobly advanced.',
    chinese: '毋宁说，我们生者应当在这里投身于他们迄今如此崇高推进的、尚未完成的事业。',
  ),
  Sentence(
    id: 'h10',
    index: 9,
    startMs: 68311,
    endMs: 97940,
    english: 'It is rather for us to be here dedicated to the great task remaining before us, that from these honored dead we take increased devotion to that cause for which they gave the last full measure of devotion, that we here highly resolve that these dead shall not have died in vain, that this nation, under God, shall have a new birth of freedom, and that government of the people, by the people, for the people, shall not perish from the earth.',
    chinese: '毋宁说，我们应当在这里献身于摆在我们面前的伟大任务——从这些光荣的死者身上汲取更多的献身精神，来完成他们已经完全彻底为之献身的事业；我们在这里下决心，绝不让这些死者白白牺牲；我们要使这个国家，在上帝的护佑下，获得自由的新生；我们要使这个民有、民治、民享的政府，决不从地球上消失。',
  ),
];

/// Asset path for the human-speech audio.
const String demoAudioAssetHuman = 'assets/audio/gettysburg.mp3';
