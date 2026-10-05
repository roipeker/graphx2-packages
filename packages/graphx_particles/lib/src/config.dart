part of '../graphx_particles.dart';

/// Behavior when an emitter has no free particle slots.
enum GParticleOverflow {
  /// Ignore new particles until a slot becomes free.
  drop,

  /// Remove the oldest live particle and reuse its slot.
  recycleOldest,
}

/// Coordinate space used by particle simulation data.
enum GParticleSpace {
  /// Particles remain in emitter-local coordinates and follow later transforms.
  local,

  /// Spawned particles are converted to Stage/root coordinates and remain there.
  world,
}

/// How a particle chooses a texture frame when multiple same-image frames exist.
enum GParticleFrameMode {
  /// Always render the first configured frame.
  first,

  /// Sample and retain one deterministic frame at particle birth.
  random,

  /// Advance through configured frames from normalized particle lifetime.
  overLife,
}

/// How initial velocity direction is derived from the emission shape.
///
/// [GParticleEmitter.angle] remains absolute in [angle] mode. In derived modes
/// it is sampled as an angular offset/spread around the shape direction.
enum GParticleDirectionMode {
  angle,
  radial,
  tangent,
  normal,
}

/// Built-in emission geometry.
enum GParticleShapeKind { point, rectangle, circle, line, path }

/// Inclusive scalar range sampled once when a particle is emitted.
final class GParticleRange {
  const GParticleRange(double value, [double? max])
    : min = value,
      max = max ?? value,
      assert(value > double.negativeInfinity && value < double.infinity),
      assert(
        max == null || (max > double.negativeInfinity && max < double.infinity),
      ),
      assert(max == null || value <= max);

  final double min;
  final double max;

  bool get isConstant => min == max;

  @override
  String toString() => isConstant ? '$min' : '$min..$max';
}

/// Small retained scalar lookup table evaluated over normalized lifetime.
///
/// Stops are evenly distributed from 0 to 1 and compiled once at construction.
/// Runtime evaluation performs no callback dispatch and allocates no objects.
final class GParticleCurve {
  GParticleCurve.stops(List<double> stops, {int samples = 64})
    : _values = _compileStops(stops, samples);

  factory GParticleCurve.linear(
    double from,
    double to, {
    int samples = 64,
  }) => GParticleCurve.stops(<double>[from, to], samples: samples);

  final Float32List _values;

  int get sampleCount => _values.length;

  double evaluate(double normalizedAge) => _sample(normalizedAge);

  double _sample(double normalizedAge) {
    final t = normalizedAge <= 0.0
        ? 0.0
        : normalizedAge >= 1.0
        ? 1.0
        : normalizedAge;
    final scaled = t * (_values.length - 1);
    final index = scaled.floor();
    if (index >= _values.length - 1) return _values.last;
    final fraction = scaled - index;
    final a = _values[index];
    return a + (_values[index + 1] - a) * fraction;
  }

  static Float32List _compileStops(List<double> stops, int samples) {
    if (stops.isEmpty) {
      throw ArgumentError.value(stops, 'stops', 'must not be empty');
    }
    if (samples < 2) {
      throw ArgumentError.value(samples, 'samples', 'must be >= 2');
    }
    for (var i = 0; i < stops.length; ++i) {
      if (!stops[i].isFinite) {
        throw ArgumentError.value(stops[i], 'stops[$i]', 'must be finite');
      }
    }

    final values = Float32List(samples);
    if (stops.length == 1) {
      values.fillRange(0, samples, stops.first);
      return values;
    }

    final lastStop = stops.length - 1;
    for (var i = 0; i < samples; ++i) {
      final t = i / (samples - 1);
      final position = t * lastStop;
      final index = position.floor();
      if (index >= lastStop) {
        values[i] = stops.last;
        continue;
      }
      final fraction = position - index;
      final a = stops[index];
      values[i] = a + (stops[index + 1] - a) * fraction;
    }
    return values;
  }
}

