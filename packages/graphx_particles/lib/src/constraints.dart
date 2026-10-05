part of '../graphx_particles.dart';

/// Built-in geometry evaluated by the packed particle constraint pass.
enum GParticleConstraintKind { bounds, plane, circle }

/// Response applied when a particle violates a retained constraint.
enum GParticleConstraintResponse { bounce, kill, wrap }

/// Immutable retained particle constraint.
///
/// Constraints are evaluated in list order after one simulation step. Geometry
/// uses the emitter's current simulation space: emitter-local coordinates in
/// [GParticleSpace.local] and Stage/root coordinates in
/// [GParticleSpace.world]. No per-particle callback or collision object is
/// created.
final class GParticleConstraint {
  factory GParticleConstraint.bounds(
    GRect bounds, {
    GParticleConstraintResponse response = GParticleConstraintResponse.bounce,
    double restitution = 1.0,
    GParticleSpawn? onImpact,
  }) {
    if (!bounds.x.isFinite ||
        !bounds.y.isFinite ||
        !bounds.w.isFinite ||
        !bounds.h.isFinite ||
        bounds.w <= 0.0 ||
        bounds.h <= 0.0) {
      throw ArgumentError.value(bounds, 'bounds', 'must be finite and non-empty');
    }
    if (response == GParticleConstraintResponse.wrap && onImpact != null) {
      throw ArgumentError.value(
        onImpact,
        'onImpact',
        'wrap has no impact event; use bounce or kill',
      );
    }
    return GParticleConstraint._(
      kind: GParticleConstraintKind.bounds,
      response: response,
      restitution: _unit(restitution, 'restitution'),
      onImpact: onImpact,
      x1: bounds.left,
      y1: bounds.top,
      x2: bounds.right,
      y2: bounds.bottom,
    );
  }

  factory GParticleConstraint.plane({
    required double x,
    required double y,
    required double normalX,
    required double normalY,
    GParticleConstraintResponse response = GParticleConstraintResponse.bounce,
    double restitution = 1.0,
    GParticleSpawn? onImpact,
  }) {
    if (response == GParticleConstraintResponse.wrap) {
      throw ArgumentError.value(
        response,
        'response',
        'wrap is only defined for bounds constraints',
      );
    }
    x = _finite(x, 'x');
    y = _finite(y, 'y');
    normalX = _finite(normalX, 'normalX');
    normalY = _finite(normalY, 'normalY');
    final length2 = normalX * normalX + normalY * normalY;
    if (length2 <= 0.0) {
      throw ArgumentError('plane normal must be non-zero');
    }
    final inverseLength = 1.0 / math.sqrt(length2);
    return GParticleConstraint._(
      kind: GParticleConstraintKind.plane,
      response: response,
      restitution: _unit(restitution, 'restitution'),
      onImpact: onImpact,
      x1: x,
      y1: y,
      normalX: normalX * inverseLength,
      normalY: normalY * inverseLength,
    );
  }

  factory GParticleConstraint.circle({
    required double x,
    required double y,
    required double radius,
    bool keepInside = true,
    GParticleConstraintResponse response = GParticleConstraintResponse.bounce,
    double restitution = 1.0,
    GParticleSpawn? onImpact,
  }) {
    if (response == GParticleConstraintResponse.wrap) {
      throw ArgumentError.value(
        response,
        'response',
        'wrap is only defined for bounds constraints',
      );
    }
    radius = _finite(radius, 'radius');
    if (radius <= 0.0) {
      throw ArgumentError.value(radius, 'radius', 'must be > 0');
    }
    return GParticleConstraint._(
      kind: GParticleConstraintKind.circle,
      response: response,
      restitution: _unit(restitution, 'restitution'),
      onImpact: onImpact,
      x1: _finite(x, 'x'),
      y1: _finite(y, 'y'),
      radius: radius,
      keepInside: keepInside,
    );
  }

  const GParticleConstraint._({
    required this.kind,
    required this.response,
    required this.restitution,
    required this.onImpact,
    this._x1 = 0.0,
    this._y1 = 0.0,
    this._x2 = 0.0,
    this._y2 = 0.0,
    this._normalX = 0.0,
    this._normalY = 0.0,
    this._radius = 0.0,
    this.keepInside = true,
  });

  final GParticleConstraintKind kind;
  final GParticleConstraintResponse response;

  /// Velocity retained after a bounce, within `0..1`.
  final double restitution;

