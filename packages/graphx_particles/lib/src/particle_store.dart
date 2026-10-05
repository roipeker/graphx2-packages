import 'dart:math' as math;
import 'dart:typed_data';

import 'particle_field.dart';
import 'particle_trail_store.dart';

/// Fixed-capacity dense particle storage used by GParticleEmitter.
///
/// This library is intentionally not exported. Active slots are [0, count),
/// death uses swap-remove, and an intrusive spawn-order list preserves O(1)
/// oldest recycling without imposing stable render ordering.
final class ParticleStore {
  ParticleStore(int capacity) : this._(_validateCapacity(capacity));

  ParticleStore._(this.capacity)
    : x = Float32List(capacity),
      y = Float32List(capacity),
      vx = Float32List(capacity),
      vy = Float32List(capacity),
      age = Float32List(capacity),
      life = Float32List(capacity),
      rotation = Float32List(capacity),
      angularVelocity = Float32List(capacity),
      scale = Float32List(capacity),
      baseColor = Uint32List(capacity),
      frameIndex = Uint16List(capacity),
      previous = Int32List(capacity),
      next = Int32List(capacity) {
    previous.fillRange(0, capacity, -1);
    next.fillRange(0, capacity, -1);
  }

  static const int endpointScaleFlag = 1 << 0;
  static const int endpointColorFlag = 1 << 1;

  final int capacity;
  final Float32List x;
  final Float32List y;
  final Float32List vx;
  final Float32List vy;
  final Float32List age;
  final Float32List life;
  final Float32List rotation;
  final Float32List angularVelocity;
  final Float32List scale;
  final Uint32List baseColor;
  final Uint16List frameIndex;
  final Int32List previous;
  final Int32List next;

  /// Optional lifetime endpoint state. These arrays remain null for emitters
  /// that never enable endpoint sampling and are retained after first use.
  Uint8List? endpointFlags;
  Float32List? endScale;
  Uint32List? endColor;

  List<GParticleField> fields = const <GParticleField>[];
  double fieldTime = 0.0;

  Object? secondaryConfig;
  void Function(double x, double y)? onDeath;
  int Function()? frameProvider;
  Int32List? _deferredFrame;

  /// Optional bounded trail history. Null keeps the normal particle hot path
  /// free of history allocation and per-particle trail branches.
  ParticleTrailStore? trail;
  Object? trailConfig;
  Object? trailRenderer;

  int count = 0;
  int oldest = -1;
  int newest = -1;

  bool get isEmpty => count == 0;
  bool get isFull => count == capacity;

  void enableEndScale() {
    endpointFlags ??= Uint8List(capacity);
    endScale ??= Float32List(capacity);
  }

  void enableEndColor() {
    endpointFlags ??= Uint8List(capacity);
    endColor ??= Uint32List(capacity);
  }

  void enableDeferredFrames() {
    if (_deferredFrame != null) return;
    final frames = Int32List(capacity);
    frames.fillRange(0, capacity, -1);
    _deferredFrame = frames;
  }

  void deferNewestUntilNextFrame(int frame) {
    if (frame < 0 || count == 0) return;
    enableDeferredFrames();
    _deferredFrame![count - 1] = frame;
  }

  int add({
    required double x,
    required double y,
    required double vx,
    required double vy,
    required double life,
    required double rotation,
    required double angularVelocity,
    required double scale,
    required int baseColor,
    double? particleEndScale,
    int? particleEndColor,
    int frameIndex = 0,
  }) {
    if (count == capacity) throw StateError('Particle capacity exceeded.');
    final index = count++;
    this.x[index] = x;
    this.y[index] = y;
    this.vx[index] = vx;
    this.vy[index] = vy;
    age[index] = 0.0;
    this.life[index] = life;
    this.rotation[index] = rotation;
    this.angularVelocity[index] = angularVelocity;
    this.scale[index] = scale;
    this.baseColor[index] = baseColor;
    this.frameIndex[index] = frameIndex;

    var flags = 0;
    if (particleEndScale != null) {
      enableEndScale();
      endScale![index] = particleEndScale;
      flags |= endpointScaleFlag;
    }
    if (particleEndColor != null) {
      enableEndColor();
      endColor![index] = particleEndColor;
      flags |= endpointColorFlag;
    }
    final endpoints = endpointFlags;
    if (endpoints != null) endpoints[index] = flags;

    _deferredFrame?[index] = -1;
    trail?.add(index, x, y);

    previous[index] = newest;
    next[index] = -1;
    if (newest >= 0) {
      next[newest] = index;
    } else {
      oldest = index;
    }
    newest = index;
    return index;
  }