/// Small retained color lookup table evaluated over normalized lifetime.
///
/// Colors are interpolated in sRGB and packed to ARGB8888 when configured.
final class GParticleColorCurve {
  GParticleColorCurve.stops(List<ui.Color> stops, {int samples = 64})
    : _values = _compileStops(stops, samples);

  final Uint32List _values;

  int get sampleCount => _values.length;

  ui.Color evaluate(double normalizedAge) {
    final packed = _samplePacked(normalizedAge);
    return ui.Color.fromARGB(
      (packed >>> 24) & 0xff,
      (packed >>> 16) & 0xff,
      (packed >>> 8) & 0xff,
      packed & 0xff,
    );
  }

  int _samplePacked(double normalizedAge) {
    final t = normalizedAge <= 0.0
        ? 0.0
        : normalizedAge >= 1.0
        ? 1.0
        : normalizedAge;
    final index = (t * (_values.length - 1)).round();
    return _values[index];
  }

  static Uint32List _compileStops(List<ui.Color> stops, int samples) {
    if (stops.isEmpty) {
      throw ArgumentError.value(stops, 'stops', 'must not be empty');
    }
    if (samples < 2) {
      throw ArgumentError.value(samples, 'samples', 'must be >= 2');
    }

    final packedStops = Uint32List(stops.length);
    for (var i = 0; i < stops.length; ++i) {
      packedStops[i] = _packColor(stops[i]);
    }

    final values = Uint32List(samples);
    if (packedStops.length == 1) {
      values.fillRange(0, samples, packedStops.first);
      return values;
    }

    final lastStop = packedStops.length - 1;
    for (var i = 0; i < samples; ++i) {
      final t = i / (samples - 1);
      final position = t * lastStop;
      final index = position.floor();
      if (index >= lastStop) {
        values[i] = packedStops.last;
        continue;
      }
      values[i] = _lerpPackedColor(
        packedStops[index],
        packedStops[index + 1],
        position - index,
      );
    }
    return values;
  }
}

/// Compact built-in emission geometry.
///
/// Rectangle emission is centered on the emitter. Circle emission is uniform by
/// area unless [edge] is true. Line endpoints and paths are emitter-local.
final class GParticleShape {
  const GParticleShape.point()
    : kind = GParticleShapeKind.point,
      width = 0.0,
      height = 0.0,
      radius = 0.0,
      edge = false,
      x1 = 0.0,
      y1 = 0.0,
      x2 = 0.0,
      y2 = 0.0,
      path = null;

  const GParticleShape.rect(double width, double height)
    : assert(
        width >= 0.0 && width > double.negativeInfinity && width < double.infinity,
      ),
      assert(
        height >= 0.0 && height > double.negativeInfinity && height < double.infinity,
      ),
      kind = GParticleShapeKind.rectangle,
      width = width,
      height = height,
      radius = 0.0,
      edge = false,
      x1 = 0.0,
      y1 = 0.0,
      x2 = 0.0,
      y2 = 0.0,
      path = null;

  const GParticleShape.circle(double radius, {bool edge = false})
    : assert(
        radius >= 0.0 && radius > double.negativeInfinity && radius < double.infinity,
      ),
      kind = GParticleShapeKind.circle,
      width = 0.0,
      height = 0.0,
      radius = radius,
      edge = edge,
      x1 = 0.0,
      y1 = 0.0,
      x2 = 0.0,
      y2 = 0.0,
      path = null;

  const GParticleShape.line(double x1, double y1, double x2, double y2)
    : assert(
        x1 > double.negativeInfinity &&
            x1 < double.infinity &&
            y1 > double.negativeInfinity &&
            y1 < double.infinity &&
            x2 > double.negativeInfinity &&
            x2 < double.infinity &&
            y2 > double.negativeInfinity &&
            y2 < double.infinity,
      ),
      kind = GParticleShapeKind.line,
      width = 0.0,
      height = 0.0,
      radius = 0.0,
      edge = false,
      x1 = x1,
      y1 = y1,
      x2 = x2,
      y2 = y2,
      path = null;