  /// Optional retained secondary emission at the resolved boundary point.
  ///
  /// Only `bounce` and `kill` constraints can produce an impact. `wrap` is a
  /// topological relocation and deliberately has no impact semantics.
  final GParticleSpawn? onImpact;

  /// Circle policy. `true` contains particles; `false` excludes the circle as
  /// an obstacle. Ignored by other constraint kinds.
  final bool keepInside;

  final double _x1;
  final double _y1;
  final double _x2;
  final double _y2;
  final double _normalX;
  final double _normalY;
  final double _radius;

  static double _finite(double value, String name) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, name, 'must be finite');
    }
    return value;
  }

  static double _unit(double value, String name) {
    if (!value.isFinite || value < 0.0 || value > 1.0) {
      throw ArgumentError.value(value, name, 'must be within 0..1');
    }
    return value;
  }
}

/// Constraint configuration for [GParticleEmitter].
///
/// The list is copied only when configuration changes. Constraint instances are
/// immutable and may be shared by multiple emitters.
extension GParticleEmitterConstraints on GParticleEmitter {
  List<GParticleConstraint> get constraints => _constraints;

  set constraints(List<GParticleConstraint> value) {
    if (value.isEmpty) {
      _constraints = const <GParticleConstraint>[];
      return;
    }

    final snapshot = List<GParticleConstraint>.unmodifiable(value);
    for (var i = 0; i < snapshot.length; ++i) {
      final spawn = snapshot[i].onImpact;
      if (spawn != null) {
        _prepareSecondarySpawn(this, spawn, 'constraints[$i].onImpact');
      }
    }
    _constraints = snapshot;
  }
}

const int _constraintNone = 0;
const int _constraintCorrected = 1;
const int _constraintRemoved = 2;

bool _resolveParticleConstraints(GParticleEmitter emitter) {
  final constraints = emitter._constraints;
  final store = emitter._store;
  if (constraints.isEmpty || store.count == 0) return false;

  var changed = false;
  var index = 0;
  while (index < store.count) {
    var corrected = false;
    var removed = false;
    for (var constraintIndex = 0; constraintIndex < constraints.length; ++constraintIndex) {
      final constraint = constraints[constraintIndex];
      final result = switch (constraint.kind) {
        GParticleConstraintKind.bounds => _resolveBoundsConstraint(
          emitter,
          store,
          index,
          constraint,
        ),
        GParticleConstraintKind.plane => _resolvePlaneConstraint(emitter, store, index, constraint),
        GParticleConstraintKind.circle => _resolveCircleConstraint(
          emitter,
          store,
          index,
          constraint,
        ),
      };
      if (result == _constraintRemoved) {
        changed = true;
        removed = true;
        break;
      }
      if (result == _constraintCorrected) {
        changed = true;
        corrected = true;
      }
    }

    if (removed) continue;
    if (corrected) _resetConstraintTrail(store, index);
    index++;
  }
  return changed;
}

int _resolveBoundsConstraint(
  GParticleEmitter emitter,
  ParticleStore store,
  int index,
  GParticleConstraint constraint,
) {
  var x = store.x[index];
  var y = store.y[index];
  final left = constraint._x1;
  final top = constraint._y1;
  final right = constraint._x2;
  final bottom = constraint._y2;
  final outsideX = x < left || x > right;
  final outsideY = y < top || y > bottom;
  if (!outsideX && !outsideY) return _constraintNone;

  switch (constraint.response) {
    case GParticleConstraintResponse.kill:
      final impactX = x.clamp(left, right).toDouble();
      final impactY = y.clamp(top, bottom).toDouble();
      _emitConstraintImpact(emitter, constraint, impactX, impactY);
      store.removeAt(index);
      return _constraintRemoved;
    case GParticleConstraintResponse.wrap:
      if (outsideX) {
        final width = right - left;
        x = left + (x - left) % width;
      }
      if (outsideY) {
        final height = bottom - top;
        y = top + (y - top) % height;
      }
      store.x[index] = x;
      store.y[index] = y;
      return _constraintCorrected;
    case GParticleConstraintResponse.bounce:
      final restitution = constraint.restitution;
      if (x < left) {
        x = left;
        if (store.vx[index] < 0.0) {
          store.vx[index] = -store.vx[index] * restitution;
        }
      } else if (x > right) {
        x = right;
        if (store.vx[index] > 0.0) {
          store.vx[index] = -store.vx[index] * restitution;
        }
      }
      if (y < top) {
        y = top;
        if (store.vy[index] < 0.0) {
          store.vy[index] = -store.vy[index] * restitution;
        }
      } else if (y > bottom) {
        y = bottom;
        if (store.vy[index] > 0.0) {
          store.vy[index] = -store.vy[index] * restitution;
        }
      }
      store.x[index] = x;
      store.y[index] = y;
      _emitConstraintImpact(emitter, constraint, x, y);
      return _constraintCorrected;
  }
}

