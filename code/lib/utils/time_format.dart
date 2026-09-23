/// Small time-formatting helpers shared by the UI.
///
/// Kept separate so they can be unit tested and reused.
library;

/// Formats a millisecond value as seconds with one decimal, e.g. `3200` ->
/// `"3.2s"`. Negative values are clamped to zero.
String formatMsAsSeconds(int ms) {
  final clamped = ms < 0 ? 0 : ms;
  final seconds = clamped / 1000.0;
  return '${seconds.toStringAsFixed(1)}s';
}

/// Formats a [Duration] as seconds with one decimal place, e.g. `6200ms` ->
/// `"6.2s"`. Negative durations are clamped to zero. Used for the live position
/// readout.
String formatDuration(Duration d) {
  final totalMs = d.inMilliseconds < 0 ? 0 : d.inMilliseconds;
  final seconds = totalMs / 1000.0;
  return '${seconds.toStringAsFixed(1)}s';
}
