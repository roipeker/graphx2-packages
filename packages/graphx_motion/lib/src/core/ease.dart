part of '../../motion.dart';

/// Allocation-free easing callback used directly by the Motion hot path.
typedef EaseFunction = double Function(double t);

/// Discoverable in/out/in-out family of easing callbacks.
final class EaseFamily {
  const EaseFamily({
    required this.easeIn,
    required this.easeOut,
    required this.easeInOut,
  });

  final EaseFunction easeIn;
  final EaseFunction easeOut;
  final EaseFunction easeInOut;
}

/// Broad easing catalog. Family members are cached callbacks; configured
/// curves allocate only at setup and still resolve to one [EaseFunction].
abstract final class Ease {
  static double linear(double t) => t;

  static final EaseFamily quad = EaseFamily(
    easeIn: _quadIn,
    easeOut: _quadOut,
    easeInOut: _quadInOut,
  );
  static final EaseFamily cubic = EaseFamily(
    easeIn: _cubicIn,
    easeOut: _cubicOut,
    easeInOut: _cubicInOut,
  );
  static final EaseFamily quart = EaseFamily(
    easeIn: _quartIn,
    easeOut: _quartOut,
    easeInOut: _quartInOut,
  );
  static final EaseFamily quint = EaseFamily(
    easeIn: _quintIn,
    easeOut: _quintOut,
    easeInOut: _quintInOut,
  );
  static final EaseFamily sine = EaseFamily(
    easeIn: _sineIn,
    easeOut: _sineOut,
    easeInOut: _sineInOut,
  );
  static final EaseFamily expo = EaseFamily(
    easeIn: _expoIn,
    easeOut: _expoOut,
    easeInOut: _expoInOut,
  );
  static final EaseFamily circ = EaseFamily(
    easeIn: _circIn,
    easeOut: _circOut,
    easeInOut: _circInOut,
  );
  static final EaseFamily back = EaseFamily(
    easeIn: _backIn,
    easeOut: _backOut,
    easeInOut: _backInOut,
  );
  static final EaseFamily bounce = EaseFamily(
    easeIn: _bounceIn,
    easeOut: _bounceOut,
    easeInOut: _bounceInOut,
  );
  static final EaseFamily elastic = EaseFamily(
    easeIn: _elasticIn,
    easeOut: _elasticOut,
    easeInOut: _elasticInOut,
  );

  /// CSS-style cubic Bezier easing. X control points are solved for time.
  static EaseFunction bezier(double x1, double y1, double x2, double y2) =>
      _CubicBezier(x1, y1, x2, y2).transform;

  /// Quantizes normalized progress into [count] equal steps.
  static EaseFunction steps(int count, {bool jumpAtStart = false}) {
    if (count <= 0) throw ArgumentError.value(count, 'count', 'Must be > 0.');
    return (t) {
      if (t <= 0.0) return jumpAtStart ? 1.0 / count : 0.0;
      if (t >= 1.0) return 1.0;
      final scaled = t * count;
      final step = jumpAtStart ? scaled.ceil() : scaled.floor();
      return step / count;
    };
  }

  /// Configured Back family. Default cached family is [back].
  static EaseFamily backWith({double overshoot = 1.70158}) {
    return EaseFamily(
      easeIn: (t) => _backInWith(t, overshoot),
      easeOut: (t) => _backOutWith(t, overshoot),
      easeInOut: (t) => _backInOutWith(t, overshoot),
    );
  }

  /// Configured Elastic family. Default cached family is [elastic].
  static EaseFamily elasticWith({double amplitude = 1.0, double period = 0.3}) {
    if (!amplitude.isFinite || amplitude <= 0.0) {
      throw ArgumentError.value(amplitude, 'amplitude', 'Must be finite and > 0.');
    }
    if (!period.isFinite || period <= 0.0) {
      throw ArgumentError.value(period, 'period', 'Must be finite and > 0.');
    }
    return EaseFamily(
      easeIn: (t) => _elasticInWith(t, amplitude, period),
      easeOut: (t) => _elasticOutWith(t, amplitude, period),
      easeInOut: (t) => _elasticInOutWith(t, amplitude, period),
    );
  }

