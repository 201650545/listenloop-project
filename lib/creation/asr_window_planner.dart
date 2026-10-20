import 'package:flutter/foundation.dart';

/// A stretch of audio the voice-activity detector believes is speech, or a
/// stretch it believes is silence. Both are just ranges on the ORIGINAL media
/// timeline — nothing here ever re-cuts the media.
@immutable
class SpeechRegion {
  const SpeechRegion({required this.startMs, required this.endMs});

  final int startMs;
  final int endMs;

  int get durationMs => endMs - startMs;

  @override
  String toString() => 'SpeechRegion($startMs..$endMs)';
}

/// One bounded span of the original media handed to the recogniser.
///
/// Two boundary pairs, and the difference between them matters (Creation V2
/// §七/§八):
///
/// * [readStartMs]..[readEndMs] is what is actually fed to the model. It MAY
///   overlap its neighbours, because a little extra context on each side is
///   what stops a word being cut in half at the seam.
/// * [keepStartMs]..[keepEndMs] is what this window OWNS. Keep ranges never
///   overlap and never leave a hole — together they partition the whole
///   timeline. A token belongs to the window whose keep range contains its
///   midpoint, so overlap is context only and never shows up twice.
@immutable
class AsrWindow {
  const AsrWindow({
    required this.readStartMs,
    required this.readEndMs,
    required this.keepStartMs,
    required this.keepEndMs,
  });

  final int readStartMs;
  final int readEndMs;
  final int keepStartMs;
  final int keepEndMs;

  int get keepDurationMs => keepEndMs - keepStartMs;

  @override
  String toString() =>
      'AsrWindow(read $readStartMs..$readEndMs, keep $keepStartMs..$keepEndMs)';
}

/// Target window length. Bring-up value from Creation V2 §二十四 — far below
/// the measured failure boundary (400 s passes, 405 s fails on a desktop run),
/// so it is safe while the architecture is proven. NOT a final product
/// parameter: it is meant to be replaced by measured numbers.
const int kDefaultTargetWindowMs = 90 * 1000;

/// Hard ceiling on how long any single inference may be.
///
/// This is the piece that actually guarantees stability (§六十一): the planner
/// never emits a window longer than this, whatever the VAD suggests, so a long
/// unbroken speech stretch cannot walk the model back into the failure region.
const int kHardMaxWindowMs = 120 * 1000;

/// How much context each window reads beyond what it owns. Overlap is context
/// only — it never becomes part of the final timeline (§二十七).
const int kDefaultWindowOverlapMs = 2 * 1000;

/// How far either side of the target the planner will look for a silence to
/// cut at before giving up and hard-splitting (§十一).
const int kBoundarySearchRadiusMs = 15 * 1000;

/// Turns silence information plus a target length into the ordered list of
/// bounded windows the recogniser will be run over.
///
/// VAD's role here is Boundary Adviser, not chunk generator (§九): it says
/// where the natural pauses are, and the planner decides the actual windows —
/// under a hard ceiling that silence alone cannot lift.
abstract final class AsrWindowPlanner {
  /// Plans windows covering `0..totalMs`.
  ///
  /// [silenceGaps] are the pauses found by the VAD. Passing an empty list is
  /// valid and means "no natural boundaries known" — the planner then
  /// hard-splits at the target length. That keeps windowing independent of the
  /// VAD: the pipeline is bounded and safe even before any VAD exists.
  static List<AsrWindow> plan({
    required int totalMs,
    List<SpeechRegion> silenceGaps = const [],
    int targetWindowMs = kDefaultTargetWindowMs,
    int hardMaxWindowMs = kHardMaxWindowMs,
    int overlapMs = kDefaultWindowOverlapMs,
    int boundarySearchRadiusMs = kBoundarySearchRadiusMs,
  }) {
    if (totalMs <= 0) return const [];
    // A target above the ceiling would make the ceiling meaningless.
    final target = targetWindowMs.clamp(1, hardMaxWindowMs);

    final windows = <AsrWindow>[];
    var cursor = 0;
    while (cursor < totalMs) {
      final remaining = totalMs - cursor;
      // The tail always becomes its own window, however short.
      if (remaining <= hardMaxWindowMs) {
        windows.add(
          _windowAround(cursor, totalMs, overlapMs, totalMs),
        );
        break;
      }
      final boundary = _pickBoundary(
        cursorMs: cursor,
        targetMs: cursor + target,
        hardMaxMs: cursor + hardMaxWindowMs,
        totalMs: totalMs,
        gaps: silenceGaps,
        radiusMs: boundarySearchRadiusMs,
      );
      windows.add(_windowAround(cursor, boundary, overlapMs, totalMs));
      cursor = boundary;
    }
    return windows;
  }

  /// Chooses where the window that starts at [cursorMs] should end.
  ///
  /// Prefers the midpoint of a silence inside the search window — closest to
  /// the target wins, and a longer pause breaks ties, since a longer pause is
  /// the safer place to cut (§十一). With no usable silence it falls back to a
  /// hard split exactly at the target.
  static int _pickBoundary({
    required int cursorMs,
    required int targetMs,
    required int hardMaxMs,
    required int totalMs,
    required List<SpeechRegion> gaps,
    required int radiusMs,
  }) {
    // Never below half the target — otherwise a badly placed pause could
    // produce a run of uselessly tiny windows.
    final lower = cursorMs + (targetMs - cursorMs) ~/ 2;
    final upper = hardMaxMs < totalMs ? hardMaxMs : totalMs;
    final searchLow = (targetMs - radiusMs).clamp(lower, upper);
    final searchHigh = (targetMs + radiusMs).clamp(lower, upper);

    SpeechRegion? bestGap;
    var bestMidpoint = 0;
    var bestDistance = 1 << 30;

    for (final gap in gaps) {
      final midpoint = (gap.startMs + gap.endMs) ~/ 2;
      if (midpoint < searchLow || midpoint > searchHigh) continue;
      final distance = (midpoint - targetMs).abs();
      final better =
          distance < bestDistance ||
          (distance == bestDistance &&
              bestGap != null &&
              gap.durationMs > bestGap.durationMs);
      if (better) {
        bestGap = gap;
        bestMidpoint = midpoint;
        bestDistance = distance;
      }
    }

    if (bestGap != null) return bestMidpoint;
    return targetMs.clamp(lower, upper);
  }

  /// Builds one window: it owns `keepStart..keepEnd`, and reads that plus
  /// [overlapMs] of context on each side (clamped to the media).
  static AsrWindow _windowAround(
    int keepStartMs,
    int keepEndMs,
    int overlapMs,
    int totalMs,
  ) => AsrWindow(
    readStartMs: (keepStartMs - overlapMs).clamp(0, totalMs),
    readEndMs: (keepEndMs + overlapMs).clamp(0, totalMs),
    keepStartMs: keepStartMs,
    keepEndMs: keepEndMs,
  );
}
