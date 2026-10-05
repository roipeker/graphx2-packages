part of '../graphx_particles.dart';

/// One retained GraphX node that simulates and batches many packed particles.
///
/// Individual particles are not scene nodes or Dart objects. Active state lives
/// in fixed-capacity structure-of-arrays storage and is submitted through one
/// `Canvas.drawRawAtlas` call for the common same-image atlas case.
final class GParticleEmitter extends GNode {
  GParticleEmitter({
    required GTexture texture,
    required this.capacity,
    int seed = 0x51a7ec41,
  }) : _texture = texture,
       _frames = <GTexture>[texture],
       _seed = seed,
       _store = ParticleStore(capacity),
       _random = ParticleRandom(seed),
       stats = GParticleStats._(capacity),
       _transforms = Float32List(capacity * 4),
       _rects = Float32List(capacity * 4),
       _colors = Int32List(capacity),
       _particleColors = const <ui.Color>[ui.Color(0xffffffff)],
       _spawnColors = Uint32List.fromList(const <int>[0xffffffff]) {
    if (texture.isDisposed) {
      throw StateError('Cannot create a particle emitter with a disposed texture.');
    }
    _paint.filterQuality = ui.FilterQuality.low;
    _colors.fillRange(0, capacity, -1);
    _fillSourceRects(texture);
    _buildDrawSlices();
    setPaintSelf(true);
  }

  final int capacity;
  final ParticleStore _store;
  final ParticleRandom _random;
  final GParticleStats stats;

  GTexture _texture;
  List<GTexture> _frames;
  final Float32List _transforms;
  final Float32List _rects;
  final Int32List _colors;
  final List<_ParticleDrawSlice> _drawSlices = <_ParticleDrawSlice>[];
  final ui.Paint _paint = ui.Paint();
  final GMatrix2 _inverseWorld = GMatrix2();
  final GBounds _packedBounds = GBounds.empty();
  final GPoint _pathPoint = GPoint();
  final GPoint _pathTangent = GPoint();

  List<ui.Color> _particleColors;
  List<ui.Color>? _particleEndColors;
  List<GParticleConstraint> _constraints = const <GParticleConstraint>[];
  Uint32List _spawnColors;
  Uint32List? _spawnEndColors;
  int _seed;
  double _rate = 0.0;
  double _rateCarry = 0.0;
  double _distanceRate = 0.0;
  double _distanceCarry = 0.0;
  double _distanceSourceX = 0.0;
  double _distanceSourceY = 0.0;
  bool _distanceSourceValid = false;
  double _sourceVelocityFactor = 0.0;
  double _sourceVelocityX = 0.0;
  double _sourceVelocityY = 0.0;
  double _sourceVelocitySourceX = 0.0;
  double _sourceVelocitySourceY = 0.0;
  bool _sourceVelocitySourceValid = false;
  bool _running = false;
  GParticleRange _life = const GParticleRange(1.0);
  GParticleRange _particleScale = const GParticleRange(1.0);
  GParticleRange? _particleEndScale;
  GParticleRange _particleAlpha = const GParticleRange(1.0);
  GParticleRange? _particleEndAlpha;
  double _gravityX = 0.0;
  double _gravityY = 0.0;
  double _drag = 0.0;
  GParticleSpace _space = GParticleSpace.local;
  GParticleFrameMode _frameMode = GParticleFrameMode.first;
  GParticleCurve? _scaleOverLife;
  GParticleCurve? _alphaOverLife;
  GParticleColorCurve? _colorOverLife;
  bool _metricsEnabled = false;
  bool _renderDirty = true;
  int _lastPackedCount = 0;
  int _cachedPaintAlpha = -1;
  double _cachedRedMultiplier = double.nan;
  double _cachedGreenMultiplier = double.nan;
  double _cachedBlueMultiplier = double.nan;
  double _cachedAlphaMultiplier = double.nan;
  double _cachedRedOffset = double.nan;
  double _cachedGreenOffset = double.nan;
  double _cachedBlueOffset = double.nan;
  double _cachedAlphaOffset = double.nan;

  /// Future-birth velocity magnitude in logical units per second.
  GParticleRange speed = const GParticleRange(0.0);

  /// Absolute direction in [GParticleDirectionMode.angle], otherwise an offset
  /// around the sampled radial/tangent/normal direction.
  GParticleRange angle = const GParticleRange(0.0);

  /// Initial per-particle rotation in radians.
  /// `rotation` itself remains the normal GNode rotation.
  GParticleRange particleRotation = const GParticleRange(0.0);

  GParticleRange angularVelocity = const GParticleRange(0.0);
  GParticleShape shape = const GParticleShape.point();
  GParticleOverflow overflow = GParticleOverflow.drop;
  GParticleDirectionMode directionMode = GParticleDirectionMode.angle;

  int get activeCount => _store.count;
  bool get isRunning => _running;

  /// Compatibility shorthand for the first configured particle frame.
  ///
  /// Assigning [texture] collapses [frames] back to one frame.
  GTexture get texture => _texture;
  set texture(GTexture value) {
    if (_frames.length == 1 && identical(_texture, value)) return;
    _setFrames(<GTexture>[value]);
  }

  /// Same-image atlas frames available to particles.
  ///
  /// All textures must reference the same backing `ui.Image`, which keeps the
  /// emitter batchable in one `drawRawAtlas` call. The emitter never owns them.
  List<GTexture> get frames => _frames;
  set frames(List<GTexture> value) => _setFrames(value);

