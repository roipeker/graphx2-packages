part of 'package:graphx_arcade/graphx_arcade.dart';

final Expando<GArcadeWorld> _arcadeByStage = Expando<GArcadeWorld>('graphx.arcade.world');
final Expando<GBody> _bodyByNode = Expando<GBody>('graphx.arcade.body');
final Expando<GArcadeWorld> _arcadeBySpace = Expando<GArcadeWorld>('graphx.arcade.space');

/// Lightweight deterministic 2D arcade simulation.
///
/// The world owns simulation state. Bound [GNode]s are presentation handles;
/// dynamic bodies write node position after simulation while static/kinematic
/// bodies read authored node position before simulation.
final class GArcadeWorld {
  GArcadeWorld({
    double gravityX = 0,
    double gravityY = 0,
    double fixedStep = 1 / 60,
    int maxSubSteps = 4,
    bool interpolate = true,
  }) : _stage = null,
       _space = null,
       gravityX = gravityX,
       gravityY = gravityY,
       _fixedStep = _validateFixedStep(fixedStep),
       _maxSubSteps = _validateMaxSubSteps(maxSubSteps),
       interpolate = interpolate;

  GArcadeWorld.stage(
    GStage stage, {
    GNode? space,
    double gravityX = 0,
    double gravityY = 0,
    double fixedStep = 1 / 60,
    int maxSubSteps = 4,
    bool interpolate = true,
  }) : _stage = stage,
       _space = space ?? stage.root,
       gravityX = gravityX,
       gravityY = gravityY,
       _fixedStep = _validateFixedStep(fixedStep),
       _maxSubSteps = _validateMaxSubSteps(maxSubSteps),
       interpolate = interpolate {
    final resolvedSpace = _space!;
    if (resolvedSpace.isDisposed) {
      throw ArgumentError('Arcade space is disposed.');
    }
    if (resolvedSpace.isAttached && !identical(resolvedSpace.stage, stage)) {
      throw ArgumentError('Arcade space belongs to another Stage.');
    }
    _stageDisposeSubscription = stage.signals.onDispose.add(dispose, key: this);
    if (!identical(resolvedSpace, stage.root)) {
      _spaceDisposeSubscription = resolvedSpace.signals.onDispose.add(
        dispose,
        key: this,
      );
    }
  }

  final GStage? _stage;
  final GNode? _space;

  GStage? get stage => _stage;
  GNode? get space => _space;

  double gravityX;
  double gravityY;
  bool interpolate;

  double _fixedStep;
  int _maxSubSteps;
  bool _enabled = true;
  bool _disposed = false;
  double _accumulator = 0;
  int _stepSerial = 0;

  GSignalSubscription? _updateSubscription;
  GSignalSubscription? _stageDisposeSubscription;
  GSignalSubscription? _spaceDisposeSubscription;

  int _capacity = 0;
  int _slotCount = 0;
  int _bodyCount = 0;
  final List<int> _freeSlots = <int>[];

  Float64List _x = Float64List(0);
  Float64List _y = Float64List(0);
  Float64List _previousX = Float64List(0);
  Float64List _previousY = Float64List(0);
  Float64List _authoredX = Float64List(0);
  Float64List _authoredY = Float64List(0);
  Float64List _vx = Float64List(0);
  Float64List _vy = Float64List(0);
  Float64List _bounce = Float64List(0);
  Float64List _invMass = Float64List(0);
  Float64List _shapeA = Float64List(0);
  Float64List _shapeB = Float64List(0);
  Uint8List _type = Uint8List(0);
  Uint8List _flags = Uint8List(0);
  Uint8List _shapeKind = Uint8List(0);
  Uint32List _layer = Uint32List(0);
  Uint32List _mask = Uint32List(0);
  List<GBody?> _bodies = <GBody?>[];

  Int32List _sweepOrder = Int32List(0);
  int _sweepCount = 0;
  bool _sweepMembershipDirty = true;
  final GPoint _spacePointScratch = GPoint();
  final Map<int, _GContactState> _contacts = <int, _GContactState>{};
  final List<int> _staleContacts = <int>[];
  final List<_GContactState> _contactBegins = <_GContactState>[];
  final List<_GContactState> _contactEnds = <_GContactState>[];
  final _GSweepResult _sweepResult = _GSweepResult();
  GSignal<double>? _beforeStep;
  GSignal<double>? _afterStep;
  bool _stepping = false;
  bool _dispatchingContacts = false;
  bool _dispatchingStepHook = false;