  // Compatibility aliases while callers migrate to the discoverable families.
  static double quadIn(double t) => _quadIn(t);
  static double quadOut(double t) => _quadOut(t);
  static double quadInOut(double t) => _quadInOut(t);
  static double cubicIn(double t) => _cubicIn(t);
  static double cubicOut(double t) => _cubicOut(t);
  static double cubicInOut(double t) => _cubicInOut(t);
  static double sineIn(double t) => _sineIn(t);
  static double sineOut(double t) => _sineOut(t);
  static double sineInOut(double t) => _sineInOut(t);
  static double expoOut(double t) => _expoOut(t);
  static double backOut(double t) => _backOut(t);
}

double _quadIn(double t) => t * t;
double _quadOut(double t) => 1.0 - (1.0 - t) * (1.0 - t);
double _quadInOut(double t) =>
    t < 0.5 ? 2.0 * t * t : 1.0 - math.pow(-2.0 * t + 2.0, 2).toDouble() * 0.5;

double _cubicIn(double t) => t * t * t;
double _cubicOut(double t) => 1.0 - math.pow(1.0 - t, 3).toDouble();
double _cubicInOut(double t) =>
    t < 0.5 ? 4.0 * t * t * t : 1.0 - math.pow(-2.0 * t + 2.0, 3).toDouble() * 0.5;

double _quartIn(double t) => t * t * t * t;
double _quartOut(double t) => 1.0 - math.pow(1.0 - t, 4).toDouble();
double _quartInOut(double t) =>
    t < 0.5 ? 8.0 * t * t * t * t : 1.0 - math.pow(-2.0 * t + 2.0, 4).toDouble() * 0.5;

double _quintIn(double t) => t * t * t * t * t;
double _quintOut(double t) => 1.0 - math.pow(1.0 - t, 5).toDouble();
double _quintInOut(double t) =>
    t < 0.5 ? 16.0 * t * t * t * t * t : 1.0 - math.pow(-2.0 * t + 2.0, 5).toDouble() * 0.5;

double _sineIn(double t) => 1.0 - math.cos(t * math.pi * 0.5);
double _sineOut(double t) => math.sin(t * math.pi * 0.5);
double _sineInOut(double t) => 0.5 * (1.0 - math.cos(math.pi * t));

double _expoIn(double t) => t <= 0.0 ? 0.0 : math.pow(2.0, 10.0 * t - 10.0).toDouble();
double _expoOut(double t) => t >= 1.0 ? 1.0 : 1.0 - math.pow(2.0, -10.0 * t).toDouble();
double _expoInOut(double t) {
  if (t <= 0.0) return 0.0;
  if (t >= 1.0) return 1.0;
  return t < 0.5
      ? math.pow(2.0, 20.0 * t - 10.0).toDouble() * 0.5
      : (2.0 - math.pow(2.0, -20.0 * t + 10.0).toDouble()) * 0.5;
}

double _circIn(double t) => 1.0 - math.sqrt(1.0 - t * t);
double _circOut(double t) => math.sqrt(1.0 - (t - 1.0) * (t - 1.0));
double _circInOut(double t) => t < 0.5
    ? (1.0 - math.sqrt(1.0 - 4.0 * t * t)) * 0.5
    : (math.sqrt(1.0 - math.pow(-2.0 * t + 2.0, 2).toDouble()) + 1.0) * 0.5;

const _backDefault = 1.70158;
double _backIn(double t) => _backInWith(t, _backDefault);
double _backOut(double t) => _backOutWith(t, _backDefault);
double _backInOut(double t) => _backInOutWith(t, _backDefault);
double _backInWith(double t, double s) => (s + 1.0) * t * t * t - s * t * t;
double _backOutWith(double t, double s) {
  final u = t - 1.0;
  return 1.0 + (s + 1.0) * u * u * u + s * u * u;
}

double _backInOutWith(double t, double s) {
  final c = s * 1.525;
  return t < 0.5
      ? math.pow(2.0 * t, 2).toDouble() * (((c + 1.0) * 2.0 * t) - c) * 0.5
      : (math.pow(2.0 * t - 2.0, 2).toDouble() * (((c + 1.0) * (t * 2.0 - 2.0)) + c) + 2.0) * 0.5;
}

