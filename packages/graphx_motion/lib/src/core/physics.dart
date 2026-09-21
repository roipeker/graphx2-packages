part of '../../motion.dart';

/// Settle-driven physics family used by [MotionEngine].
sealed class MotionPhysics {
  const MotionPhysics();

  MotionKind get kind;
  void validate();

  bool _step(
    _DoubleTrack track,
    double deltaTime, {
    required double physicsStep,
    required int maxPhysicsSteps,
  });

  void _terminal(_DoubleTrack track);
}

/// Linear damped spring solved analytically for a constant target over each
/// frame. It is stable across under-, critical-, and over-damped ranges and
/// requires no iterative spring substeps.
final class Spring extends MotionPhysics {
  const Spring({
    this.stiffness = 170.0,
    this.damping = 26.0,
    this.mass = 1.0,
    this.tolerance = 0.001,
    this.velocityTolerance = 0.001,
  });

  final double stiffness;
  final double damping;
  final double mass;
  final double tolerance;
  final double velocityTolerance;

  static const snappy = Spring(stiffness: 250.0, damping: 25.0);
  static const gentle = Spring(stiffness: 120.0, damping: 14.0);
  static const wobbly = Spring(stiffness: 180.0, damping: 12.0);
  static const stiff = Spring(stiffness: 400.0, damping: 35.0);
  static const slow = Spring(stiffness: 80.0, damping: 18.0);

  @override
  MotionKind get kind => MotionKind.spring;

  @override
  void validate() {
    if (!stiffness.isFinite || stiffness <= 0.0) {
      throw ArgumentError.value(stiffness, 'stiffness', 'Must be finite and > 0.');
    }
    if (!damping.isFinite || damping < 0.0) {
      throw ArgumentError.value(damping, 'damping', 'Must be finite and >= 0.');
    }
    if (!mass.isFinite || mass <= 0.0) {
      throw ArgumentError.value(mass, 'mass', 'Must be finite and > 0.');
    }
    _validateTolerance(tolerance, 'tolerance');
    _validateTolerance(velocityTolerance, 'velocityTolerance');
  }

  @override
  bool _step(
    _DoubleTrack track,
    double deltaTime, {
    required double physicsStep,
    required int maxPhysicsSteps,
  }) {
    if (deltaTime <= 0.0) return !_settled(track);

    final target = track.end;
    final displacement = track.value - target;
    final velocity = track.velocity;
    final omega0 = math.sqrt(stiffness / mass);
    final zeta = damping / (2.0 * math.sqrt(stiffness * mass));

    late final double nextDisplacement;
    late final double nextVelocity;

    if ((zeta - 1.0).abs() <= 1e-4) {
      final decay = math.exp(-omega0 * deltaTime);
      final b = velocity + omega0 * displacement;
      nextDisplacement = decay * (displacement + b * deltaTime);
      nextVelocity = decay * (velocity - omega0 * b * deltaTime);
    } else if (zeta < 1.0) {
      final omegaD = omega0 * math.sqrt(1.0 - zeta * zeta);
      final decayRate = zeta * omega0;
      final decay = math.exp(-decayRate * deltaTime);
      final angle = omegaD * deltaTime;
      final cosValue = math.cos(angle);
      final sinValue = math.sin(angle);
      final a = displacement;
      final b = (velocity + decayRate * displacement) / omegaD;
      final wave = a * cosValue + b * sinValue;
      nextDisplacement = decay * wave;
      nextVelocity = decay * (-decayRate * wave - a * omegaD * sinValue + b * omegaD * cosValue);
    } else {
      final root = math.sqrt(zeta * zeta - 1.0);
      final r1 = -omega0 * (zeta - root);
      final r2 = -omega0 * (zeta + root);
      final c1 = (velocity - r2 * displacement) / (r1 - r2);
      final c2 = displacement - c1;
      final e1 = math.exp(r1 * deltaTime);
      final e2 = math.exp(r2 * deltaTime);
      nextDisplacement = c1 * e1 + c2 * e2;
      nextVelocity = c1 * r1 * e1 + c2 * r2 * e2;
    }

    track.value = target + nextDisplacement;
    track.velocity = nextVelocity;

    if (_settled(track)) {
      track.value = target;
      track.velocity = 0.0;
      return false;
    }
    return true;
  }