  GParticleFrameMode get frameMode => _frameMode;
  set frameMode(GParticleFrameMode value) {
    if (_frameMode == value) return;
    _frameMode = value;
    if (value == GParticleFrameMode.random && _frames.length > 1) {
      for (var i = 0; i < _store.count; ++i) {
        _store.frameIndex[i] = _random.nextInt(_frames.length);
      }
    }
    _markVisualChanged(bounds: true);
  }

  ui.FilterQuality get filterQuality => _paint.filterQuality;
  set filterQuality(ui.FilterQuality value) {
    if (_paint.filterQuality == value) return;
    _paint.filterQuality = value;
    invalidatePaint();
  }

  bool get metricsEnabled => _metricsEnabled;
  set metricsEnabled(bool value) {
    if (_metricsEnabled == value) return;
    _metricsEnabled = value;
    if (!value) {
      stats.simulationMicros = 0;
      stats.packingMicros = 0;
      stats.paintMicros = 0;
    }
  }

  /// Continuous time emission in particles per second.
  double get rate => _rate;
  set rate(double value) {
    _requireFiniteNonNegative(value, 'rate');
    if (_rate == value) return;
    _rate = value;
    _rateCarry = 0.0;
    _syncUpdates();
  }

  /// Continuous movement emission in particles per Stage logical unit traveled
  /// by this emitter's origin.
  ///
  /// Birth positions are interpolated along the source segment between updates.
  /// In world simulation they remain at those Stage positions. In local
  /// simulation they are converted back through the emitter's current transform
  /// and retain normal hierarchy ownership after birth.
  double get distanceRate => _distanceRate;
  set distanceRate(double value) {
    _requireFiniteNonNegative(value, 'distanceRate');
    if (_distanceRate == value) return;
    _distanceRate = value;
    _distanceCarry = 0.0;
    if (_running && value > 0.0) {
      _captureDistanceSource();
    } else {
      _distanceSourceValid = false;
    }
    _syncUpdates();
  }

  /// Fraction of the moving source's Stage-space translational velocity added
  /// to future world-space particle births.
  ///
  /// `0` disables tracking and keeps the original birth path. `1` inherits the
  /// full source velocity. Other finite values are allowed for exaggeration or
  /// reversal. Local-space particles do not receive an additive velocity because
  /// they continue inheriting the emitter hierarchy transform after birth.
  double get sourceVelocityFactor => _sourceVelocityFactor;
  set sourceVelocityFactor(double value) {
    _requireFinite(value, 'sourceVelocityFactor');
    if (_sourceVelocityFactor == value) return;
    _sourceVelocityFactor = value;
    _resetSourceVelocitySource();
    _syncUpdates();
  }

  GParticleRange get life => _life;
  set life(GParticleRange value) {
    if (value.min < 0.0) {
      throw ArgumentError.value(value, 'life', 'must be >= 0');
    }
    _life = value;
  }

  /// Initial per-particle scale. `scale` itself remains the normal GNode scale.
  GParticleRange get particleScale => _particleScale;
  set particleScale(GParticleRange value) {
    if (value.min < 0.0) {
      throw ArgumentError.value(value, 'particleScale', 'must be >= 0');
    }
    _particleScale = value;
  }

  /// Optional independently sampled scale target at natural lifetime end.
  ///
  /// `null` keeps the existing birth-scale behavior. Assigning a range affects
  /// future births only; particles that already own an endpoint retain it.
  GParticleRange? get particleEndScale => _particleEndScale;
  set particleEndScale(GParticleRange? value) {
    if (value != null && value.min < 0.0) {
      throw ArgumentError.value(value, 'particleEndScale', 'must be >= 0');
    }
    _particleEndScale = value;
    if (value != null) _store.enableEndScale();
  }

  GParticleRange get particleAlpha => _particleAlpha;
  set particleAlpha(GParticleRange value) {
    if (value.min < 0.0 || value.max > 1.0) {
      throw ArgumentError.value(value, 'particleAlpha', 'must be within 0..1');
    }
    _particleAlpha = value;
  }

  /// Optional independently sampled alpha target at natural lifetime end.
  ///
  /// When no end color palette is configured, the sampled birth RGB is retained
  /// and only alpha changes. Assigning `null` affects future births only.
  GParticleRange? get particleEndAlpha => _particleEndAlpha;
  set particleEndAlpha(GParticleRange? value) {
    if (value != null && (value.min < 0.0 || value.max > 1.0)) {
      throw ArgumentError.value(value, 'particleEndAlpha', 'must be within 0..1');
    }
    _particleEndAlpha = value;
    if (value != null) _store.enableEndColor();
  }

  double get gravityX => _gravityX;
  set gravityX(double value) {
    _requireFinite(value, 'gravityX');
    _gravityX = value;
  }

  double get gravityY => _gravityY;
  set gravityY(double value) {
    _requireFinite(value, 'gravityY');
    _gravityY = value;
  }

  /// Exponential velocity damping coefficient in inverse seconds.
  double get drag => _drag;
  set drag(double value) {
    _requireFiniteNonNegative(value, 'drag');
    _drag = value;
  }

  GParticleSpace get space => _space;
  set space(GParticleSpace value) {
    if (_space == value) return;
    _convertSpace(value);
    _resetSourceVelocitySource();
    _syncUpdates();
  }

  int get seed => _seed;
  set seed(int value) {
    _seed = value;
    _random.seed = value;
  }

  ui.Color get particleColor => _particleColors.first;
  set particleColor(ui.Color value) => particleColors = <ui.Color>[value];

