import 'dart:typed_data';

/// Optional fixed-capacity history storage for particle trails.
///
/// The allocation exists only while an emitter has trail rendering enabled.
/// [samples] is the total visual point budget including the particle's current
/// position, so retained history stores [samples] - 1 older anchors.
final class ParticleTrailStore {
  ParticleTrailStore(this.capacity, this.samples, this.duration)
    : historySamples = samples - 1,
      sampleInterval = duration / (samples - 1),
      x = Float32List(capacity * (samples - 1)),
      y = Float32List(capacity * (samples - 1)),
      head = Uint16List(capacity),
      length = Uint16List(capacity),
      sampleOrdinal = Uint32List(capacity) {
    if (samples < 2 || samples > 16) {
      throw ArgumentError.value(samples, 'samples', 'must be within 2..16');
    }
    if (!duration.isFinite || duration <= 0.0) {
      throw ArgumentError.value(duration, 'duration', 'must be finite and > 0');
    }
  }

  final int capacity;
  final int samples;
  final int historySamples;
  final double duration;
  final double sampleInterval;
  final Float32List x;
  final Float32List y;

  /// Next history-ring slot to write for each dense particle slot.
  final Uint16List head;

  /// Valid retained anchors for each dense particle slot.
  final Uint16List length;

  /// Number of fixed-interval anchors emitted since particle birth.
  ///
  /// Integer phase avoids refresh-rate-dependent drift from repeatedly adding
  /// a floating-point interval accumulator.
  final Uint32List sampleOrdinal;

  /// Monotonic change version consumed by the retained renderer.
  int version = 0;

  void add(int particle, double px, double py) {
    final base = particle * historySamples;
    x[base] = px;
    y[base] = py;
    head[particle] = historySamples == 1 ? 0 : 1;
    length[particle] = 1;
    sampleOrdinal[particle] = 0;
    version++;
  }

  /// Records fixed-time history anchors crossed by one simulation step.
  ///
  /// [age0] and [age1] are particle ages before and after the step. Anchor
  /// times are derived from an integer ordinal (`n * sampleInterval`) so the
  /// same trajectory retains the same sampling phase across refresh rates.
  void recordStep(
    int particle,
    double x0,
    double y0,
    double x1,
    double y1,
    double age0,
    double age1,
  ) {
    final dt = age1 - age0;
    if (dt <= 0.0) return;

    // Particle age is Float32 storage. Admit a mathematically exact boundary
    // when the stored age lands a few ULPs below it; the tolerance is tiny
    // relative to one authored sample interval and is never accumulated.
    final epsilon = sampleInterval * 1e-5 + 1e-12;
    var ordinal = sampleOrdinal[particle];
    var sampleAge = (ordinal + 1) * sampleInterval;
    while (sampleAge <= age1 + epsilon) {
      if (sampleAge >= age0 - epsilon) {
        final t = ((sampleAge - age0) / dt).clamp(0.0, 1.0).toDouble();
        _push(
          particle,
          x0 + (x1 - x0) * t,
          y0 + (y1 - y0) * t,
        );
      }
      ordinal++;
      sampleAge = (ordinal + 1) * sampleInterval;
    }
    sampleOrdinal[particle] = ordinal;
  }

  void markMoved() => version++;

  void _push(int particle, double px, double py) {
    final slot = head[particle];
    final index = particle * historySamples + slot;
    x[index] = px;
    y[index] = py;
    head[particle] = slot + 1 == historySamples ? 0 : slot + 1;
    if (length[particle] < historySamples) length[particle]++;
  }

  /// Copies the history of [last] into [removed] before dense storage shrinks.
  void removeAt(int removed, int last) {
    if (removed != last) {
      final source = last * historySamples;
      final target = removed * historySamples;
      x.setRange(target, target + historySamples, x, source);
      y.setRange(target, target + historySamples, y, source);
      head[removed] = head[last];
      length[removed] = length[last];
      sampleOrdinal[removed] = sampleOrdinal[last];
    }
    head[last] = 0;
    length[last] = 0;
    sampleOrdinal[last] = 0;
    version++;
  }

  void clear() {
    head.fillRange(0, capacity, 0);
    length.fillRange(0, capacity, 0);
    sampleOrdinal.fillRange(0, capacity, 0);
    version++;
  }

  /// Returns the Nth newest retained anchor, where 0 is the newest history
  /// sample behind the live particle position.
  int sampleIndex(int particle, int ageFromNewest) {
    final valid = length[particle];
    if (ageFromNewest < 0 || ageFromNewest >= valid) return -1;
    var slot = head[particle] - 1 - ageFromNewest;
    while (slot < 0) {
      slot += historySamples;
    }
    return particle * historySamples + slot;
  }
}