  int removeOldest() {
    if (oldest < 0) return -1;
    final removed = oldest;
    removeAt(removed);
    return removed;
  }

  void removeAt(int index) {
    if (index < 0 || index >= count) {
      throw RangeError.index(index, x, 'index', null, count);
    }

    final before = previous[index];
    final after = next[index];
    if (before >= 0) {
      next[before] = after;
    } else {
      oldest = after;
    }
    if (after >= 0) {
      previous[after] = before;
    } else {
      newest = before;
    }

    final last = count - 1;
    final endpoints = endpointFlags;
    final scaleEndpoints = endScale;
    final colorEndpoints = endColor;
    if (index != last) {
      final movedBefore = previous[last];
      final movedAfter = next[last];
      x[index] = x[last];
      y[index] = y[last];
      vx[index] = vx[last];
      vy[index] = vy[last];
      age[index] = age[last];
      life[index] = life[last];
      rotation[index] = rotation[last];
      angularVelocity[index] = angularVelocity[last];
      scale[index] = scale[last];
      baseColor[index] = baseColor[last];
      frameIndex[index] = frameIndex[last];
      if (endpoints != null) endpoints[index] = endpoints[last];
      if (scaleEndpoints != null) scaleEndpoints[index] = scaleEndpoints[last];
      if (colorEndpoints != null) colorEndpoints[index] = colorEndpoints[last];
      final deferred = _deferredFrame;
      if (deferred != null) deferred[index] = deferred[last];
      previous[index] = movedBefore;
      next[index] = movedAfter;

      if (movedBefore >= 0) {
        next[movedBefore] = index;
      } else {
        oldest = index;
      }
      if (movedAfter >= 0) {
        previous[movedAfter] = index;
      } else {
        newest = index;
      }
    }

    trail?.removeAt(index, last);
    count = last;
    if (endpoints != null) endpoints[last] = 0;
    _deferredFrame?[last] = -1;
    previous[last] = -1;
    next[last] = -1;
  }

  void clear() {
    count = 0;
    oldest = -1;
    newest = -1;
    trail?.clear();
  }

  int step(
    double dt, {
    required double accelerationX,
    required double accelerationY,
    required double drag,
  }) {
    if (dt <= 0.0 || count == 0) return 0;
    final activeFields = fields;
    if (onDeath == null && _deferredFrame == null) {
      final activeTrail = trail;
      if (activeTrail == null) {
        if (activeFields.isEmpty) {
          return _stepConstant(dt, accelerationX, accelerationY, drag);
        }
        return _stepFields(dt, accelerationX, accelerationY, drag, activeFields);
      }
      if (activeFields.isEmpty) {
        return _stepConstantTrail(
          dt,
          accelerationX,
          accelerationY,
          drag,
          activeTrail,
        );
      }
      return _stepFieldsTrail(
        dt,
        accelerationX,
        accelerationY,
        drag,
        activeFields,
        activeTrail,
      );
    }
    return _stepExtended(
      dt,
      accelerationX,
      accelerationY,
      drag,
      activeFields,
      frameProvider?.call() ?? -1,
    );
  }

  int _stepFields(
    double dt,
    double accelerationX,
    double accelerationY,
    double drag,
    List<GParticleField> activeFields,
  ) {
    final sampleTime = fieldTime + dt * 0.5;
    var expired = 0;
    var index = 0;
    while (index < count) {
      final nextAge = age[index] + dt;
      if (life[index] <= 0.0 || nextAge >= life[index]) {
        removeAt(index);
        expired++;
        continue;
      }
      age[index] = nextAge;
      _integrateWithFields(
        index,
        dt,
        accelerationX,
        accelerationY,
        drag,
        activeFields,
        sampleTime,
      );
      index++;
    }
    fieldTime += dt;
    return expired;
  }

