part of '../graphx_particles.dart';

/// Retained secondary emission triggered by another packed particle event.
///
/// The target remains an ordinary [GParticleEmitter]. No particle owns an
/// emitter or callback object; one retained rule describes how many particles
/// are emitted into the target.
final class GParticleSpawn {
  GParticleSpawn(this.target, {int count = 1}) : _count = _validateCount(count);

  final GParticleEmitter target;
  final GMatrix2 _inverseTarget = GMatrix2();

  int _count;
  bool enabled = true;

  int get count => _count;
  set count(int value) => _count = _validateCount(value);

  static int _validateCount(int value) {
    if (value < 0) {
      throw ArgumentError.value(value, 'count', 'must be >= 0');
    }
    return value;
  }
}

void _prepareSecondarySpawn(
  GParticleEmitter source,
  GParticleSpawn spawn,
  String argumentName,
) {
  if (identical(spawn.target, source)) {
    throw ArgumentError.value(
      spawn,
      argumentName,
      'target must be a different emitter',
    );
  }

  final target = spawn.target;
  target._store.enableDeferredFrames();
  target._store.frameProvider ??= () => target.isAttached ? target.stage.frame : -1;
}

void _spawnSecondaryAt(
  GParticleEmitter source,
  GParticleSpawn spawn,
  double sourceX,
  double sourceY,
) {
  if (!spawn.enabled || spawn.count == 0) return;
  final target = spawn.target;
  if (target.isDisposed) return;

  var worldX = sourceX;
  var worldY = sourceY;
  if (source._space == GParticleSpace.local) {
    final matrix = source.worldMatrix;
    worldX = matrix.a * sourceX + matrix.c * sourceY + matrix.tx;
    worldY = matrix.b * sourceX + matrix.d * sourceY + matrix.ty;
  }

  var originX = worldX;
  var originY = worldY;
  if (target._space == GParticleSpace.local) {
    if (!target.worldMatrix.invertInto(spawn._inverseTarget)) return;
    final inverse = spawn._inverseTarget;
    originX = inverse.a * worldX + inverse.c * worldY + inverse.tx;
    originY = inverse.b * worldX + inverse.d * worldY + inverse.ty;
  }

  var frame = -1;
  if (source.isAttached && target.isAttached) {
    if (!identical(source.stage, target.stage)) {
      throw StateError(
        'Secondary particle emitters must belong to the same Stage.',
      );
    }
    frame = source.stage.frame;
  }

  final before = target._store.count;
  final recycledBefore = target.stats.recycledLastFrame;
  for (var i = 0; i < spawn.count; ++i) {
    if (!target._spawnOne(
      0.0,
      originX: originX,
      originY: originY,
      hasOrigin: true,
    )) {
      continue;
    }
    if (frame >= 0) target._store.deferNewestUntilNextFrame(frame);
  }

  if (target._store.count != before || target.stats.recycledLastFrame != recycledBefore) {
    target.stats.active = target._store.count;
    target._markVisualChanged(bounds: true);
    target._syncUpdates();
  }
}

/// Secondary-emission configuration for [GParticleEmitter].
extension GParticleEmitterSecondary on GParticleEmitter {
  /// Optional emission into another retained emitter when a particle expires.
  ///
  /// Only natural lifetime expiry triggers this rule. `clear()`, capacity
  /// recycling and overflow replacement do not. A source cannot target itself;
  /// use a second retained emitter so packed-store mutation stays non-reentrant.
  GParticleSpawn? get onDeath => _store.secondaryConfig as GParticleSpawn?;

  set onDeath(GParticleSpawn? value) {
    if (identical(onDeath, value)) return;
    if (value != null) _prepareSecondarySpawn(this, value, 'onDeath');

    _store.secondaryConfig = value;
    if (value == null) {
      _store.onDeath = null;
      return;
    }

    _store.onDeath = (x, y) => _spawnSecondaryAt(this, value, x, y);
  }
}
