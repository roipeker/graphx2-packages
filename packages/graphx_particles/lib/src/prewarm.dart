part of '../graphx_particles.dart';

/// Deterministic fixed-step warm-up for [GParticleEmitter].
extension GParticleEmitterPrewarm on GParticleEmitter {
  /// Advances this emitter through [duration] seconds using the normal packed
  /// CPU simulation path before ordinary playback continues.
  ///
  /// The emitter is temporarily started when necessary so configured time-rate
  /// emission participates in warm-up. Its previous running/stopped state is
  /// restored afterward. Existing live particles are advanced too; call
  /// [clear] first when a fresh steady-state population is desired.
  ///
  /// [step] controls deterministic subdivision and defaults to 60 Hz. The same
  /// duration, step, seed and emitter configuration produce the same result.
  /// Linked secondary target emitters are not recursively stepped; prewarm them
  /// explicitly when their own already-spawned populations should also age.
  void prewarm(double duration, {double step = 1.0 / 60.0}) {
    if (!duration.isFinite || duration < 0.0) {
      throw ArgumentError.value(duration, 'duration', 'must be finite and >= 0');
    }
    if (!step.isFinite || step <= 0.0) {
      throw ArgumentError.value(step, 'step', 'must be finite and > 0');
    }
    if (duration == 0.0) return;

    final wasRunning = isRunning;
    if (!wasRunning) start();
    try {
      final wholeSteps = (duration / step).floor();
      for (var i = 0; i < wholeSteps; ++i) {
        update(step);
      }
      final remainder = duration - wholeSteps * step;
      if (remainder > 1e-12) update(remainder);
    } finally {
      if (!wasRunning) stop();
    }
  }
}