  int _stepFieldsTrail(
    double dt,
    double accelerationX,
    double accelerationY,
    double drag,
    List<GParticleField> activeFields,
    ParticleTrailStore activeTrail,
  ) {
    final sampleTime = fieldTime + dt * 0.5;
    var expired = 0;
    var moved = false;
    var index = 0;
    while (index < count) {
      final currentAge = age[index];
      final nextAge = currentAge + dt;
      if (life[index] <= 0.0 || nextAge >= life[index]) {
        removeAt(index);
        expired++;
        continue;
      }
      age[index] = nextAge;
      final x0 = x[index];
      final y0 = y[index];
      _integrateWithFields(
        index,
        dt,
        accelerationX,
        accelerationY,
        drag,
        activeFields,
        sampleTime,
      );
      activeTrail.recordStep(
        index,
        x0,
        y0,
        x[index],
        y[index],
        currentAge,
        nextAge,
      );
      moved = true;
      index++;
    }
    if (moved) activeTrail.markMoved();
    fieldTime += dt;
    return expired;
  }

  int _stepExtended(
    double dt,
    double accelerationX,
    double accelerationY,
    double drag,
    List<GParticleField> activeFields,
    int frame,
  ) {
    final sampleTime = fieldTime + dt * 0.5;
    final deferred = _deferredFrame;
    final deathHook = onDeath;
    final activeTrail = trail;
    var trailMoved = false;
    var expired = 0;
    var index = 0;
    while (index < count) {
      if (frame >= 0 && deferred != null && deferred[index] == frame) {
        index++;
        continue;
      }

      final currentAge = age[index];
      final particleLife = life[index];
      final nextAge = currentAge + dt;
      if (particleLife <= 0.0 || nextAge >= particleLife) {
        if (deathHook != null && particleLife > currentAge) {
          final remaining = particleLife - currentAge;
          if (activeFields.isEmpty) {
            _integrate(index, remaining, accelerationX, accelerationY, drag);
          } else {
            _integrateWithFields(
              index,
              remaining,
              accelerationX,
              accelerationY,
              drag,
              activeFields,
              fieldTime + remaining * 0.5,
            );
          }
        }
        deathHook?.call(x[index], y[index]);
        removeAt(index);
        expired++;
        continue;
      }

      age[index] = nextAge;
      final x0 = x[index];
      final y0 = y[index];
      if (activeFields.isEmpty) {
        _integrate(index, dt, accelerationX, accelerationY, drag);
      } else {
        _integrateWithFields(
          index,
          dt,
          accelerationX,
          accelerationY,
          drag,
          activeFields,
          sampleTime,
        );
      }
      if (activeTrail != null) {
        activeTrail.recordStep(
          index,
          x0,
          y0,
          x[index],
          y[index],
          currentAge,
          nextAge,
        );
        trailMoved = true;
      }
      index++;
    }
    if (trailMoved) activeTrail!.markMoved();
    if (activeFields.isNotEmpty) fieldTime += dt;
    return expired;
  }

  int _stepConstant(
    double dt,
    double accelerationX,
    double accelerationY,
    double drag,
  ) {
    var expired = 0;
    var index = 0;
    while (index < count) {
      final nextAge = age[index] + dt;
      if (life[index] <= 0.0 || nextAge >= life[index]) {
        removeAt(index);
        expired++;
        continue;
      }
      age[index] = nextAge;
      _integrate(index, dt, accelerationX, accelerationY, drag);
      index++;
    }
    return expired;
  }

  int _stepConstantTrail(
    double dt,
    double accelerationX,
    double accelerationY,
    double drag,
    ParticleTrailStore activeTrail,
  ) {
    var expired = 0;
    var moved = false;
    var index = 0;
    while (index < count) {
      final currentAge = age[index];
      final nextAge = currentAge + dt;
      if (life[index] <= 0.0 || nextAge >= life[index]) {
        removeAt(index);
        expired++;
        continue;
      }
      age[index] = nextAge;
      final x0 = x[index];
      final y0 = y[index];
      _integrate(index, dt, accelerationX, accelerationY, drag);
      activeTrail.recordStep(
        index,
        x0,
        y0,
        x[index],
        y[index],
        currentAge,
        nextAge,
      );
      moved = true;
      index++;
    }
    if (moved) activeTrail.markMoved();
    return expired;
  }