double _bounceOut(double t) {
  const n1 = 7.5625;
  const d1 = 2.75;
  if (t < 1.0 / d1) return n1 * t * t;
  if (t < 2.0 / d1) {
    final u = t - 1.5 / d1;
    return n1 * u * u + 0.75;
  }
  if (t < 2.5 / d1) {
    final u = t - 2.25 / d1;
    return n1 * u * u + 0.9375;
  }
  final u = t - 2.625 / d1;
  return n1 * u * u + 0.984375;
}

double _bounceIn(double t) => 1.0 - _bounceOut(1.0 - t);
double _bounceInOut(double t) =>
    t < 0.5 ? (1.0 - _bounceOut(1.0 - 2.0 * t)) * 0.5 : (1.0 + _bounceOut(2.0 * t - 1.0)) * 0.5;

double _elasticIn(double t) => _elasticInWith(t, 1.0, 0.3);
double _elasticOut(double t) => _elasticOutWith(t, 1.0, 0.3);
double _elasticInOut(double t) => _elasticInOutWith(t, 1.0, 0.3);

double _elasticPhase(double amplitude, double period) {
  final a = math.max(1.0, amplitude);
  return period / (2.0 * math.pi) * math.asin(1.0 / a);
}

double _elasticInWith(double t, double amplitude, double period) {
  if (t <= 0.0 || t >= 1.0) return t;
  final a = math.max(1.0, amplitude);
  final s = _elasticPhase(a, period);
  return -a *
      math.pow(2.0, 10.0 * t - 10.0).toDouble() *
      math.sin((t - 1.0 - s) * (2.0 * math.pi) / period);
}

double _elasticOutWith(double t, double amplitude, double period) {
  if (t <= 0.0 || t >= 1.0) return t;
  final a = math.max(1.0, amplitude);
  final s = _elasticPhase(a, period);
  return a * math.pow(2.0, -10.0 * t).toDouble() * math.sin((t - s) * (2.0 * math.pi) / period) +
      1.0;
}

double _elasticInOutWith(double t, double amplitude, double period) {
  if (t <= 0.0 || t >= 1.0) return t;
  final a = math.max(1.0, amplitude);
  final p = period * 1.5;
  final s = _elasticPhase(a, p);
  final u = t * 2.0;
  if (u < 1.0) {
    return -0.5 *
        a *
        math.pow(2.0, 10.0 * u - 10.0).toDouble() *
        math.sin((u - 1.0 - s) * (2.0 * math.pi) / p);
  }
  final v = u - 1.0;
  return a * math.pow(2.0, -10.0 * v).toDouble() * math.sin((v - s) * (2.0 * math.pi) / p) * 0.5 +
      1.0;
}

final class _CubicBezier {
  const _CubicBezier(this.x1, this.y1, this.x2, this.y2);

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  double transform(double value) {
    if (value <= 0.0) return 0.0;
    if (value >= 1.0) return 1.0;
    return _sampleY(_solve(value));
  }

  double _sampleX(double t) =>
      3.0 * (1.0 - t) * (1.0 - t) * t * x1 + 3.0 * (1.0 - t) * t * t * x2 + t * t * t;

  double _sampleY(double t) =>
      3.0 * (1.0 - t) * (1.0 - t) * t * y1 + 3.0 * (1.0 - t) * t * t * y2 + t * t * t;

  double _sampleDx(double t) =>
      3.0 * (1.0 - t) * (1.0 - t) * x1 + 6.0 * (1.0 - t) * t * (x2 - x1) + 3.0 * t * t * (1.0 - x2);

  double _solve(double x) {
    var t = x;
    for (var i = 0; i < 6; i++) {
      final dx = _sampleDx(t);
      if (dx.abs() < 1e-6) break;
      t -= (_sampleX(t) - x) / dx;
      if (t < 0.0 || t > 1.0) break;
    }

    var lo = 0.0;
    var hi = 1.0;
    t = x.clamp(0.0, 1.0).toDouble();
    for (var i = 0; i < 10; i++) {
      final sample = _sampleX(t);
      if ((sample - x).abs() < 1e-6) return t;
      if (sample < x) {
        lo = t;
      } else {
        hi = t;
      }
      t = (lo + hi) * 0.5;
    }
    return t;
  }
}
