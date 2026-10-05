part of '../graphx_particles.dart';

/// Particle-rendering controls that deliberately remain separate from normal
/// [GNode] subtree compositing.
extension GParticleEmitterBlend on GParticleEmitter {
  /// Blend mode used when batched particle sprites write to the current render
  /// target.
  ///
  /// This is distinct from [GNode.blendMode]. `blendMode` composites the
  /// emitter subtree as a scene node; [particleBlendMode] controls how the
  /// individual sprites inside the emitter's retained `drawRawAtlas` batch
  /// overlap each other and the existing framebuffer.
  ///
  /// The mode is shared by the emitter batch. Different particle populations
  /// that require different blend modes should use separate emitters rather
  /// than per-particle blend state.
  ///
  /// Trail primitives currently keep their own normal compositing path.
  ui.BlendMode get particleBlendMode => _paint.blendMode;

  set particleBlendMode(ui.BlendMode value) {
    if (_paint.blendMode == value) return;
    _paint.blendMode = value;
    _markVisualChanged();
  }
}
