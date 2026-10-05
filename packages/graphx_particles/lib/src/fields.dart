part of '../graphx_particles.dart';

/// Force-field configuration for [GParticleEmitter].
///
/// The list is copied only when configuration changes. Field objects remain
/// mutable and may be shared by several emitters, so moving an attractor or
/// changing wind strength does not rebuild particle storage.
extension GParticleEmitterFields on GParticleEmitter {
  List<GParticleField> get fields => _store.fields;

  set fields(List<GParticleField> value) {
    if (value.isEmpty) {
      _store.fields = const <GParticleField>[];
      return;
    }
    _store.fields = List<GParticleField>.unmodifiable(value);
  }

  /// Resets the deterministic time domain used by turbulence fields.
  void resetFieldTime() => _store.fieldTime = 0.0;
}