  bool _settled(_DoubleTrack track) =>
      (track.value - track.end).abs() <= tolerance && track.velocity.abs() <= velocityTolerance;

  @override
  void _terminal(_DoubleTrack track) {
    track.value = track.end;
    track.velocity = 0.0;
  }
}

/// Frame-rate independent exponential chase toward a target.
/// [response] is the seconds required to halve the remaining error.
final class Damp extends MotionPhysics {
  const Damp({this.response = 0.08, this.tolerance = 0.001});

  final double response;
  final double tolerance;

  @override
  MotionKind get kind => MotionKind.damp;

  @override
  void validate() {
    if (!response.isFinite || response < 0.0) {
      throw ArgumentError.value(response, 'response', 'Must be finite and >= 0.');
    }
    _validateTolerance(tolerance, 'tolerance');
  }

  @override
  bool _step(
    _DoubleTrack track,
    double deltaTime, {
    required double physicsStep,
    required int maxPhysicsSteps,
  }) {
    final target = track.end;
    if (response <= 0.0) {
      track.value = target;
      track.velocity = 0.0;
      return false;
    }
    final decay = math.exp(-0.6931471805599453 * deltaTime / response);
    track.value = target + (track.value - target) * decay;
    track.velocity = 0.0;
    if ((target - track.value).abs() <= tolerance) {
      track.value = target;
      return false;
    }
    return true;
  }

  @override
  void _terminal(_DoubleTrack track) {
    track.value = track.end;
    track.velocity = 0.0;
  }
}

/// Free-running velocity decay with optional acceleration and bounds.
///
/// Unbounded motion uses the exact exponential solution. Bounded/bouncing
/// motion subdivides only for boundary handling.
final class Inertia extends MotionPhysics {
  const Inertia({
    this.friction = 5.0,
    this.acceleration = 0.0,
    this.min = double.negativeInfinity,
    this.max = double.infinity,
    this.bounce = 0.0,
    this.tolerance = 0.01,
  });

  final double friction;
  final double acceleration;
  final double min;
  final double max;
  final double bounce;
  final double tolerance;

  @override
  MotionKind get kind => MotionKind.inertia;

  @override
  void validate() {
    if (!friction.isFinite || friction < 0.0) {
      throw ArgumentError.value(friction, 'friction', 'Must be finite and >= 0.');
    }
    if (!acceleration.isFinite) {
      throw ArgumentError.value(acceleration, 'acceleration', 'Must be finite.');
    }
    if (min.isNaN || max.isNaN || min > max) {
      throw ArgumentError('Inertia bounds must satisfy min <= max.');
    }
    if (!bounce.isFinite || bounce < 0.0 || bounce > 1.0) {
      throw ArgumentError.value(bounce, 'bounce', 'Must be between 0 and 1.');
    }
    _validateTolerance(tolerance, 'tolerance');
  }