int _resolvePlaneConstraint(
  GParticleEmitter emitter,
  ParticleStore store,
  int index,
  GParticleConstraint constraint,
) {
  final nx = constraint._normalX;
  final ny = constraint._normalY;
  final signedDistance =
      (store.x[index] - constraint._x1) * nx + (store.y[index] - constraint._y1) * ny;
  if (signedDistance >= 0.0) return _constraintNone;

  final impactX = store.x[index] - signedDistance * nx;
  final impactY = store.y[index] - signedDistance * ny;
  if (constraint.response == GParticleConstraintResponse.kill) {
    _emitConstraintImpact(emitter, constraint, impactX, impactY);
    store.removeAt(index);
    return _constraintRemoved;
  }

  store.x[index] = impactX;
  store.y[index] = impactY;
  final normalVelocity = store.vx[index] * nx + store.vy[index] * ny;
  if (normalVelocity < 0.0) {
    final impulse = (1.0 + constraint.restitution) * normalVelocity;
    store.vx[index] -= impulse * nx;
    store.vy[index] -= impulse * ny;
  }
  _emitConstraintImpact(emitter, constraint, impactX, impactY);
  return _constraintCorrected;
}

int _resolveCircleConstraint(
  GParticleEmitter emitter,
  ParticleStore store,
  int index,
  GParticleConstraint constraint,
) {
  final dx = store.x[index] - constraint._x1;
  final dy = store.y[index] - constraint._y1;
  final radius = constraint._radius;
  final distance2 = dx * dx + dy * dy;
  final radius2 = radius * radius;
  final violated = constraint.keepInside ? distance2 > radius2 : distance2 < radius2;
  if (!violated) return _constraintNone;

  double nx;
  double ny;
  if (distance2 > 1e-12) {
    final inverseDistance = 1.0 / math.sqrt(distance2);
    nx = dx * inverseDistance;
    ny = dy * inverseDistance;
  } else {
    final velocity2 = store.vx[index] * store.vx[index] + store.vy[index] * store.vy[index];
    if (velocity2 > 1e-12) {
      final inverseSpeed = 1.0 / math.sqrt(velocity2);
      nx = -store.vx[index] * inverseSpeed;
      ny = -store.vy[index] * inverseSpeed;
    } else {
      nx = 1.0;
      ny = 0.0;
    }
  }

  final impactX = constraint._x1 + nx * radius;
  final impactY = constraint._y1 + ny * radius;
  if (constraint.response == GParticleConstraintResponse.kill) {
    _emitConstraintImpact(emitter, constraint, impactX, impactY);
    store.removeAt(index);
    return _constraintRemoved;
  }

  store.x[index] = impactX;
  store.y[index] = impactY;
  final normalVelocity = store.vx[index] * nx + store.vy[index] * ny;
  final movingThroughBoundary = constraint.keepInside ? normalVelocity > 0.0 : normalVelocity < 0.0;
  if (movingThroughBoundary) {
    final impulse = (1.0 + constraint.restitution) * normalVelocity;
    store.vx[index] -= impulse * nx;
    store.vy[index] -= impulse * ny;
  }
  _emitConstraintImpact(emitter, constraint, impactX, impactY);
  return _constraintCorrected;
}

void _emitConstraintImpact(
  GParticleEmitter emitter,
  GParticleConstraint constraint,
  double x,
  double y,
) {
  final spawn = constraint.onImpact;
  if (spawn != null) _spawnSecondaryAt(emitter, spawn, x, y);
}

void _resetConstraintTrail(ParticleStore store, int index) {
  final trail = store.trail;
  if (trail == null) return;
  final base = index * trail.historySamples;
  trail.x[base] = store.x[index];
  trail.y[base] = store.y[index];
  trail.head[index] = trail.historySamples == 1 ? 0 : 1;
  trail.length[index] = 1;
  trail.markMoved();
}
