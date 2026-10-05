import 'dart:math' as math;

/// Built-in force field evaluated directly by the packed particle simulator.
enum GParticleFieldKind { wind, point, vortex, turbulence }

/// Distance attenuation for spatial particle fields.
enum GParticleFieldFalloff { none, linear, quadratic }

/// A retained, mutable force field shared by one or more particle emitters.
///
/// Fields are intentionally few and data-only. The simulator switches on
/// [kind] inside its packed loop; there is no callback or virtual dispatch per
/// particle. Coordinates use the emitter's simulation space: local coordinates
/// for local emitters and Stage/root coordinates for world emitters.
final class GParticleField {
  GParticleField.wind({double x = 0.0, double y = 0.0})
    : kind = GParticleFieldKind.wind,
      _x = _finite(x, 'x'),
      _y = _finite(y, 'y'),
      _strength = 0.0,
      _radius = 0.0,
      _frequency = 0.0,
      _speed = 0.0,
      seed = 0,
      falloff = GParticleFieldFalloff.none;

  GParticleField.point({
    required double x,
    required double y,
    required double strength,
    double radius = 0.0,
    this.falloff = GParticleFieldFalloff.linear,
  }) : kind = GParticleFieldKind.point,
       _x = _finite(x, 'x'),
       _y = _finite(y, 'y'),
       _strength = _finite(strength, 'strength'),
       _radius = _nonNegative(radius, 'radius'),
       _frequency = 0.0,
       _speed = 0.0,
       seed = 0;

  GParticleField.vortex({
    required double x,
    required double y,
    required double strength,
    double radius = 0.0,
    this.falloff = GParticleFieldFalloff.linear,
  }) : kind = GParticleFieldKind.vortex,
       _x = _finite(x, 'x'),
       _y = _finite(y, 'y'),
       _strength = _finite(strength, 'strength'),
       _radius = _nonNegative(radius, 'radius'),
       _frequency = 0.0,
       _speed = 0.0,
       seed = 0;

  GParticleField.turbulence({
    double strength = 80.0,
    double frequency = 0.015,
    double speed = 1.0,
    int seed = 0,
    double x = 0.0,
    double y = 0.0,
  }) : kind = GParticleFieldKind.turbulence,
       _x = _finite(x, 'x'),
       _y = _finite(y, 'y'),
       _strength = _finite(strength, 'strength'),
       _radius = 0.0,
       _frequency = _nonNegative(frequency, 'frequency'),
       _speed = _finite(speed, 'speed'),
       seed = seed,
       falloff = GParticleFieldFalloff.none;

  final GParticleFieldKind kind;

  /// Spatial attenuation. Ignored by wind and turbulence.
  GParticleFieldFalloff falloff;

  bool enabled = true;

  double _x;
  double _y;
  double _strength;
  double _radius;
  double _frequency;
  double _speed;
  int seed;

  /// Field origin, or acceleration X for a wind field.
  double get x => _x;
  set x(double value) => _x = _finite(value, 'x');

  /// Field origin, or acceleration Y for a wind field.
  double get y => _y;
  set y(double value) => _y = _finite(value, 'y');

  /// Acceleration magnitude. Negative point strength repels; negative vortex
  /// strength reverses rotation.
  double get strength => _strength;
  set strength(double value) => _strength = _finite(value, 'strength');

  /// Influence radius for point/vortex fields. Zero means unbounded.
  double get radius => _radius;
  set radius(double value) => _radius = _nonNegative(value, 'radius');

  /// Spatial frequency for turbulence in inverse logical units.
  double get frequency => _frequency;
  set frequency(double value) => _frequency = _nonNegative(value, 'frequency');

  /// Temporal turbulence phase speed in radians per second.
  double get speed => _speed;
  set speed(double value) => _speed = _finite(value, 'speed');

  /// Moves the field origin without rebuilding an emitter configuration.
  void setPosition(double x, double y) {
    _x = _finite(x, 'x');
    _y = _finite(y, 'y');
  }

  /// Sets directional acceleration for [GParticleField.wind].
  void setVector(double x, double y) => setPosition(x, y);

  double attenuation(double distance) {
    final radius = _radius;
    if (radius <= 0.0) return 1.0;
    if (distance >= radius) return 0.0;
    final remaining = 1.0 - distance / radius;
    return switch (falloff) {
      GParticleFieldFalloff.none => 1.0,
      GParticleFieldFalloff.linear => remaining,
      GParticleFieldFalloff.quadratic => remaining * remaining,
    };
  }

  /// Deterministic phase derived from [seed], kept out of the particle RNG.
  double get phase => (seed & 0xffff) * (math.pi * 2.0 / 65536.0);

  static double _finite(double value, String name) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, name, 'must be finite');
    }
    return value;
  }

  static double _nonNegative(double value, String name) {
    if (!value.isFinite || value < 0.0) {
      throw ArgumentError.value(value, name, 'must be finite and >= 0');
    }
    return value;
  }
}