  static double _validateFixedStep(double value) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(value, 'fixedStep');
    }
    return value;
  }

  static int _validateMaxSubSteps(int value) {
    if (value <= 0 || value > 64) {
      throw ArgumentError.value(value, 'maxSubSteps');
    }
    return value;
  }

  double get fixedStep => _fixedStep;
  set fixedStep(double value) {
    _checkAlive();
    _fixedStep = _validateFixedStep(value);
    _accumulator = 0;
  }

  int get maxSubSteps => _maxSubSteps;
  set maxSubSteps(int value) {
    _checkAlive();
    _maxSubSteps = _validateMaxSubSteps(value);
  }

  bool get enabled => _enabled;
  set enabled(bool value) {
    _checkAlive();
    if (_enabled == value) return;
    _enabled = value;
    if (value) {
      _refreshWake();
    } else {
      _sleep();
    }
  }

  int get bodyCount => _bodyCount;

  /// Emits immediately before every fixed simulation step.
  ///
  /// Game/tool code may author velocity, spawn/destroy bodies or teleport from
  /// this callback. Re-entering [step] or [advance] from the callback is
  /// rejected.
  GSignal<double> get onBeforeStep => (_beforeStep ??= GSignal<double>());

  /// Emits after one fixed step has solved and contact callbacks have run.
  ///
  /// The emitted value is the exact simulation delta for that step.
  GSignal<double> get onAfterStep => (_afterStep ??= GSignal<double>());

  bool get isDisposed => _disposed;

  void _checkAlive() {
    if (_disposed) throw StateError('GArcadeWorld has been disposed.');
  }

  GBody _createBody(
    GNode? node, {
    required GBodyShape shape,
    GBodyType type = GBodyType.dynamic,
    double x = 0,
    double y = 0,
    double mass = 1,
    double bounce = 0,
    bool sensor = false,
    bool continuous = false,
    int layer = 1,
    int mask = 0xffffffff,
  }) {
    _checkAlive();
    if (!x.isFinite) throw ArgumentError.value(x, 'x');
    if (!y.isFinite) throw ArgumentError.value(y, 'y');
    if (!mass.isFinite || mass <= 0) throw ArgumentError.value(mass, 'mass');
    if (!bounce.isFinite || bounce < 0 || bounce > 1) {
      throw ArgumentError.value(bounce, 'bounce');
    }
    if (continuous && !shape.isCircle) {
      throw ArgumentError('Continuous collision currently requires a circle body.');
    }
    if (layer < 0 || layer > 0xffffffff) {
      throw ArgumentError.value(layer, 'layer');
    }
    if (mask < 0 || mask > 0xffffffff) {
      throw ArgumentError.value(mask, 'mask');
    }

    if (node != null) {
      if (node.isDisposed) throw ArgumentError('Cannot bind a disposed node.');
      final existing = _bodyByNode[node];
      if (existing != null && existing.isAlive && identical(existing.node, node)) {
        throw StateError('Node already has an Arcade body.');
      }
      final space = _space;
      if (space == null) {
        throw StateError('A headless Arcade world cannot bind GNode instances.');
      }
      if (identical(node, space)) {
        throw ArgumentError('Arcade space cannot be bound as one of its bodies.');
      }
      if (!_readNodePosition(node, _spacePointScratch)) {
        throw ArgumentError(
          'Bound node must share the Arcade world Stage and have a parent.',
        );
      }
      x = _spacePointScratch.x;
      y = _spacePointScratch.y;
    }

    final slot = _allocateSlot();
    _x[slot] = _previousX[slot] = _authoredX[slot] = x;
    _y[slot] = _previousY[slot] = _authoredY[slot] = y;
    _vx[slot] = 0;
    _vy[slot] = 0;
    _bounce[slot] = bounce;
    _invMass[slot] = 1 / mass;
    _type[slot] = type.index;
    _flags[slot] = _flagEnabled | (sensor ? _flagSensor : 0) | (continuous ? _flagContinuous : 0);
    _shapeKind[slot] = shape._kind.index;
    _shapeA[slot] = shape._a;
    _shapeB[slot] = shape._b;
    _layer[slot] = layer;
    _mask[slot] = mask;

    final result = GBody._(this, slot, shape, node);
    _bodies[slot] = result;
    _bodyCount++;
    _sweepMembershipDirty = true;

    if (node != null) {
      _bodyByNode[node] = result;
      result._nodeDisposeSubscription = node.signals.onDispose.add(
        result.destroy,
        key: result,
      );
    }

    _refreshWake();
    return result;
  }

  /// Binds one collision body to [node].
  GBody body(
    GNode node, {
    required GBodyShape shape,
    GBodyType type = GBodyType.dynamic,
    double mass = 1,
    double bounce = 0,
    bool sensor = false,
    bool continuous = false,
    int layer = 1,
    int mask = 0xffffffff,
  }) => _createBody(
    node,
    shape: shape,
    type: type,
    mass: mass,
    bounce: bounce,
    sensor: sensor,
    continuous: continuous,
    layer: layer,
    mask: mask,
  );

  /// Creates an unbound body for headless/server/tool simulation.
  GBody createBody({
    required GBodyShape shape,
    GBodyType type = GBodyType.dynamic,
    double x = 0,
    double y = 0,
    double mass = 1,
    double bounce = 0,
    bool sensor = false,
    bool continuous = false,
    int layer = 1,
    int mask = 0xffffffff,
  }) => _createBody(
    null,
    shape: shape,
    type: type,
    x: x,
    y: y,
    mass: mass,
    bounce: bounce,
    sensor: sensor,
    continuous: continuous,
    layer: layer,
    mask: mask,
  );

  /// Creates an unbound circle for headless/server/tool simulation.
  GBody createCircle({
    required double radius,
    GBodyType type = GBodyType.dynamic,
    double x = 0,
    double y = 0,
    double mass = 1,
    double bounce = 0,
    bool sensor = false,
    bool continuous = false,
    int layer = 1,
    int mask = 0xffffffff,
  }) => _createBody(
    null,
    shape: GBodyShape.circle(radius),
    type: type,
    x: x,
    y: y,
    mass: mass,
    bounce: bounce,
    sensor: sensor,
    continuous: continuous,
    layer: layer,
    mask: mask,
  );

  /// Creates an unbound box for headless/server/tool simulation.
  GBody createBox({
    required double width,
    required double height,
    GBodyType type = GBodyType.dynamic,
    double x = 0,
    double y = 0,
    double mass = 1,
    double bounce = 0,
    bool sensor = false,
    int layer = 1,
    int mask = 0xffffffff,
  }) => _createBody(
    null,
    shape: GBodyShape.box(width, height),
    type: type,
    x: x,
    y: y,
    mass: mass,
    bounce: bounce,
    sensor: sensor,
    layer: layer,
    mask: mask,
  );

  GBody circle(
    GNode node, {
    required double radius,
    GBodyType type = GBodyType.dynamic,
    double mass = 1,
    double bounce = 0,
    bool sensor = false,
    bool continuous = false,
    int layer = 1,
    int mask = 0xffffffff,
  }) => _createBody(
    node,
    shape: GBodyShape.circle(radius),
    type: type,
    mass: mass,
    bounce: bounce,
    sensor: sensor,
    continuous: continuous,
    layer: layer,
    mask: mask,
  );

  GBody box(
    GNode node, {
    required double width,
    required double height,
    GBodyType type = GBodyType.dynamic,
    double mass = 1,
    double bounce = 0,
    bool sensor = false,
    int layer = 1,
    int mask = 0xffffffff,
  }) => _createBody(
    node,
    shape: GBodyShape.box(width, height),
    type: type,
    mass: mass,
    bounce: bounce,
    sensor: sensor,
    layer: layer,
    mask: mask,
  );

  void destroyBody(GBody body) {
    if (!body._alive || !identical(body.world, this)) return;
    final slot = body._slot;
    _removeContactsFor(slot);
    body._control?._released = true;
    body._control?._body = null;
    body._control = null;
    body._nodeDisposeSubscription?.cancel();
    body._nodeDisposeSubscription = null;
    body._node = null;
    body._contactBegin?.dispose();
    body._contactEnd?.dispose();
    body._alive = false;
    _bodies[slot] = null;
    _flags[slot] = 0;
    _freeSlots.add(slot);
    _bodyCount--;
    _sweepMembershipDirty = true;
    _refreshWake();
    if (!_stepping && !_dispatchingContacts) {
      _dispatchContactEvents();
    }
  }

  void _unbind(GBody body) {
    final node = body._node;
    if (node == null) return;
    body._nodeDisposeSubscription?.cancel();
    body._nodeDisposeSubscription = null;
    body._node = null;
    final control = body._control;
    if (control != null && control.isActive) control.release();
  }

  bool _readNodePosition(GNode node, GPoint out) {
    final space = _space;
    final parent = node.parent;
    if (space == null || parent == null) return false;
    if (identical(parent, space)) {
      out.set(node.x, node.y);
      return true;
    }
    return parent.localToNodeInto(space, node.x, node.y, out);
  }

  bool _writeNodePosition(GNode node, double x, double y) {
    final space = _space;
    final parent = node.parent;
    if (space == null || parent == null) return false;
    if (identical(parent, space)) {
      node.setPosition(x, y);
      return true;
    }
    if (!space.localToNodeInto(parent, x, y, _spacePointScratch)) {
      return false;
    }
    node.setPosition(_spacePointScratch.x, _spacePointScratch.y);
    return true;
  }

  void _syncBodyFromNode(GBody body, {required bool resetVelocity}) {
    final node = body._node;
    if (node == null || !_readNodePosition(node, _spacePointScratch)) {
      return;
    }
    final slot = body._slot;
    final x = _spacePointScratch.x;
    final y = _spacePointScratch.y;
    _teleport(slot, x, y, syncNode: false);
    _authoredX[slot] = x;
    _authoredY[slot] = y;
    if (resetVelocity) {
      _vx[slot] = 0;
      _vy[slot] = 0;
    }
  }

  int _allocateSlot() {
    if (_freeSlots.isNotEmpty) return _freeSlots.removeLast();
    final slot = _slotCount++;
    if (slot >= _capacity) _grow(slot + 1);
    return slot;
  }

  void _grow(int minimum) {
    var next = _capacity == 0 ? 16 : _capacity;
    while (next < minimum) next <<= 1;

    Float64List growF64(Float64List old) {
      final value = Float64List(next);
      value.setAll(0, old);
      return value;
    }

    Uint8List growU8(Uint8List old) {
      final value = Uint8List(next);
      value.setAll(0, old);
      return value;
    }

    Uint32List growU32(Uint32List old) {
      final value = Uint32List(next);
      value.setAll(0, old);
      return value;
    }

    _x = growF64(_x);
    _y = growF64(_y);
    _previousX = growF64(_previousX);
    _previousY = growF64(_previousY);
    _authoredX = growF64(_authoredX);
    _authoredY = growF64(_authoredY);
    _vx = growF64(_vx);
    _vy = growF64(_vy);
    _bounce = growF64(_bounce);
    _invMass = growF64(_invMass);
    _shapeA = growF64(_shapeA);
    _shapeB = growF64(_shapeB);
    _type = growU8(_type);
    _flags = growU8(_flags);
    _shapeKind = growU8(_shapeKind);
    _layer = growU32(_layer);
    _mask = growU32(_mask);

    final bodies = List<GBody?>.filled(next, null);
    for (var i = 0; i < _bodies.length; i++) {
      bodies[i] = _bodies[i];
    }
    _bodies = bodies;
    _sweepOrder = Int32List(next);
    _capacity = next;
  }

  bool _enabledBody(int slot) => (_flags[slot] & _flagEnabled) != 0;
  bool _sensorBody(int slot) => (_flags[slot] & _flagSensor) != 0;
  bool _continuousBody(int slot) => (_flags[slot] & _flagContinuous) != 0;
  bool _controlledBody(int slot) => (_flags[slot] & _flagControlled) != 0;

  void _setFlag(int slot, int flag, bool value) {
    final old = _flags[slot];
    final next = value ? old | flag : old & ~flag;
    if (old == next) return;
    _flags[slot] = next;
    if (flag == _flagEnabled) {
      _sweepMembershipDirty = true;
      _refreshWake();
    }
  }

  void _setBodyEnabled(int slot, bool value) {
    _setFlag(slot, _flagEnabled, value);
  }

  void _setBodyShape(int slot, GBodyShape value) {
    _shapeKind[slot] = value._kind.index;
    _shapeA[slot] = value._a;
    _shapeB[slot] = value._b;
  }

  void _setBodyType(int slot, GBodyType value) {
    if (_type[slot] == value.index) return;
    _type[slot] = value.index;
    if (value != GBodyType.dynamic) {
      _flags[slot] &= ~_flagControlled;
      final body = _bodies[slot];
      final control = body?._control;
      if (control != null) {
        control._released = true;
        control._body = null;
        body!._control = null;
      }
    }
    _refreshWake();
  }

  void _refreshWake() {
    if (_disposed || !_enabled || _stage == null) {
      if (!_enabled || _disposed) _sleep();
      return;
    }
    var needs = false;
    for (var i = 0; i < _slotCount; i++) {
      if (_bodies[i] == null || !_enabledBody(i)) continue;
      if (_type[i] != GBodyType.static.index) {
        needs = true;
        break;
      }
    }
    if (needs) {
      final current = _updateSubscription;
      if (current == null || !current.isActive) {
        _updateSubscription = _stage.signals.onPostUpdate.add(
          _onStageUpdate,
          key: this,
        );
      }
    } else {
      _sleep();
    }
  }

  void _sleep() {
    final subscription = _updateSubscription;
    _updateSubscription = null;
    subscription?.cancel();
  }

  void _onStageUpdate(double delta) => advance(delta);

  /// Advances using the retained fixed-step accumulator.
  void advance(double delta) {
    _checkAlive();
    if (_stepping || _dispatchingContacts || _dispatchingStepHook) {
      throw StateError(
        'Arcade world cannot advance recursively from a step/contact callback.',
      );
    }
    if (!_enabled || !delta.isFinite || delta <= 0) return;

    final maximum = _fixedStep * _maxSubSteps;
    _accumulator += math.min(delta, maximum).toDouble();
    var steps = (_accumulator / _fixedStep).floor();
    if (steps > _maxSubSteps) steps = _maxSubSteps;

    _syncAuthoredBodies(steps * _fixedStep);
    for (var i = 0; i < steps; i++) {
      _step(_fixedStep);
      _accumulator -= _fixedStep;
    }
    if (steps == _maxSubSteps && _accumulator >= _fixedStep) {
      _accumulator = 0;
    }
    _syncDynamicNodes();
  }

  /// Runs one exact simulation step without using the accumulator.
  void step([double? delta]) {
    _checkAlive();
    if (_stepping || _dispatchingContacts) {
      throw StateError('Arcade world cannot step from a contact callback.');
    }
    if (!_enabled) return;
    final dt = delta ?? _fixedStep;
    if (!dt.isFinite || dt <= 0) throw ArgumentError.value(dt, 'delta');
    _syncAuthoredBodies(dt);
    _step(dt);
    _syncDynamicNodes(alphaOverride: 1);
  }

  void _syncAuthoredBodies(double simulationDelta) {
    for (var slot = 0; slot < _slotCount; slot++) {
      final body = _bodies[slot];
      if (body == null || !_enabledBody(slot)) continue;
      final node = body._node;
      if (node == null) continue;

      final type = _type[slot];
      if (type == GBodyType.dynamic.index && !_controlledBody(slot)) continue;
      if (!_readNodePosition(node, _spacePointScratch)) continue;

      final nextX = _spacePointScratch.x;
      final nextY = _spacePointScratch.y;

      if (type == GBodyType.static.index) {
        _previousX[slot] = _x[slot] = _authoredX[slot] = nextX;
        _previousY[slot] = _y[slot] = _authoredY[slot] = nextY;
        _vx[slot] = 0;
        _vy[slot] = 0;
      } else {
        _authoredX[slot] = nextX;
        _authoredY[slot] = nextY;
        if (simulationDelta > 0) {
          // Consume the complete authored displacement over the fixed steps
          // that will run this frame. If a render frame produces no physics
          // step, the target is retained and consumed by the next step instead
          // of losing a short pointer/Motion movement.
          _vx[slot] = (nextX - _x[slot]) / simulationDelta;
          _vy[slot] = (nextY - _y[slot]) / simulationDelta;
        } else {
          _vx[slot] = 0;
          _vy[slot] = 0;
        }
      }
    }
  }

  void _syncDynamicNodes({double? alphaOverride}) {
    final alpha =
        alphaOverride ??
        (interpolate && _fixedStep > 0
            ? (_accumulator / _fixedStep).clamp(0.0, 1.0).toDouble()
            : 1.0);
    for (var slot = 0; slot < _slotCount; slot++) {
      final body = _bodies[slot];
      if (body == null || !_enabledBody(slot)) continue;
      if (_type[slot] != GBodyType.dynamic.index || _controlledBody(slot)) {
        continue;
      }
      final node = body._node;
      if (node == null) continue;
      final px = _previousX[slot] + (_x[slot] - _previousX[slot]) * alpha;
      final py = _previousY[slot] + (_y[slot] - _previousY[slot]) * alpha;
      _writeNodePosition(node, px, py);
    }
  }

  void _teleport(int slot, double x, double y, {required bool syncNode}) {
    _x[slot] = _previousX[slot] = x;
    _y[slot] = _previousY[slot] = y;
    _authoredX[slot] = x;
    _authoredY[slot] = y;
    if (!syncNode) return;
    final node = _bodies[slot]?._node;
    if (node != null) _writeNodePosition(node, x, y);
  }

  void _step(double dt) {
    _stepping = true;
    try {
      _stepSerial++;
      _emitStepHook(_beforeStep, dt);

      for (var slot = 0; slot < _slotCount; slot++) {
        if (_bodies[slot] == null || !_enabledBody(slot)) continue;
        final type = _type[slot];
        if (type == GBodyType.dynamic.index && !_controlledBody(slot)) {
          _previousX[slot] = _x[slot];
          _previousY[slot] = _y[slot];
          _vx[slot] += gravityX * dt;
          _vy[slot] += gravityY * dt;
        } else if (type == GBodyType.kinematic.index || _controlledBody(slot)) {
          _previousX[slot] = _x[slot];
          _previousY[slot] = _y[slot];
          _x[slot] += _vx[slot] * dt;
          _y[slot] += _vy[slot] * dt;
        }
      }

      for (var slot = 0; slot < _slotCount; slot++) {
        if (_bodies[slot] == null || !_enabledBody(slot)) continue;
        if (_type[slot] != GBodyType.dynamic.index || _controlledBody(slot)) {
          continue;
        }
        if (_continuousBody(slot)) {
          _integrateContinuousCircle(slot, dt);
        } else {
          _x[slot] += _vx[slot] * dt;
          _y[slot] += _vy[slot] * dt;
        }
      }

      _solveOverlaps();
      _finishContacts();
    } finally {
      _stepping = false;
    }
    _dispatchContactEvents();
    _emitStepHook(_afterStep, dt);
  }

  void _emitStepHook(GSignal<double>? signal, double dt) {
    if (signal == null) return;
    _dispatchingStepHook = true;
    try {
      signal.emit(dt);
    } finally {
      _dispatchingStepHook = false;
    }
  }

  /// Returns one enabled body containing [x],[y], or null when none does.
  /// This is an O(n) convenience query; high-volume spatial querying should
  /// use a future retained query surface rather than relying on this helper.
  GBody? hitTest(double x, double y, {int mask = 0xffffffff}) {
    _checkAlive();
    if (!x.isFinite || !y.isFinite) return null;
    for (var slot = _slotCount - 1; slot >= 0; slot--) {
      final body = _bodies[slot];
      if (body == null || !_enabledBody(slot) || (_layer[slot] & mask) == 0) {
        continue;
      }
      if (_containsPoint(slot, x, y)) return body;
    }
    return null;
  }

  bool _containsPoint(int slot, double x, double y) {
    final dx = x - _x[slot];
    final dy = y - _y[slot];
    if (_shapeKind[slot] == _GShapeKind.circle.index) {
      final r = _shapeA[slot];
      return dx * dx + dy * dy <= r * r;
    }
    return dx.abs() <= _shapeA[slot] && dy.abs() <= _shapeB[slot];
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _sleep();
    _stageDisposeSubscription?.cancel();
    _stageDisposeSubscription = null;
    _spaceDisposeSubscription?.cancel();
    _spaceDisposeSubscription = null;

    for (var slot = 0; slot < _slotCount; slot++) {
      final body = _bodies[slot];
      if (body == null || !body._alive) continue;
      _removeContactsFor(slot);
      body._control?._released = true;
      body._control?._body = null;
      body._nodeDisposeSubscription?.cancel();
      body._nodeDisposeSubscription = null;
      body._node = null;
      body._contactBegin?.dispose();
      body._contactEnd?.dispose();
      body._alive = false;
      _bodies[slot] = null;
    }
    _contacts.clear();
    _contactBegins.clear();
    _contactEnds.clear();
    _beforeStep?.dispose();
    _beforeStep = null;
    _afterStep?.dispose();
    _afterStep = null;
    _bodyCount = 0;
  }
}