  @override
  bool _step(
    _DoubleTrack track,
    double deltaTime, {
    required double physicsStep,
    required int maxPhysicsSteps,
  }) {
    if (deltaTime <= 0.0) return _isAlive(track);

    final bounded = min.isFinite || max.isFinite;
    if (!bounded) {
      _integrate(track, deltaTime);
      if (acceleration == 0.0 && track.velocity.abs() <= tolerance) {
        if (friction > 0.0) track.value += track.velocity / friction;
        track.velocity = 0.0;
        return false;
      }
      return true;
    }

    final preferred = physicsStep > 0.0 ? physicsStep : deltaTime;
    var steps = (deltaTime / preferred).ceil();
    if (steps < 1) steps = 1;
    if (maxPhysicsSteps > 0 && steps > maxPhysicsSteps) {
      steps = maxPhysicsSteps;
    }
    final dt = deltaTime / steps;

    for (var i = 0; i < steps; ++i) {
      _integrate(track, dt);
      if (track.value < min) {
        track.value = min;
        if (track.velocity < 0.0) {
          track.velocity = bounce == 0.0 ? 0.0 : -track.velocity * bounce;
        }
      } else if (track.value > max) {
        track.value = max;
        if (track.velocity > 0.0) {
          track.velocity = bounce == 0.0 ? 0.0 : -track.velocity * bounce;
        }
      }
    }

    if (_restingAtBound(track)) {
      track.velocity = 0.0;
      return false;
    }
    if (acceleration == 0.0 && track.velocity.abs() <= tolerance) {
      if (friction > 0.0) {
        track.value = (track.value + track.velocity / friction).clamp(min, max).toDouble();
      }
      track.velocity = 0.0;
      return false;
    }
    return true;
  }

  void _integrate(_DoubleTrack track, double dt) {
    final velocity = track.velocity;
    if (friction > 0.0) {
      final decay = math.exp(-friction * dt);
      final terminalVelocity = acceleration / friction;
      final offsetVelocity = velocity - terminalVelocity;
      track.value += terminalVelocity * dt + offsetVelocity * (1.0 - decay) / friction;
      track.velocity = terminalVelocity + offsetVelocity * decay;
      return;
    }
    track.value += velocity * dt + 0.5 * acceleration * dt * dt;
    track.velocity = velocity + acceleration * dt;
  }

  bool _restingAtBound(_DoubleTrack track) {
    if (track.velocity != 0.0) return false;
    if (track.value <= min && acceleration <= 0.0) return true;
    if (track.value >= max && acceleration >= 0.0) return true;
    return false;
  }

  bool _isAlive(_DoubleTrack track) {
    if (_restingAtBound(track)) return false;
    return acceleration != 0.0 || track.velocity.abs() > tolerance;
  }

  @override
  void _terminal(_DoubleTrack track) {
    track.velocity = 0.0;
  }
}

/// Optional per-axis bounds used by typed inertia facades.
final class MotionBounds {
  const MotionBounds(this.min, this.max, {this.bounce = 0.0});

  final double min;
  final double max;
  final double bounce;

  Inertia inertia({
    double friction = 5.0,
    double acceleration = 0.0,
    double tolerance = 0.01,
  }) => Inertia(
    friction: friction,
    acceleration: acceleration,
    min: min,
    max: max,
    bounce: bounce,
    tolerance: tolerance,
  );
}

