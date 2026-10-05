part of 'package:graphx_arcade/graphx_arcade.dart';

/// How a body participates in simulation.
enum GBodyType {
  /// Fully simulated. Velocity, gravity and collisions own its position.
  dynamic,

  /// Authored externally. A bound node drives position and Arcade derives
  /// velocity for collision response.
  kinematic,

  /// Immovable collision geometry. A bound node may still reposition it
  /// between simulation steps.
  static,
}

enum _GShapeKind { circle, box }

/// Small immutable collision-shape description.
final class GBodyShape {
  GBodyShape._(this._kind, this._a, this._b);

  factory GBodyShape.circle(double radius) {
    if (!radius.isFinite || radius <= 0) {
      throw ArgumentError.value(radius, 'radius');
    }
    return GBodyShape._(_GShapeKind.circle, radius, 0);
  }

  factory GBodyShape.box(double width, double height) {
    if (!width.isFinite || width <= 0) {
      throw ArgumentError.value(width, 'width');
    }
    if (!height.isFinite || height <= 0) {
      throw ArgumentError.value(height, 'height');
    }
    return GBodyShape._(_GShapeKind.box, width * .5, height * .5);
  }

  final _GShapeKind _kind;
  final double _a;
  final double _b;

  bool get isCircle => _kind == _GShapeKind.circle;
  bool get isBox => _kind == _GShapeKind.box;
  double get radius => isCircle ? _a : 0;
  double get width => isBox ? _a * 2 : 0;
  double get height => isBox ? _b * 2 : 0;
}

/// Body-relative contact view. One instance is retained for the lifetime of
/// the contact pair and reused for begin/end dispatch.
final class GBodyContact {
  GBodyContact._(this.body, this.other);

  final GBody body;
  final GBody other;

  double pointX = 0;
  double pointY = 0;
  double normalX = 0;
  double normalY = 0;

  bool get isSensor => body.sensor || other.sensor;
}

/// Mutable velocity facade backed directly by a body's packed world storage.
/// It is allocated lazily per body.
final class GBodyVelocity {
  GBodyVelocity._(this._body);

  final GBody _body;

  double get x => _body.velocityX;
  set x(double value) => _body.velocityX = value;

  double get y => _body.velocityY;
  set y(double value) => _body.velocityY = value;

  void set(double x, double y) => _body.setVelocity(x, y);

  void setZero() => set(0, 0);
}

/// Explicit temporary node authority over a dynamic body.
final class GBodyControl {
  GBodyControl._(this._body);

  GBody? _body;
  bool _released = false;

  bool get isActive => !_released && (_body?.isAlive ?? false);

  void moveTo(double x, double y) {
    final body = _body;
    if (!isActive || body == null) {
      throw StateError('Body control is no longer active.');
    }
    final node = body.node;
    if (node == null) {
      throw StateError('Controlled body is no longer bound to a node.');
    }
    if (!body.world._writeNodePosition(node, x, y)) {
      throw StateError('Controlled node cannot resolve into Arcade space.');
    }
  }

  void release({double? velocityX, double? velocityY}) {
    if (_released) return;
    _released = true;
    final body = _body;
    _body = null;
    if (body == null || !body.isAlive) return;
    body._releaseControl(this, velocityX: velocityX, velocityY: velocityY);
  }

  bool get isDisposed => _released;

  void dispose() => release();
}

/// Stable public handle into one packed body slot.
final class GBody {
  GBody._(this.world, this._slot, this._shape, this._node);

  final GArcadeWorld world;
  final int _slot;
  GBodyShape _shape;

  GBodyShape get shape => _shape;
  set shape(GBodyShape value) {
    _checkAlive();
    if (continuous && !value.isCircle) {
      throw StateError(
        'Disable continuous collision before assigning a non-circle shape.',
      );
    }
    _shape = value;
    world._setBodyShape(_slot, value);
  }

  GNode? _node;
  GSignalSubscription? _nodeDisposeSubscription;
  GBodyVelocity? _velocity;
  GSignal<GBodyContact>? _contactBegin;
  GSignal<GBodyContact>? _contactEnd;
  GBodyControl? _control;
  bool _alive = true;

  Object? userData;

  bool get isAlive => _alive;
  GNode? get node => _node;

  void _checkAlive() {
    if (!_alive) throw StateError('GBody has been destroyed.');
  }

  GBodyType get type {
    _checkAlive();
    return GBodyType.values[world._type[_slot]];
  }

  set type(GBodyType value) {
    _checkAlive();
    world._setBodyType(_slot, value);
  }

  bool get enabled {
    _checkAlive();
    return world._enabledBody(_slot);
  }

  set enabled(bool value) {
    _checkAlive();
    world._setBodyEnabled(_slot, value);
  }

  bool get sensor {
    _checkAlive();
    return world._sensorBody(_slot);
  }