  /// Palette sampled at emission time. Existing particles keep their color.
  List<ui.Color> get particleColors => _particleColors;
  set particleColors(List<ui.Color> value) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'particleColors', 'must not be empty');
    }
    final colors = List<ui.Color>.unmodifiable(value);
    final packed = Uint32List(colors.length);
    for (var i = 0; i < colors.length; ++i) {
      packed[i] = _packColor(colors[i]);
    }
    _particleColors = colors;
    _spawnColors = packed;
  }

  ui.Color? get particleEndColor => _particleEndColors?.first;
  set particleEndColor(ui.Color? value) =>
      particleEndColors = value == null ? null : <ui.Color>[value];

  /// Optional palette sampled independently for the natural lifetime endpoint.
  ///
  /// `null` disables end-color sampling for future births. Existing particles
  /// retain any packed endpoint already sampled at birth.
  List<ui.Color>? get particleEndColors => _particleEndColors;
  set particleEndColors(List<ui.Color>? value) {
    if (value == null) {
      _particleEndColors = null;
      _spawnEndColors = null;
      return;
    }
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'particleEndColors', 'must not be empty');
    }
    final colors = List<ui.Color>.unmodifiable(value);
    final packed = Uint32List(colors.length);
    for (var i = 0; i < colors.length; ++i) {
      packed[i] = _packColor(colors[i]);
    }
    _particleEndColors = colors;
    _spawnEndColors = packed;
    _store.enableEndColor();
  }

  GParticleCurve? get scaleOverLife => _scaleOverLife;
  set scaleOverLife(GParticleCurve? value) {
    if (identical(_scaleOverLife, value)) return;
    _scaleOverLife = value;
    _markVisualChanged(bounds: true);
  }

  GParticleCurve? get alphaOverLife => _alphaOverLife;
  set alphaOverLife(GParticleCurve? value) {
    if (identical(_alphaOverLife, value)) return;
    _alphaOverLife = value;
    _markVisualChanged();
  }

  GParticleColorCurve? get colorOverLife => _colorOverLife;
  set colorOverLife(GParticleColorCurve? value) {
    if (identical(_colorOverLife, value)) return;
    _colorOverLife = value;
    _markVisualChanged();
  }

  /// Starts continuous time and/or distance emission. Existing particles are
  /// unaffected. Source-velocity tracking is also activated for world-space
  /// emitters even when both continuous emission rates are zero.
  void start() {
    if (_running) return;
    _running = true;
    _rateCarry = 0.0;
    _distanceCarry = 0.0;
    if (_distanceRate > 0.0) {
      _captureDistanceSource();
    } else {
      _distanceSourceValid = false;
    }
    _resetSourceVelocitySource();
    _syncUpdates();
  }

  /// Stops continuous emission and source-velocity tracking. Existing particles
  /// continue simulating with the velocity they already own.
  void stop() {
    if (!_running) return;
    _running = false;
    _rateCarry = 0.0;
    _distanceCarry = 0.0;
    _distanceSourceValid = false;
    _sourceVelocityX = 0.0;
    _sourceVelocityY = 0.0;
    _sourceVelocitySourceValid = false;
    _syncUpdates();
  }

  @override
  void attached() {
    super.attached();
    if (_running && _distanceRate > 0.0) {
      _distanceCarry = 0.0;
      _captureDistanceSource();
    }
    _resetSourceVelocitySource();
  }

  /// Emits up to [count] particles at the emitter origin.
  int burst(int count) => _burst(count);

  /// Emits around an explicit origin without moving the retained emitter node.
  ///
  /// Coordinates use the current simulation space: emitter-local in local mode,
  /// Stage/root coordinates in world mode. Shape offsets and velocity still use
  /// the emitter's current linear transform in world mode.
  int burstAt(double x, double y, int count) {
    _requireFinite(x, 'x');
    _requireFinite(y, 'y');
    return _burst(count, originX: x, originY: y, hasOrigin: true);
  }

  int _burst(
    int count, {
    double originX = 0.0,
    double originY = 0.0,
    bool hasOrigin = false,
  }) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'must be >= 0');
    }
    stats._beginFrame();
    final startedAt = _metricsEnabled ? getTimerMicros() : 0;
    final before = _store.count;
    for (var i = 0; i < count; ++i) {
      if (overflow == GParticleOverflow.drop && _store.isFull) {
        stats.droppedLastFrame += count - i;
        break;
      }
      _spawnOne(
        0.0,
        originX: originX,
        originY: originY,
        hasOrigin: hasOrigin,
      );
    }
    stats.active = _store.count;
    if (_metricsEnabled) {
      stats.simulationMicros = getTimerMicros() - startedAt;
    }
    if (_store.count != before || stats.recycledLastFrame != 0) {
      _markVisualChanged(bounds: true);
    }
    _syncUpdates();
    return stats.spawnedLastFrame;
  }

  void clear() {
    if (_store.isEmpty) return;
    _store.clear();
    stats.active = 0;
    _markVisualChanged(bounds: true);
    _syncUpdates();
  }

  @override
  void update(double delta) {
    stats._beginFrame();
    final startedAt = _metricsEnabled ? getTimerMicros() : 0;
    final hadParticles = _store.count != 0;
    var expired = 0;

    if (_running && _space == GParticleSpace.world && _sourceVelocityFactor != 0.0) {
      _sampleSourceVelocity(delta);
    }

    if (delta > 0.0 && _store.count != 0) {
      expired = _store.step(
        delta,
        accelerationX: _gravityX,
        accelerationY: _gravityY,
        drag: _drag,
      );
    }

    if (delta > 0.0 && _running && _rate > 0.0) {
      final startCarry = _rateCarry;
      final total = startCarry + _rate * delta;
      final emissions = total.floor();
      _rateCarry = total - emissions;
      for (var i = 0; i < emissions; ++i) {
        if (overflow == GParticleOverflow.drop && _store.isFull) {
          stats.droppedLastFrame += emissions - i;
          break;
        }
        final emitAt = (1.0 - startCarry + i) / _rate;
        final remaining = (delta - emitAt).clamp(0.0, delta).toDouble();
        _spawnOne(remaining, sourceTimeOffset: remaining);
      }
    }

    if (_running && _distanceRate > 0.0) {
      _emitDistance(delta);
    }

    final constraintsChanged = _resolveParticleConstraints(this);
    stats.active = _store.count;
    if (_metricsEnabled) {
      stats.simulationMicros = getTimerMicros() - startedAt;
    }

    if (hadParticles || expired != 0 || constraintsChanged || stats.spawnedLastFrame != 0) {
      _markVisualChanged(bounds: true);
    }
    _syncUpdates();
  }

  void _captureDistanceSource() {
    final matrix = worldMatrix;
    _distanceSourceX = matrix.tx;
    _distanceSourceY = matrix.ty;
    _distanceSourceValid = true;
  }

  void _resetSourceVelocitySource() {
    _sourceVelocityX = 0.0;
    _sourceVelocityY = 0.0;
    if (_running && _space == GParticleSpace.world && _sourceVelocityFactor != 0.0 && isAttached) {
      _captureSourceVelocitySource();
    } else {
      _sourceVelocitySourceValid = false;
    }
  }

  void _captureSourceVelocitySource() {
    final matrix = worldMatrix;
    _sourceVelocitySourceX = matrix.tx;
    _sourceVelocitySourceY = matrix.ty;
    _sourceVelocityX = 0.0;
    _sourceVelocityY = 0.0;
    _sourceVelocitySourceValid = true;
  }

  void _sampleSourceVelocity(double delta) {
    final matrix = worldMatrix;
    final currentX = matrix.tx;
    final currentY = matrix.ty;
    if (!_sourceVelocitySourceValid) {
      _sourceVelocitySourceX = currentX;
      _sourceVelocitySourceY = currentY;
      _sourceVelocityX = 0.0;
      _sourceVelocityY = 0.0;
      _sourceVelocitySourceValid = true;
      return;
    }

    if (delta > 0.0) {
      _sourceVelocityX = (currentX - _sourceVelocitySourceX) / delta;
      _sourceVelocityY = (currentY - _sourceVelocitySourceY) / delta;
    } else {
      // A zero-delta frame establishes a new positional baseline without
      // inventing an infinite velocity from a teleport or editor scrub.
      _sourceVelocityX = 0.0;
      _sourceVelocityY = 0.0;
    }
    _sourceVelocitySourceX = currentX;
    _sourceVelocitySourceY = currentY;
  }

  void _emitDistance(double delta) {
    final matrix = worldMatrix;
    final currentX = matrix.tx;
    final currentY = matrix.ty;
    if (!_distanceSourceValid) {
      _distanceSourceX = currentX;
      _distanceSourceY = currentY;
      _distanceSourceValid = true;
      return;
    }

    final startX = _distanceSourceX;
    final startY = _distanceSourceY;
    _distanceSourceX = currentX;
    _distanceSourceY = currentY;

    final dx = currentX - startX;
    final dy = currentY - startY;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance <= 0.0) return;

    final startCarry = _distanceCarry;
    final total = startCarry + _distanceRate * distance;
    final emissions = total.floor();
    _distanceCarry = total - emissions;
    if (emissions == 0) return;

    final local = _space == GParticleSpace.local;
    if (local && !matrix.invertInto(_inverseWorld)) {
      // A singular current transform cannot represent Stage positions in the
      // emitter's local simulation space. Discard this segment and restart the
      // distance phase from the current source position.
      _distanceCarry = 0.0;
      return;
    }

    for (var i = 0; i < emissions; ++i) {
      if (overflow == GParticleOverflow.drop && _store.isFull) {
        stats.droppedLastFrame += emissions - i;
        break;
      }
      final distanceAt = (1.0 - startCarry + i) / _distanceRate;
      final t = (distanceAt / distance).clamp(0.0, 1.0).toDouble();
      var originX = startX + dx * t;
      var originY = startY + dy * t;
      if (local) {
        final worldX = originX;
        final worldY = originY;
        originX = _inverseWorld.a * worldX + _inverseWorld.c * worldY + _inverseWorld.tx;
        originY = _inverseWorld.b * worldX + _inverseWorld.d * worldY + _inverseWorld.ty;
      }
      final remaining = delta > 0.0 ? delta * (1.0 - t) : 0.0;
      _spawnOne(
        remaining,
        originX: originX,
        originY: originY,
        hasOrigin: true,
      );
    }
  }

  bool _spawnOne(
    double remainingFrameTime, {
    double originX = 0.0,
    double originY = 0.0,
    bool hasOrigin = false,
    double sourceTimeOffset = 0.0,
  }) {
    final sampledLife = _sample(_life);
    if (sampledLife <= 0.0) {
      stats.droppedLastFrame++;
      return false;
    }

    if (_store.isFull) {
      if (overflow == GParticleOverflow.drop) {
        stats.droppedLastFrame++;
        return false;
      }
      _store.removeOldest();
      stats.recycledLastFrame++;
    }

    var px = 0.0;
    var py = 0.0;
    var radialAngle = double.nan;
    var tangentAngle = double.nan;
    var normalAngle = double.nan;

    switch (shape.kind) {
      case GParticleShapeKind.point:
        break;
      case GParticleShapeKind.rectangle:
        px = (_random.nextDouble() - 0.5) * shape.width;
        py = (_random.nextDouble() - 0.5) * shape.height;
        if (px != 0.0 || py != 0.0) {
          radialAngle = math.atan2(py, px);
          normalAngle = radialAngle;
        }
        break;
      case GParticleShapeKind.circle:
        final theta = _random.nextDouble() * math.pi * 2.0;
        final radius = shape.edge ? shape.radius : math.sqrt(_random.nextDouble()) * shape.radius;
        px = math.cos(theta) * radius;
        py = math.sin(theta) * radius;
        radialAngle = theta;
        tangentAngle = theta + math.pi * 0.5;
        normalAngle = theta;
        break;
      case GParticleShapeKind.line:
        final t = _random.nextDouble();
        px = shape.x1 + (shape.x2 - shape.x1) * t;
        py = shape.y1 + (shape.y2 - shape.y1) * t;
        if (px != 0.0 || py != 0.0) radialAngle = math.atan2(py, px);
        final dx = shape.x2 - shape.x1;
        final dy = shape.y2 - shape.y1;
        if (dx != 0.0 || dy != 0.0) {
          tangentAngle = math.atan2(dy, dx);
          normalAngle = tangentAngle + math.pi * 0.5;
        }
        break;
      case GParticleShapeKind.path:
        final path = shape.path!;
        final progress = _random.nextDouble();
        path.sampleAt(progress, _pathPoint, _pathTangent);
        px = _pathPoint.x;
        py = _pathPoint.y;
        if (px != 0.0 || py != 0.0) radialAngle = math.atan2(py, px);
        if (_pathTangent.x != 0.0 || _pathTangent.y != 0.0) {
          tangentAngle = math.atan2(_pathTangent.y, _pathTangent.x);
          normalAngle = tangentAngle + math.pi * 0.5;
        }
        break;
    }

    final sampledAngle = _sample(angle);
    final direction = switch (directionMode) {
      GParticleDirectionMode.angle => sampledAngle,
      GParticleDirectionMode.radial => (radialAngle.isNaN ? 0.0 : radialAngle) + sampledAngle,
      GParticleDirectionMode.tangent => (tangentAngle.isNaN ? 0.0 : tangentAngle) + sampledAngle,
      GParticleDirectionMode.normal =>
        (normalAngle.isNaN ? (radialAngle.isNaN ? 0.0 : radialAngle) : normalAngle) + sampledAngle,
    };

    final sampledSpeed = _sample(speed);
    var velocityX = math.cos(direction) * sampledSpeed;
    var velocityY = math.sin(direction) * sampledSpeed;
    var sampledScale = _sample(_particleScale);
    final endScaleRange = _particleEndScale;
    double? sampledEndScale = endScaleRange == null ? null : _sample(endScaleRange);
    var sampledRotation = _sample(particleRotation);

    if (_space == GParticleSpace.world) {
      final matrix = worldMatrix;
      final nextX = matrix.a * px + matrix.c * py;
      final nextY = matrix.b * px + matrix.d * py;
      final nextVelocityX = matrix.a * velocityX + matrix.c * velocityY;
      final nextVelocityY = matrix.b * velocityX + matrix.d * velocityY;
      var sourceX = hasOrigin ? originX : matrix.tx;
      var sourceY = hasOrigin ? originY : matrix.ty;
      if (!hasOrigin && sourceTimeOffset > 0.0 && _sourceVelocityFactor != 0.0) {
        sourceX -= _sourceVelocityX * sourceTimeOffset;
        sourceY -= _sourceVelocityY * sourceTimeOffset;
      }
      px = nextX + sourceX;
      py = nextY + sourceY;
      velocityX = nextVelocityX;
      velocityY = nextVelocityY;
      if (_sourceVelocityFactor != 0.0) {
        velocityX += _sourceVelocityX * _sourceVelocityFactor;
        velocityY += _sourceVelocityY * _sourceVelocityFactor;
      }
      final basisScale = math.sqrt(matrix.a * matrix.a + matrix.b * matrix.b);
      sampledScale *= basisScale;
      if (sampledEndScale != null) sampledEndScale *= basisScale;
      sampledRotation += math.atan2(matrix.b, matrix.a);
    } else if (hasOrigin) {
      px += originX;
      py += originY;
    }

    final startBaseColor = _spawnColors.length == 1
        ? _spawnColors[0]
        : _spawnColors[_random.nextInt(_spawnColors.length)];
    final sampledStartAlpha = _sample(_particleAlpha);
    final color = _multiplyPackedAlpha(startBaseColor, sampledStartAlpha);

    int? sampledEndColor;
    final endColors = _spawnEndColors;
    final endAlphaRange = _particleEndAlpha;
    if (endColors != null || endAlphaRange != null) {
      final endBaseColor = endColors == null
          ? startBaseColor
          : endColors.length == 1
          ? endColors[0]
          : endColors[_random.nextInt(endColors.length)];
      final endAlpha = endAlphaRange == null ? sampledStartAlpha : _sample(endAlphaRange);
      sampledEndColor = _multiplyPackedAlpha(endBaseColor, endAlpha);
    }

    final frameIndex = _frameMode == GParticleFrameMode.random && _frames.length > 1
        ? _random.nextInt(_frames.length)
        : 0;
    final index = _store.add(
      x: px,
      y: py,
      vx: velocityX,
      vy: velocityY,
      life: sampledLife,
      rotation: sampledRotation,
      angularVelocity: _sample(angularVelocity),
      scale: sampledScale,
      baseColor: color,
      particleEndScale: sampledEndScale,
      particleEndColor: sampledEndColor,
      frameIndex: frameIndex,
    );
    stats.spawnedLastFrame++;
    stats.totalSpawned++;

    if (remainingFrameTime > 0.0) {
      _store.advanceAt(
        index,
        remainingFrameTime,
        accelerationX: _gravityX,
        accelerationY: _gravityY,
        drag: _drag,
      );
    }
    return true;
  }

  double _sample(GParticleRange range) {
    if (range.isConstant) return range.min;
    return range.min + (range.max - range.min) * _random.nextDouble();
  }

  void _convertSpace(GParticleSpace next) {
    if (_store.isEmpty) {
      _space = next;
      return;
    }

    final matrix = worldMatrix;
    final basisScale = math.sqrt(matrix.a * matrix.a + matrix.b * matrix.b);
    final basisAngle = math.atan2(matrix.b, matrix.a);
    final toWorld = next == GParticleSpace.world;
    if (!toWorld) {
      if (basisScale == 0.0 || !matrix.invertInto(_inverseWorld)) {
        throw StateError('Cannot convert world particles through a singular transform.');
      }
    }
    final transform = toWorld ? matrix : _inverseWorld;
    final endpointFlags = _store.endpointFlags;
    final endScale = _store.endScale;

    for (var i = 0; i < _store.count; ++i) {
      final x = _store.x[i];
      final y = _store.y[i];
      final vx = _store.vx[i];
      final vy = _store.vy[i];
      _store.x[i] = transform.a * x + transform.c * y + transform.tx;
      _store.y[i] = transform.b * x + transform.d * y + transform.ty;
      _store.vx[i] = transform.a * vx + transform.c * vy;
      _store.vy[i] = transform.b * vx + transform.d * vy;
      if (toWorld) {
        _store.scale[i] *= basisScale;
        if (endpointFlags != null &&
            endScale != null &&
            (endpointFlags[i] & ParticleStore.endpointScaleFlag) != 0) {
          endScale[i] *= basisScale;
        }
        _store.rotation[i] += basisAngle;
      } else {
        _store.scale[i] /= basisScale;
        if (endpointFlags != null &&
            endScale != null &&
            (endpointFlags[i] & ParticleStore.endpointScaleFlag) != 0) {
          endScale[i] /= basisScale;
        }
        _store.rotation[i] -= basisAngle;
      }
    }
    _transformTrailHistory(transform);
    _space = next;
    _markVisualChanged(bounds: true);
  }

  @override
  void computeSelfBounds(GBounds out) {
    if (_store.isEmpty) {
      out.setEmpty();
      return;
    }
    if (_renderDirty) _packRenderBuffers();

    if (_space == GParticleSpace.local) {
      out.copyFrom(_packedBounds);
      _includeTrailBounds(out);
      return;
    }
    if (worldMatrix.invertInto(_inverseWorld)) {
      _inverseWorld.transformBoundsInto(_packedBounds, out);
      _includeTrailBounds(out, transform: _inverseWorld);
    } else {
      out.setEmpty();
    }
  }

  @override
  void paintSelf(GRenderContext context) {
    stats.drawCalls = 0;
    stats.submittedParticles = 0;
    if (_store.isEmpty || context.alpha <= 0.0) return;

    final startedAt = _metricsEnabled ? getTimerMicros() : 0;
    stats.drawCalls = _paintTrail(context);

    if (!_framesAlive()) {
      if (_metricsEnabled) stats.paintMicros = getTimerMicros() - startedAt;
      return;
    }

    if (_renderDirty) _packRenderBuffers();
    final slice = _sliceFor(_store.count);
    if (slice == null) {
      if (_metricsEnabled) stats.paintMicros = getTimerMicros() - startedAt;
      return;
    }
    _configurePaint(context);
    final canvas = context.canvas;
    var cancelledWorldTransform = false;
    if (_space == GParticleSpace.world) {
      if (!worldMatrix.invertInto(_inverseWorld)) {
        if (_metricsEnabled) stats.paintMicros = getTimerMicros() - startedAt;
        return;
      }
      canvas.save();
      context.transform(_inverseWorld);
      cancelledWorldTransform = true;
    }

    try {
      canvas.drawRawAtlas(
        _texture.image,
        slice.transforms,
        slice.rects,
        slice.colors,
        ui.BlendMode.modulate,
        null,
        _paint,
      );
      stats.drawCalls++;
      stats.submittedParticles = slice.length;
    } finally {
      if (cancelledWorldTransform) canvas.restore();
    }

    if (_metricsEnabled) {
      stats.paintMicros = getTimerMicros() - startedAt;
    }
  }

  void _packRenderBuffers() {
    final startedAt = _metricsEnabled ? getTimerMicros() : 0;
    final count = _store.count;
    final multipleFrames = _frames.length > 1;
    final endpointFlags = _store.endpointFlags;
    final endScale = _store.endScale;
    final endColor = _store.endColor;
    _packedBounds.setEmpty();

    for (var i = 0; i < count; ++i) {
      final life = _store.life[i];
      final t = life <= 0.0 ? 1.0 : (_store.age[i] / life).clamp(0.0, 1.0).toDouble();
      final texture = _frameFor(i, t);
      final frame = texture.frame;
      final invTextureScale = 1.0 / texture.scale;
      final pivotX = texture.width * 0.5;
      final pivotY = texture.height * 0.5;
      final flags = endpointFlags == null ? 0 : endpointFlags[i];
      var scale = _store.scale[i];
      if ((flags & ParticleStore.endpointScaleFlag) != 0) {
        final target = endScale![i];
        scale += (target - scale) * t;
      }
      scale *= _scaleOverLife?._sample(t) ?? 1.0;
      final rotation = _store.rotation[i];
      final cosine = rotation == 0.0 ? 1.0 : math.cos(rotation);
      final sine = rotation == 0.0 ? 0.0 : math.sin(rotation);
      final drawScale = scale * invTextureScale;
      final scaledCosine = cosine * scale;
      final scaledSine = sine * scale;
      final sourceCosine = (frame.rotated ? sine : cosine) * drawScale;
      final sourceSine = (frame.rotated ? -cosine : sine) * drawScale;
      final offsetX = frame.offsetX * invTextureScale - pivotX;
      final offsetY =
          (frame.rotated ? frame.offsetY + frame.region.w : frame.offsetY) * invTextureScale -
          pivotY;
      final base = i * 4;
      _transforms[base] = sourceCosine;
      _transforms[base + 1] = sourceSine;
      _transforms[base + 2] = _store.x[i] + scaledCosine * offsetX - scaledSine * offsetY;
      _transforms[base + 3] = _store.y[i] + scaledSine * offsetX + scaledCosine * offsetY;

      if (multipleFrames) _writeSourceRect(base, texture);

      var color = _store.baseColor[i];
      if ((flags & ParticleStore.endpointColorFlag) != 0) {
        color = _lerpPackedColor(color, endColor![i], t);
      }
      final colorCurve = _colorOverLife;
      if (colorCurve != null) {
        color = _multiplyPackedColor(color, colorCurve._samplePacked(t));
      }
      final alphaCurve = _alphaOverLife;
      if (alphaCurve != null) {
        color = _multiplyPackedAlpha(color, alphaCurve._sample(t));
      }
      _colors[i] = color;

      final radius =
          math.sqrt(texture.width * texture.width + texture.height * texture.height) *
          0.5 *
          scale.abs();
      final x = _store.x[i];
      final y = _store.y[i];
      _packedBounds.includePoint(x - radius, y - radius);
      _packedBounds.includePoint(x + radius, y + radius);
    }

    for (var i = count; i < _lastPackedCount; ++i) {
      final base = i * 4;
      _transforms[base] = 0.0;
      _transforms[base + 1] = 0.0;
      _transforms[base + 2] = 0.0;
      _transforms[base + 3] = 0.0;
      _colors[i] = 0;
    }
    _lastPackedCount = count;
    _renderDirty = false;
    if (_metricsEnabled) {
      stats.packingMicros = getTimerMicros() - startedAt;
    }
  }

  GTexture _frameFor(int index, double normalizedAge) {
    final frames = _frames;
    if (frames.length == 1 || _frameMode == GParticleFrameMode.first) {
      return frames.first;
    }
    final frameIndex = switch (_frameMode) {
      GParticleFrameMode.first => 0,
      GParticleFrameMode.random => _store.frameIndex[index] % frames.length,
      GParticleFrameMode.overLife => math.min(
        (normalizedAge * frames.length).floor(),
        frames.length - 1,
      ),
    };
    return frames[frameIndex];
  }

  void _setFrames(List<GTexture> value) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'frames', 'must not be empty');
    }
    if (value.length > 0xffff) {
      throw ArgumentError.value(value.length, 'frames.length', 'must be <= 65535');
    }
    final image = value.first.image;
    for (var i = 0; i < value.length; ++i) {
      final frame = value[i];
      if (frame.isDisposed) {
        throw StateError('Cannot assign a disposed particle frame at index $i.');
      }
      if (!identical(frame.image, image)) {
        throw ArgumentError.value(
          value,
          'frames',
          'all particle frames must share one backing image',
        );
      }
    }
    _frames = List<GTexture>.unmodifiable(value);
    _texture = _frames.first;
    if (_frames.length == 1) {
      _fillSourceRects(_texture);
    } else if (_frameMode == GParticleFrameMode.random) {
      for (var i = 0; i < _store.count; ++i) {
        _store.frameIndex[i] = _random.nextInt(_frames.length);
      }
    }
    _markVisualChanged(bounds: true);
  }

  bool _framesAlive() {
    for (var i = 0; i < _frames.length; ++i) {
      if (_frames[i].isDisposed) return false;
    }
    return true;
  }

  void _fillSourceRects(GTexture texture) {
    final region = texture.frame.region;
    for (var i = 0; i < capacity; ++i) {
      _writeSourceRect(i * 4, texture, region: region);
    }
  }

  void _writeSourceRect(int base, GTexture texture, {GRect? region}) {
    final source = region ?? texture.frame.region;
    _rects[base] = source.x;
    _rects[base + 1] = source.y;
    _rects[base + 2] = source.x + source.w;
    _rects[base + 3] = source.y + source.h;
  }

  void _buildDrawSlices() {
    if (capacity == 0) return;
    var length = 1;
    while (true) {
      final sliceLength = math.min(length, capacity);
      _drawSlices.add(
        _ParticleDrawSlice(
          sliceLength,
          Float32List.sublistView(_transforms, 0, sliceLength * 4),
          Float32List.sublistView(_rects, 0, sliceLength * 4),
          Int32List.sublistView(_colors, 0, sliceLength),
        ),
      );
      if (sliceLength == capacity) break;
      length *= 2;
      if (length > capacity) length = capacity;
    }
  }

  _ParticleDrawSlice? _sliceFor(int count) {
    if (count <= 0) return null;
    for (var i = 0; i < _drawSlices.length; ++i) {
      final slice = _drawSlices[i];
      if (slice.length >= count) return slice;
    }
    return _drawSlices.last;
  }

  void _configurePaint(GRenderContext context) {
    if (!context.hasColorTransform) {
      if (_paint.colorFilter != null) {
        _paint.colorFilter = null;
        _cachedPaintAlpha = -1;
      }
      final alphaByte = (context.alpha * 255.0).round().clamp(0, 255).toInt();
      if (_cachedPaintAlpha != alphaByte) {
        _cachedPaintAlpha = alphaByte;
        _paint.color = ui.Color.fromARGB(alphaByte, 255, 255, 255);
      }
      _cachedRedMultiplier = double.nan;
      return;
    }

    final color = context.colorTransform;
    final alphaByte = (context.alpha * 255.0).round().clamp(0, 255).toInt();
    final unchanged =
        _cachedRedMultiplier == color.redMultiplier &&
        _cachedGreenMultiplier == color.greenMultiplier &&
        _cachedBlueMultiplier == color.blueMultiplier &&
        _cachedAlphaMultiplier == color.alphaMultiplier &&
        _cachedRedOffset == color.redOffset &&
        _cachedGreenOffset == color.greenOffset &&
        _cachedBlueOffset == color.blueOffset &&
        _cachedAlphaOffset == color.alphaOffset &&
        _cachedPaintAlpha == alphaByte;
    if (unchanged) return;

    _cachedRedMultiplier = color.redMultiplier;
    _cachedGreenMultiplier = color.greenMultiplier;
    _cachedBlueMultiplier = color.blueMultiplier;
    _cachedAlphaMultiplier = color.alphaMultiplier;
    _cachedRedOffset = color.redOffset;
    _cachedGreenOffset = color.greenOffset;
    _cachedBlueOffset = color.blueOffset;
    _cachedAlphaOffset = color.alphaOffset;
    _cachedPaintAlpha = alphaByte;
    _paint.color = const ui.Color(0xffffffff);
    _paint.colorFilter = ui.ColorFilter.matrix(<double>[
      color.redMultiplier,
      0,
      0,
      0,
      color.redOffset,
      0,
      color.greenMultiplier,
      0,
      0,
      color.greenOffset,
      0,
      0,
      color.blueMultiplier,
      0,
      0,
      color.blueOffset,
      0,
      0,
      0,
      color.alphaMultiplier * context.alpha,
      color.alphaOffset * context.alpha,
    ]);
  }

  void _markVisualChanged({bool bounds = false}) {
    _renderDirty = true;
    if (bounds) invalidateBounds();
    invalidatePaint();
  }

  void _worldTransformChanged() {
    if (_space == GParticleSpace.world && _store.count != 0) invalidateBounds();
  }

  @override
  set x(double value) {
    final changed = x != value;
    super.x = value;
    if (changed) _worldTransformChanged();
  }

  @override
  set y(double value) {
    final changed = y != value;
    super.y = value;
    if (changed) _worldTransformChanged();
  }

  @override
  void setPosition(double x, double y) {
    final changed = this.x != x || this.y != y;
    super.setPosition(x, y);
    if (changed) _worldTransformChanged();
  }

  @override
  set pivotX(double value) {
    final changed = pivotX != value;
    super.pivotX = value;
    if (changed) _worldTransformChanged();
  }

  @override
  set pivotY(double value) {
    final changed = pivotY != value;
    super.pivotY = value;
    if (changed) _worldTransformChanged();
  }

  @override
  void setPivot(double x, double y, {bool preserve = false}) {
    final changed = pivotX != x || pivotY != y;
    super.setPivot(x, y, preserve: preserve);
    if (changed) _worldTransformChanged();
  }

  @override
  set scaleX(double value) {
    final changed = scaleX != value;
    super.scaleX = value;
    if (changed) _worldTransformChanged();
  }

  @override
  set scaleY(double value) {
    final changed = scaleY != value;
    super.scaleY = value;
    if (changed) _worldTransformChanged();
  }

  @override
  void setScale(double x, [double? y]) {
    final sy = y ?? x;
    final changed = scaleX != x || scaleY != sy;
    super.setScale(x, y);
    if (changed) _worldTransformChanged();
  }

  @override
  set rotation(double value) {
    final changed = rotation != value;
    super.rotation = value;
    if (changed) _worldTransformChanged();
  }

  @override
  set skewX(double value) {
    final changed = skewX != value;
    super.skewX = value;
    if (changed) _worldTransformChanged();
  }

  @override
  set skewY(double value) {
    final changed = skewY != value;
    super.skewY = value;
    if (changed) _worldTransformChanged();
  }

  @override
  void setSkew(double x, double y) {
    final changed = skewX != x || skewY != y;
    super.setSkew(x, y);
    if (changed) _worldTransformChanged();
  }

  @override
  void setLocalMatrixValues(
    double a,
    double b,
    double c,
    double d,
    double tx,
    double ty,
  ) {
    super.setLocalMatrixValues(a, b, c, d, tx, ty);
    _worldTransformChanged();
  }

  void _syncUpdates() {
    updatesEnabled =
        (_running &&
            (_rate > 0.0 ||
                _distanceRate > 0.0 ||
                (_space == GParticleSpace.world && _sourceVelocityFactor != 0.0))) ||
        _store.count != 0;
  }

  @override
  void dispose() {
    if (isDisposed) return;
    updatesEnabled = false;
    _distanceSourceValid = false;
    _sourceVelocitySourceValid = false;
    _sourceVelocityX = 0.0;
    _sourceVelocityY = 0.0;
    _store.clear();
    _drawSlices.clear();
    super.dispose();
  }

  static void _requireFinite(double value, String name) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, name, 'must be finite');
    }
  }

  static void _requireFiniteNonNegative(double value, String name) {
    if (!value.isFinite || value < 0.0) {
      throw ArgumentError.value(value, name, 'must be finite and >= 0');
    }
  }
}

final class _ParticleDrawSlice {
  const _ParticleDrawSlice(
    this.length,
    this.transforms,
    this.rects,
    this.colors,
  );

  final int length;
  final Float32List transforms;
  final Float32List rects;
  final Int32List colors;
}