extension MotionEnginePhysics on MotionEngine {
  MotionHandle springDouble(
    double Function() read,
    void Function(double value) write,
    double to, {
    Spring spring = Spring.snappy,
    double initialVelocity = 0.0,
    double delay = 0.0,
    Overwrite overwrite = Overwrite.auto,
    Object? owner,
    Object? hook,
    MotionPropertyKey? property,
    bool shortest = false,
    double period = math.pi * 2.0,
    bool inheritVelocity = true,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    return _physicsProperties(
      <DoubleMotionProperty>[
        DoubleMotionProperty(
          read: read,
          write: write,
          to: to,
          property: property,
          shortest: shortest,
          period: period,
        ),
      ],
      spring,
      initialVelocity: initialVelocity,
      delay: delay,
      overwrite: overwrite,
      owner: owner,
      hook: hook,
      inheritVelocity: inheritVelocity,
      sample: sample,
      snap: snap,
      clamp: clamp,
      onStart: onStart,
      onUpdate: onUpdate,
      onSettled: onSettled,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }

  MotionHandle springProperties(
    Iterable<DoubleMotionProperty> properties, {
    Spring spring = Spring.snappy,
    double initialVelocity = 0.0,
    double delay = 0.0,
    Overwrite overwrite = Overwrite.auto,
    Object? owner,
    Object? hook,
    bool inheritVelocity = true,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) => _physicsProperties(
    properties,
    spring,
    initialVelocity: initialVelocity,
    delay: delay,
    overwrite: overwrite,
    owner: owner,
    hook: hook,
    inheritVelocity: inheritVelocity,
    sample: sample,
    snap: snap,
    clamp: clamp,
    onStart: onStart,
    onUpdate: onUpdate,
    onSettled: onSettled,
    onComplete: onComplete,
    onCancel: onCancel,
  );

  MotionHandle dampDouble(
    double Function() read,
    void Function(double value) write,
    double to, {
    Damp damp = const Damp(),
    double delay = 0.0,
    Overwrite overwrite = Overwrite.auto,
    Object? owner,
    Object? hook,
    MotionPropertyKey? property,
    bool shortest = false,
    double period = math.pi * 2.0,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    return _physicsProperties(
      <DoubleMotionProperty>[
        DoubleMotionProperty(
          read: read,
          write: write,
          to: to,
          property: property,
          shortest: shortest,
          period: period,
        ),
      ],
      damp,
      delay: delay,
      overwrite: overwrite,
      owner: owner,
      hook: hook,
      sample: sample,
      snap: snap,
      clamp: clamp,
      onStart: onStart,
      onUpdate: onUpdate,
      onSettled: onSettled,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }

  MotionHandle dampProperties(
    Iterable<DoubleMotionProperty> properties, {
    Damp damp = const Damp(),
    double delay = 0.0,
    Overwrite overwrite = Overwrite.auto,
    Object? owner,
    Object? hook,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) => _physicsProperties(
    properties,
    damp,
    delay: delay,
    overwrite: overwrite,
    owner: owner,
    hook: hook,
    sample: sample,
    snap: snap,
    clamp: clamp,
    onStart: onStart,
    onUpdate: onUpdate,
    onSettled: onSettled,
    onComplete: onComplete,
    onCancel: onCancel,
  );

  MotionHandle inertiaDouble(
    double Function() read,
    void Function(double value) write, {
    required double velocity,
    Inertia inertia = const Inertia(),
    double delay = 0.0,
    Overwrite overwrite = Overwrite.auto,
    Object? owner,
    Object? hook,
    MotionPropertyKey? property,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) => inertiaProperties(
    <DoubleInertiaProperty>[
      DoubleInertiaProperty(
        read: read,
        write: write,
        velocity: velocity,
        property: property,
        inertia: inertia,
      ),
    ],
    delay: delay,
    overwrite: overwrite,
    owner: owner,
    hook: hook,
    sample: sample,
    snap: snap,
    clamp: clamp,
    onStart: onStart,
    onUpdate: onUpdate,
    onSettled: onSettled,
    onComplete: onComplete,
    onCancel: onCancel,
  );

  MotionHandle inertiaProperties(
    Iterable<DoubleInertiaProperty> properties, {
    double delay = 0.0,
    Overwrite overwrite = Overwrite.auto,
    Object? owner,
    Object? hook,
    MotionSample? sample,
    MotionSnap? snap,
    MotionClamp? clamp,
    void Function()? onStart,
    void Function()? onUpdate,
    void Function()? onSettled,
    void Function()? onComplete,
    void Function(MotionCancelReason reason)? onCancel,
  }) {
    _checkAlive();
    _validatePhysicsStart(delay, overwrite, owner);
    final runtime = _acquireRuntime();
    _configureRuntime(
      runtime,
      owner: owner,
      hook: hook,
      duration: 0.0,
      ease: Ease.linear,
      delay: delay,
      repeat: 0,
      repeatDelay: 0.0,
      yoyo: false,
      onStart: onStart,
      onUpdate: onUpdate,
      onRepeat: null,
      onComplete: onComplete,
      onSettled: onSettled,
      onCancel: onCancel,
    );
    runtime.kind = MotionKind.inertia;

    try {
      for (final descriptor in properties) {
        descriptor.inertia.validate();
        final start = descriptor.read();
        _validateFinite(start, 'start');
        _validateFinite(descriptor.velocity, 'velocity');
        final track = _acquireTrack();
        track.property = descriptor.property;
        track.write = descriptor.write;
        track.start = start;
        track.end = start;
        track.value = start;
        track.velocity = descriptor.velocity;
        track.physics = descriptor.inertia;
        track.sample = sample;
        track.snap = snap;
        track.clamp = clamp;
        runtime.tracks.add(track);
      }
    } catch (_) {
      _releaseRuntime(runtime);
      rethrow;
    }

    return _finishPhysicsStart(runtime, overwrite, onSettled);
  }

  MotionHandle _physicsProperties(
    Iterable<DoubleMotionProperty> properties,
    MotionPhysics physics, {
    double initialVelocity = 0.0,
    required double delay,
    required Overwrite overwrite,
    required Object? owner,
    required Object? hook,
    bool inheritVelocity = false,
    required MotionSample? sample,
    required MotionSnap? snap,
    required MotionClamp? clamp,
    required void Function()? onStart,
    required void Function()? onUpdate,
    required void Function()? onSettled,
    required void Function()? onComplete,
    required void Function(MotionCancelReason reason)? onCancel,
  }) {
    _checkAlive();
    physics.validate();
    _validatePhysicsStart(delay, overwrite, owner);
    _validateFinite(initialVelocity, 'initialVelocity');

    final runtime = _acquireRuntime();
    _configureRuntime(
      runtime,
      owner: owner,
      hook: hook,
      duration: 0.0,
      ease: Ease.linear,
      delay: delay,
      repeat: 0,
      repeatDelay: 0.0,
      yoyo: false,
      onStart: onStart,
      onUpdate: onUpdate,
      onRepeat: null,
      onComplete: onComplete,
      onSettled: onSettled,
      onCancel: onCancel,
    );
    runtime.kind = physics.kind;
    runtime.inheritVelocity = inheritVelocity;

    try {
      for (final descriptor in properties) {
        final start = descriptor.from ?? descriptor.read();
        _validateFinite(start, 'start');
        _validateFinite(descriptor.to, 'to');
        final end = _resolveCircularEnd(
          start,
          descriptor.to,
          descriptor.shortest,
          descriptor.period,
        );
        _validateFinite(end, 'resolved target');
        final track = _acquireTrack();
        track.property = descriptor.property;
        track.write = descriptor.write;
        track.start = start;
        track.end = end;
        track.value = start;
        track.velocity = initialVelocity;
        track.physics = physics;
        track.sample = sample;
        track.snap = snap;
        track.clamp = clamp;
        runtime.tracks.add(track);
      }
    } catch (_) {
      _releaseRuntime(runtime);
      rethrow;
    }

    return _finishPhysicsStart(runtime, overwrite, onSettled);
  }

  MotionHandle _finishPhysicsStart(
    _MotionRuntime runtime,
    Overwrite overwrite,
    void Function()? onSettled,
  ) {
    if (runtime.tracks.isEmpty) {
      _releaseRuntime(runtime);
      onSettled?.call();
      return MotionHandle._completed();
    }
    final handle = _bind(runtime);
    _start(runtime, overwrite);
    return handle;
  }

  void _validatePhysicsStart(double delay, Overwrite overwrite, Object? owner) {
    if (!delay.isFinite || delay < 0.0) {
      throw ArgumentError.value(delay, 'delay', 'Must be finite and >= 0.');
    }
    if (overwrite == Overwrite.all && owner == null) {
      throw ArgumentError('Overwrite.all requires an owner.');
    }
  }
}

void _validateTolerance(double value, String name) {
  if (!value.isFinite || value < 0.0) {
    throw ArgumentError.value(value, name, 'Must be finite and >= 0.');
  }
}

void _validateFinite(double value, String name) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, name, 'Must be finite.');
  }
}