  set sensor(bool value) {
    _checkAlive();
    world._setFlag(_slot, _flagSensor, value);
  }

  bool get continuous {
    _checkAlive();
    return world._continuousBody(_slot);
  }

  set continuous(bool value) {
    _checkAlive();
    if (value && !shape.isCircle) {
      throw StateError('Continuous collision currently requires a circle body.');
    }
    world._setFlag(_slot, _flagContinuous, value);
  }

  int get layer {
    _checkAlive();
    return world._layer[_slot];
  }

  set layer(int value) {
    _checkAlive();
    if (value < 0 || value > 0xffffffff) {
      throw ArgumentError.value(value, 'layer');
    }
    world._layer[_slot] = value;
  }

  int get mask {
    _checkAlive();
    return world._mask[_slot];
  }

  set mask(int value) {
    _checkAlive();
    if (value < 0 || value > 0xffffffff) {
      throw ArgumentError.value(value, 'mask');
    }
    world._mask[_slot] = value;
  }

  double get bounce {
    _checkAlive();
    return world._bounce[_slot];
  }

  set bounce(double value) {
    _checkAlive();
    if (!value.isFinite || value < 0 || value > 1) {
      throw ArgumentError.value(value, 'bounce');
    }
    world._bounce[_slot] = value;
  }

  double get mass {
    _checkAlive();
    final inv = world._invMass[_slot];
    return inv == 0 ? double.infinity : 1 / inv;
  }

  set mass(double value) {
    _checkAlive();
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(value, 'mass');
    }
    world._invMass[_slot] = 1 / value;
  }

  double get x {
    _checkAlive();
    return world._x[_slot];
  }

  set x(double value) => teleport(value, y);

  double get y {
    _checkAlive();
    return world._y[_slot];
  }

  set y(double value) => teleport(x, value);

  double get velocityX {
    _checkAlive();
    return world._vx[_slot];
  }

  set velocityX(double value) {
    _checkAlive();
    if (!value.isFinite) throw ArgumentError.value(value, 'velocityX');
    world._vx[_slot] = value;
  }

  double get velocityY {
    _checkAlive();
    return world._vy[_slot];
  }

  set velocityY(double value) {
    _checkAlive();
    if (!value.isFinite) throw ArgumentError.value(value, 'velocityY');
    world._vy[_slot] = value;
  }

  GBodyVelocity get velocity => _velocity ??= GBodyVelocity._(this);

  void setVelocity(double x, double y) {
    _checkAlive();
    if (!x.isFinite) throw ArgumentError.value(x, 'x');
    if (!y.isFinite) throw ArgumentError.value(y, 'y');
    world._vx[_slot] = x;
    world._vy[_slot] = y;
  }

  GSignal<GBodyContact> get onContactBegin => (_contactBegin ??= GSignal<GBodyContact>());

  GSignal<GBodyContact> get onContactEnd => (_contactEnd ??= GSignal<GBodyContact>());

  void teleport(double x, double y) {
    _checkAlive();
    if (!x.isFinite) throw ArgumentError.value(x, 'x');
    if (!y.isFinite) throw ArgumentError.value(y, 'y');
    world._teleport(_slot, x, y, syncNode: true);
  }

  void teleportFromNode() {
    _checkAlive();
    final node = _node;
    if (node == null) {
      throw StateError('Body is not bound to a node.');
    }
    if (!world._readNodePosition(node, world._spacePointScratch)) {
      throw StateError('Bound node cannot resolve into Arcade space.');
    }
    world._teleport(
      _slot,
      world._spacePointScratch.x,
      world._spacePointScratch.y,
      syncNode: false,
    );
  }

  GBodyControl takeControl() {
    _checkAlive();
    if (type != GBodyType.dynamic) {
      throw StateError('Only dynamic bodies can take temporary node control.');
    }
    if (_node == null) {
      throw StateError('Body must be bound to a node before taking control.');
    }
    final active = _control;
    if (active != null && active.isActive) return active;
    world._setFlag(_slot, _flagControlled, true);
    final control = GBodyControl._(this);
    _control = control;
    return control;
  }

  void _releaseControl(
    GBodyControl control, {
    required double? velocityX,
    required double? velocityY,
  }) {
    if (!identical(_control, control)) return;
    world._syncBodyFromNode(this, resetVelocity: false);
    _control = null;
    world._setFlag(_slot, _flagControlled, false);
    if (velocityX != null) this.velocityX = velocityX;
    if (velocityY != null) this.velocityY = velocityY;
  }

  void unbind() {
    _checkAlive();
    world._unbind(this);
  }

  void destroy() => world.destroyBody(this);

  bool get isDisposed => !_alive;

  void dispose() => destroy();
}

const int _flagEnabled = 1 << 0;
const int _flagSensor = 1 << 1;
const int _flagContinuous = 1 << 2;
const int _flagControlled = 1 << 3;