  bool advanceAt(
    int index,
    double dt, {
    required double accelerationX,
    required double accelerationY,
    required double drag,
  }) {
    if (dt <= 0.0) return true;
    final currentAge = age[index];
    final nextAge = currentAge + dt;
    if (life[index] <= 0.0 || nextAge >= life[index]) {
      removeAt(index);
      return false;
    }
    age[index] = nextAge;

    final x0 = x[index];
    final y0 = y[index];
    final activeFields = fields;
    if (activeFields.isEmpty) {
      _integrate(index, dt, accelerationX, accelerationY, drag);
    } else {
      _integrateWithFields(
        index,
        dt,
        accelerationX,
        accelerationY,
        drag,
        activeFields,
        fieldTime + dt * 0.5,
      );
    }
    final activeTrail = trail;
    if (activeTrail != null) {
      activeTrail.recordStep(
        index,
        x0,
        y0,
        x[index],
        y[index],
        currentAge,
        nextAge,
      );
      activeTrail.markMoved();
    }
    return true;
  }

  void _integrateWithFields(
    int index,
    double dt,
    double accelerationX,
    double accelerationY,
    double drag,
    List<GParticleField> activeFields,
    double sampleTime,
  ) {
    var ax = accelerationX;
    var ay = accelerationY;
    final px = x[index];
    final py = y[index];

    for (var fieldIndex = 0; fieldIndex < activeFields.length; ++fieldIndex) {
      final field = activeFields[fieldIndex];
      if (!field.enabled) continue;
      switch (field.kind) {
        case GParticleFieldKind.wind:
          ax += field.x;
          ay += field.y;
        case GParticleFieldKind.point:
          final dx = field.x - px;
          final dy = field.y - py;
          final distance2 = dx * dx + dy * dy;
          if (distance2 <= 1e-12) continue;
          final distance = math.sqrt(distance2);
          final attenuation = field.attenuation(distance);
          if (attenuation <= 0.0) continue;
          final factor = field.strength * attenuation / distance;
          ax += dx * factor;
          ay += dy * factor;
        case GParticleFieldKind.vortex:
          final dx = field.x - px;
          final dy = field.y - py;
          final distance2 = dx * dx + dy * dy;
          if (distance2 <= 1e-12) continue;
          final distance = math.sqrt(distance2);
          final attenuation = field.attenuation(distance);
          if (attenuation <= 0.0) continue;
          final factor = field.strength * attenuation / distance;
          ax += dy * factor;
          ay -= dx * factor;
        case GParticleFieldKind.turbulence:
          final frequency = field.frequency;
          if (field.strength == 0.0 || frequency == 0.0) continue;
          final phase = field.phase;
          final time = sampleTime * field.speed;
          final sx = (px - field.x) * frequency;
          final sy = (py - field.y) * frequency;
          ax += math.sin(sy + time + phase) * field.strength;
          ay += math.cos(sx - time + phase * 1.61803398875) * field.strength;
      }
    }

    _integrate(index, dt, ax, ay, drag);
  }

  void _integrate(
    int index,
    double dt,
    double accelerationX,
    double accelerationY,
    double drag,
  ) {
    final vx0 = vx[index];
    final vy0 = vy[index];
    if (drag <= 0.0) {
      final halfDt2 = 0.5 * dt * dt;
      x[index] += vx0 * dt + accelerationX * halfDt2;
      y[index] += vy0 * dt + accelerationY * halfDt2;
      vx[index] = vx0 + accelerationX * dt;
      vy[index] = vy0 + accelerationY * dt;
    } else {
      final decay = math.exp(-drag * dt);
      final invDrag = 1.0 / drag;
      final factor = (1.0 - decay) * invDrag;
      final terminalX = accelerationX * invDrag;
      final terminalY = accelerationY * invDrag;
      x[index] += terminalX * dt + (vx0 - terminalX) * factor;
      y[index] += terminalY * dt + (vy0 - terminalY) * factor;
      vx[index] = terminalX + (vx0 - terminalX) * decay;
      vy[index] = terminalY + (vy0 - terminalY) * decay;
    }
    rotation[index] += angularVelocity[index] * dt;
  }

  static int _validateCapacity(int value) {
    if (value < 0) {
      throw ArgumentError.value(value, 'capacity', 'must be >= 0');
    }
    return value;
  }
}
