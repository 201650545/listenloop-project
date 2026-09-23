/// Which playback source the listening screen is currently driving
/// (Phase 3C §3).
///
/// A lesson owns exactly one timeline; the mode only decides whether that
/// timeline is rendered/sounded by the local audio engine or the embedded
/// video player. Modelled as a single enum (never as a combination of
/// booleans) so "both sources active" is unrepresentable.
enum PlaybackMode {
  /// Local audio engine (always available — the default on entry).
  audio,

  /// Embedded video player (only selectable when the lesson carries a
  /// [VideoSource]).
  video,
}