  /// Uniform arc-length emission along [path].
  ///
  /// The path is retained by reference. Geometry edits affect future births
  /// immediately and reuse `GPath`'s cached arc-length lookup data.
  GParticleShape.path(GPath path)
    : kind = GParticleShapeKind.path,
      width = 0.0,
      height = 0.0,
      radius = 0.0,
      edge = false,
      x1 = 0.0,
      y1 = 0.0,
      x2 = 0.0,
      y2 = 0.0,
      path = path;

  final GParticleShapeKind kind;
  final double width;
  final double height;
  final double radius;
  final bool edge;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final GPath? path;

  @override
  String toString() => switch (kind) {
    GParticleShapeKind.point => 'point',
    GParticleShapeKind.rectangle => 'rect(${width}x$height)',
    GParticleShapeKind.circle => edge ? 'ring(r=$radius)' : 'disc(r=$radius)',
    GParticleShapeKind.line => 'line($x1,$y1 -> $x2,$y2)',
    GParticleShapeKind.path => 'path',
  };
}

/// Retained lightweight diagnostics for one emitter.
final class GParticleStats {
  GParticleStats._(this.capacity);

  final int capacity;

  int active = 0;
  int spawnedLastFrame = 0;
  int droppedLastFrame = 0;
  int recycledLastFrame = 0;
  int totalSpawned = 0;
  int simulationMicros = 0;
  int packingMicros = 0;
  int paintMicros = 0;
  int drawCalls = 0;
  int submittedParticles = 0;

  void _beginFrame() {
    spawnedLastFrame = 0;
    droppedLastFrame = 0;
    recycledLastFrame = 0;
    simulationMicros = 0;
    packingMicros = 0;
    paintMicros = 0;
    drawCalls = 0;
    submittedParticles = 0;
  }
}

int _packColor(ui.Color source) {
  final color = source.colorSpace == ui.ColorSpace.sRGB
      ? source
      : source.withValues(colorSpace: ui.ColorSpace.sRGB);
  return (_colorByte(color.a) << 24) |
      (_colorByte(color.r) << 16) |
      (_colorByte(color.g) << 8) |
      _colorByte(color.b);
}

int _colorByte(double value) => (value * 255.0).round().clamp(0, 255).toInt();

int _lerpPackedColor(int a, int b, double t) {
  final ai = (a >>> 24) & 0xff;
  final ar = (a >>> 16) & 0xff;
  final ag = (a >>> 8) & 0xff;
  final ab = a & 0xff;
  final bi = (b >>> 24) & 0xff;
  final br = (b >>> 16) & 0xff;
  final bg = (b >>> 8) & 0xff;
  final bb = b & 0xff;
  return ((ai + (bi - ai) * t).round() << 24) |
      ((ar + (br - ar) * t).round() << 16) |
      ((ag + (bg - ag) * t).round() << 8) |
      (ab + (bb - ab) * t).round();
}

int _multiplyPackedColor(int a, int b, [double alpha = 1.0]) {
  final aa = (a >>> 24) & 0xff;
  final ar = (a >>> 16) & 0xff;
  final ag = (a >>> 8) & 0xff;
  final ab = a & 0xff;
  final ba = (b >>> 24) & 0xff;
  final br = (b >>> 16) & 0xff;
  final bg = (b >>> 8) & 0xff;
  final bb = b & 0xff;
  final outA = (aa * ba * alpha / 255.0).round().clamp(0, 255).toInt();
  return (outA << 24) |
      (((ar * br + 127) ~/ 255) << 16) |
      (((ag * bg + 127) ~/ 255) << 8) |
      ((ab * bb + 127) ~/ 255);
}

int _multiplyPackedAlpha(int color, double alpha) {
  if (alpha >= 1.0) return color;
  if (alpha <= 0.0) return color & 0x00ffffff;
  final a = (color >>> 24) & 0xff;
  final next = (a * alpha).round().clamp(0, 255).toInt();
  return (color & 0x00ffffff) | (next << 24);
}
