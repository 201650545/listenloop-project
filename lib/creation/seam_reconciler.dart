import 'dart:math' as math;

import 'word_timestamp.dart';

/// How far either side of a window boundary reconciliation looks.
///
/// Measured, not guessed. An audit of the real 32-minute material — raw
/// overlap words from both windows, paired by normalised text and nearest
/// midpoint — found 13 duplicates that midpoint ownership leaked, with this
/// distance-from-boundary distribution:
///
///   p50 = 120 ms   p90 = 200 ms   p99 = 2160 ms   max = 2160 ms
///
/// Twelve of the thirteen sit at 200 ms or less. The single 2160 ms sample is
/// almost certainly a pairing artefact: that seam has two `sentence` tokens on
/// one side and one on the other, so the nearest-neighbour matcher paired the
/// far one too. Taking `p99 + margin` here would mean letting one suspect
/// sample decide the constant, so the value comes from the cluster with ample
/// headroom instead.
const int kSeamSearchRadiusMs = 1500;

/// How far apart two midpoints may be and still be called the same word.
///
/// Compared on MIDPOINTS, not on the gap between two output spans: duplicates
/// can overlap, touch, or even come out in the wrong order, so "the interval
/// between them" is not well defined (Creation V2 §二十八 follow-up).
///
/// Same audit, midpoint drift between the two estimates of one word:
///
///   p50 = 200 ms   p90 = 280 ms   p99 = 2240 ms   max = 2240 ms
///
/// The cluster tops out at 280 ms; 500 ms gives it ~80% headroom while staying
/// far below the gap at which two copies are really two different utterances.
/// Note this is the value the bring-up guess had already landed on, whereas the
/// 3000 ms search radius above was four times looser than the data supports.
const int kSeamMidpointToleranceMs = 500;

/// A recognised word plus WHICH ASR window produced it.
///
/// Provenance exists only while seams are being reconciled and is dropped
/// afterwards. Without it, two identical adjacent words are indistinguishable
/// — and `very very` from one window is real speech, while `the the` split
/// across two windows is a stitch artefact. Guessing between those is how a
/// deduper ends up deleting English.
class SeamWord {
  const SeamWord({
    required this.word,
    required this.startMs,
    required this.endMs,
    required this.windowId,
    required this.readStartMs,
    required this.readEndMs,
  });

  final String word;
  final int startMs;
  final int endMs;

  /// Index of the window that produced this word.
  final int windowId;

  /// That window's read range, so the word's distance from its edges is known.
  final int readStartMs;
  final int readEndMs;

  int get midpointMs => (startMs + endMs) ~/ 2;

  /// Distance from this word to the nearest edge of the window that produced
  /// it. A larger margin means the model had more context around this word, so
  /// its alignment is the more trustworthy of two candidates.
  int get contextMarginMs =>
      math.min(midpointMs - readStartMs, readEndMs - midpointMs);
}

/// Resolves the words a window seam produced twice.
///
/// Three rules, each from a measurement rather than a guess:
///
/// * **Only near a boundary.** A genuine repeated word elsewhere must survive.
/// * **Across windows only.** Two identical adjacent words from the SAME
///   window are the model hearing `very very`; only a pair split across two
///   windows can be a stitch artefact.
/// * **Keep the better-context copy, intact.** "Earlier" is not a quality
///   signal — it only says window A's alignment drifted left and B's drifted
///   right. The copy further from its own window's edge wins, and its text and
///   timing are taken unchanged. Stretching a merged span across both
///   candidates would invent a 900 ms "word" and corrupt the pauses and
///   sentence ends downstream.
///
/// A word that BOTH windows recognised but that ownership dropped from both is
/// NOT repaired here — that needs the overlap-level sequence alignment, which
/// is the next step, not this one.
List<WordTimestamp> reconcileSeams(
  List<SeamWord> words,
  List<int> boundariesMs, {
  int searchRadiusMs = kSeamSearchRadiusMs,
  int midpointToleranceMs = kSeamMidpointToleranceMs,
}) {
  if (words.length < 2 || boundariesMs.isEmpty) {
    return [for (final w in words) _asWord(w)];
  }

  bool nearSeam(SeamWord word) {
    for (final boundary in boundariesMs) {
      if ((word.midpointMs - boundary).abs() <= searchRadiusMs) return true;
    }
    return false;
  }

  final kept = <SeamWord>[];
  for (final word in words) {
    final previous = kept.isEmpty ? null : kept.last;
    if (previous != null && _isDuplicate(previous, word, midpointToleranceMs, nearSeam)) {
      // Replace only if the newcomer has more context; otherwise the earlier
      // candidate stands. Either way exactly one copy survives, with its own
      // timing untouched.
      if (word.contextMarginMs > previous.contextMarginMs) {
        kept[kept.length - 1] = word;
      }
      continue;
    }
    kept.add(word);
  }
  return [for (final word in kept) _asWord(word)];
}

bool _isDuplicate(
  SeamWord a,
  SeamWord b,
  int midpointToleranceMs,
  bool Function(SeamWord) nearSeam,
) {
  if (a.windowId == b.windowId) return false; // genuine repetition, not a stitch
  if (!_sameWord(a.word, b.word)) return false;
  if ((a.midpointMs - b.midpointMs).abs() > midpointToleranceMs) return false;
  return nearSeam(a) || nearSeam(b);
}

/// Compares words ignoring case and punctuation — the two windows routinely
/// punctuate the same word differently ("Right," vs "Right.").
bool _sameWord(String a, String b) {
  final left = _normalise(a);
  return left.isNotEmpty && left == _normalise(b);
}

String _normalise(String value) =>
    value.toLowerCase().replaceAll(RegExp(r"[^\p{L}\p{N}']", unicode: true), '');

WordTimestamp _asWord(SeamWord word) => WordTimestamp(
  word: word.word,
  startMs: word.startMs,
  endMs: word.endMs,
);
