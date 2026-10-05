part of '../graphx_particles.dart';

/// Fixed-duration trail rendering for one packed particle emitter.
///
/// The default constructor is the cheapest line renderer. [GParticleTrail.ribbon]
/// opts into packed tapered triangle geometry while reusing the exact same
/// fixed-time history. Neither mode creates one trail/path/object per particle.
final class GParticleTrail {
  GParticleTrail({
    this.samples = 6,
    this.duration = .18,
    this.width = 2.0,
    this.color = const ui.Color(0xffffffff),
    this.alpha,
    this.blendMode = ui.BlendMode.srcOver,
  }) : tailWidth = width,
       tailColor = color,
       texture = null,
       textureRepeatLength = null,
       _ribbon = false {
    _validateBase();
  }

  /// Richer packed trail geometry with linear head-to-tail taper and color.
  ///
  /// Ribbons use one `Vertices.raw` triangle submission per emitter paint.
  /// Numeric history, positions, colors and optional texture coordinates are
  /// retained; only the small native Vertices submission object crosses the
  /// Canvas boundary per paint.
  GParticleTrail.ribbon({
    this.samples = 10,
    this.duration = .28,
    this.width = 8.0,
    this.tailWidth = 0.0,
    this.color = const ui.Color(0xffffffff),
    ui.Color? tailColor,
    this.alpha,
    this.blendMode = ui.BlendMode.srcOver,
    this.texture,
    this.textureRepeatLength,
  }) : tailColor = tailColor ?? color,
       _ribbon = true {
    _validateBase();
    if (!tailWidth.isFinite || tailWidth < 0.0) {
      throw ArgumentError.value(
        tailWidth,
        'tailWidth',
        'must be finite and >= 0',
      );
    }
    final ribbonTexture = texture;
    if (ribbonTexture?.isDisposed ?? false) {
      throw StateError('Cannot use a disposed GTexture on a particle ribbon.');
    }
    final repeatLength = textureRepeatLength;
    if (repeatLength != null) {
      if (ribbonTexture == null) {
        throw ArgumentError.value(
          repeatLength,
          'textureRepeatLength',
          'requires texture',
        );
      }
      if (!repeatLength.isFinite || repeatLength <= 0.0) {
        throw ArgumentError.value(
          repeatLength,
          'textureRepeatLength',
          'must be finite and > 0',
        );
      }
      if (!_supportsRibbonTextureRepeat(ribbonTexture)) {
        throw ArgumentError.value(
          ribbonTexture,
          'texture',
          'repeating ribbons require a full, non-rotated image texture',
        );
      }
    }
  }

  final int samples;
  final double duration;

  /// Head width in logical units.
  final double width;

  /// Tail width for ribbon mode. Line mode keeps this equal to [width].
  final double tailWidth;

  /// Head/base trail color.
  final ui.Color color;

  /// Tail color for ribbon mode. Line mode keeps this equal to [color].
  final ui.Color tailColor;

  /// Optional head-to-tail opacity curve, where 0 is the live head and 1 is
  /// the oldest retained sample.
  ///
  /// Line trails quantize this into at most four retained paint bands. Ribbon
  /// trails evaluate the retained LUT while packing per-vertex colors and still
  /// submit one triangle draw.
  final GParticleCurve? alpha;

  /// Destination blend used by this trail primitive.
  ///
  /// This is independent from [GParticleEmitter.particleBlendMode], which only
  /// controls sprite fragments, and from inherited `GNode.blendMode`, which
  /// controls subtree compositing.
  final ui.BlendMode blendMode;

  /// Optional texture multiplied by the packed ribbon vertex colors.
  ///
  /// The emitter never owns or disposes this texture. With no
  /// [textureRepeatLength], the texture stretches once over the current visible
  /// trail length. Atlas sub-regions and rotated frames are supported in stretch
  /// mode.
  final GTexture? texture;

  /// Optional logical distance covered by one horizontal texture repeat.
  ///
  /// Repeating uses the backing image's horizontal tile mode and therefore
  /// requires [texture] to cover the complete, non-rotated backing image. This
  /// avoids sampling neighboring atlas frames. `null` stretches once head→tail.
  final double? textureRepeatLength;

  final bool _ribbon;

  /// Whether this configuration uses tapered packed ribbon geometry.
  bool get isRibbon => _ribbon;

  /// Whether this ribbon carries retained UVs and an image shader.
  bool get isTexturedRibbon => _ribbon && texture != null;

  void _validateBase() {
    if (samples < 2 || samples > 16) {
      throw ArgumentError.value(samples, 'samples', 'must be within 2..16');
    }
    if (!duration.isFinite || duration <= 0.0) {
      throw ArgumentError.value(duration, 'duration', 'must be finite and > 0');
    }
    if (!width.isFinite || width <= 0.0) {
      throw ArgumentError.value(width, 'width', 'must be finite and > 0');
    }
  }
}

bool _supportsRibbonTextureRepeat(GTexture texture) {
  final frame = texture.frame;
  final region = frame.region;
  return !frame.rotated &&
      region.x == 0.0 &&
      region.y == 0.0 &&
      region.w == texture.image.width.toDouble() &&
      region.h == texture.image.height.toDouble();
}

double _particleTrailLifetimeAlpha(GParticleEmitter emitter, int particle) {
  final store = emitter._store;
  final life = store.life[particle];
  final t = life <= 0.0 ? 1.0 : (store.age[particle] / life).clamp(0.0, 1.0).toDouble();
  var color = store.baseColor[particle];
  final endpointFlags = store.endpointFlags;
  if (endpointFlags != null && (endpointFlags[particle] & ParticleStore.endpointColorFlag) != 0) {
    color = _lerpPackedColor(color, store.endColor![particle], t);
  }
  final colorCurve = emitter._colorOverLife;
  if (colorCurve != null) {
    color = _multiplyPackedColor(color, colorCurve._samplePacked(t));
  }
  final alphaCurve = emitter._alphaOverLife;
  if (alphaCurve != null) {
    color = _multiplyPackedAlpha(color, alphaCurve._sample(t));
  }
  return ((color >>> 24) & 0xff) / 255.0;
}

/// Optional trail configuration for [GParticleEmitter].
extension GParticleEmitterTrails on GParticleEmitter {
  GParticleTrail? get trail => _store.trailConfig as GParticleTrail?;

  set trail(GParticleTrail? value) {
    if (identical(trail, value)) return;
    final oldRenderer = _store.trailRenderer as _ParticleTrailPainter?;
    oldRenderer?.dispose();
    _store.trailConfig = value;

    if (value == null) {
      _store.trail = null;
      _store.trailRenderer = null;
      _markVisualChanged(bounds: true);
      return;
    }

    final history = ParticleTrailStore(
      capacity,
      value.samples,
      value.duration,
    );
    for (var i = 0; i < _store.count; ++i) {
      history.add(i, _store.x[i], _store.y[i]);
    }
    _store.trail = history;
    _store.trailRenderer = value._ribbon
        ? _ParticleRibbonTrailRenderer(capacity, value)
        : _ParticleLineTrailRenderer(capacity, value);
    _markVisualChanged(bounds: true);
  }

  int _paintTrail(GRenderContext context) {
    final history = _store.trail;
    final renderer = _store.trailRenderer as _ParticleTrailPainter?;
    if (history == null || renderer == null || _store.count == 0) return 0;
    return renderer.paint(this, history, _store.count, context);
  }

  void _includeTrailBounds(GBounds out, {GMatrix2? transform}) {
    final history = _store.trail;
    final renderer = _store.trailRenderer as _ParticleTrailPainter?;
    if (history == null || renderer == null || _store.count == 0) return;
    renderer.includeBounds(
      this,
      history,
      _store.count,
      out,
      transform: transform,
    );
  }

  void _transformTrailHistory(GMatrix2 transform) {
    final history = _store.trail;
    if (history == null) return;
    for (var particle = 0; particle < _store.count; ++particle) {
      final valid = history.length[particle];
      for (var age = 0; age < valid; ++age) {
        final index = history.sampleIndex(particle, age);
        final x = history.x[index];
        final y = history.y[index];
        history.x[index] = transform.a * x + transform.c * y + transform.tx;
        history.y[index] = transform.b * x + transform.d * y + transform.ty;
      }
    }
    history.version++;
  }
}

abstract interface class _ParticleTrailPainter {
  int paint(
    GParticleEmitter emitter,
    ParticleTrailStore history,
    int particleCount,
    GRenderContext context,
  );

  void includeBounds(
    GParticleEmitter emitter,
    ParticleTrailStore history,
    int particleCount,
    GBounds out, {
    GMatrix2? transform,
  });

  void dispose();
}

/// Cheap fixed-width line trail renderer.
///
/// With no alpha curve this remains exactly one `drawRawPoints` submission.
/// Fading is explicitly quantized into at most four retained line bands.
final class _ParticleLineTrailRenderer implements _ParticleTrailPainter {
  _ParticleLineTrailRenderer(int capacity, this.config)
    : _bandCount = config.alpha == null ? 1 : math.min(4, config.samples - 1),
      _bands = _buildBands(capacity, config) {
    for (final band in _bands) {
      band.paint.style = ui.PaintingStyle.stroke;
      band.paint.strokeCap = ui.StrokeCap.butt;
      band.paint.strokeWidth = config.width;
      band.paint.blendMode = config.blendMode;
      band.paint.isAntiAlias = true;
    }
  }

  final GParticleTrail config;
  final int _bandCount;
  final List<_ParticleTrailBand> _bands;
  final GBounds _bounds = GBounds.empty();
  final GBounds _transformedBounds = GBounds.empty();
  final GMatrix2 _inverseWorld = GMatrix2();

  int _packedVersion = -1;
  int _packedParticles = -1;

  @override
  int paint(
    GParticleEmitter emitter,
    ParticleTrailStore history,
    int particleCount,
    GRenderContext context,
  ) {
    _ensurePacked(emitter, history, particleCount);
    if (context.alpha <= 0.0) return 0;

    final canvas = context.canvas;
    var cancelledWorld = false;
    if (emitter._space == GParticleSpace.world) {
      if (!emitter.worldMatrix.invertInto(_inverseWorld)) return 0;
      canvas.save();
      context.transform(_inverseWorld);
      cancelledWorld = true;
    }

    var draws = 0;
    try {
      for (final band in _bands) {
        final slice = band.sliceForPackedSegments();
        if (slice == null || band.alphaFactor <= 0.0) continue;
        band.configurePaint(context, config.color);
        canvas.drawRawPoints(ui.PointMode.lines, slice.points, band.paint);
        draws++;
      }
    } finally {
      if (cancelledWorld) canvas.restore();
    }
    return draws;
  }

  @override
  void includeBounds(
    GParticleEmitter emitter,
    ParticleTrailStore history,
    int particleCount,
    GBounds out, {
    GMatrix2? transform,
  }) {
    _ensurePacked(emitter, history, particleCount);
    if (_bounds.isEmpty) return;
    if (transform == null) {
      out.includeBounds(_bounds);
      return;
    }
    transform.transformBoundsInto(_bounds, _transformedBounds);
    out.includeBounds(_transformedBounds);
  }

  void _ensurePacked(
    GParticleEmitter emitter,
    ParticleTrailStore history,
    int particleCount,
  ) {
    if (_packedVersion == history.version && _packedParticles == particleCount) {
      return;
    }

    for (final band in _bands) {
      band.beginPack();
    }

    final store = emitter._store;
    _bounds.setEmpty();
    final historySamples = config.samples - 1;
    for (var particle = 0; particle < particleCount; ++particle) {
      var x1 = store.x[particle];
      var y1 = store.y[particle];
      final valid = history.length[particle];
      for (var age = 0; age < valid; ++age) {
        final older = history.sampleIndex(particle, age);
        final x2 = history.x[older];
        final y2 = history.y[older];
        final dx = x2 - x1;
        final dy = y2 - y1;
        if (dx * dx + dy * dy > 1e-12) {
          final bandIndex = _bandCount == 1
              ? 0
              : math.min(
                  _bandCount - 1,
                  age * _bandCount ~/ historySamples,
                );
          _bands[bandIndex].push(x1, y1, x2, y2);
          _bounds.includePoint(x1, y1);
          _bounds.includePoint(x2, y2);
        }
        x1 = x2;
        y1 = y2;
      }
    }

    for (final band in _bands) {
      band.endPack();
    }
    if (!_bounds.isEmpty) {
      final radius = config.width * 0.5;
      _bounds.set(
        _bounds.x1 - radius,
        _bounds.y1 - radius,
        _bounds.x2 + radius,
        _bounds.y2 + radius,
      );
    }
    _packedVersion = history.version;
    _packedParticles = particleCount;
  }

  static List<_ParticleTrailBand> _buildBands(
    int capacity,
    GParticleTrail config,
  ) {
    final historySamples = config.samples - 1;
    final bandCount = config.alpha == null ? 1 : math.min(4, historySamples);
    final agesPerBand = List<int>.filled(bandCount, 0);
    for (var age = 0; age < historySamples; ++age) {
      final band = bandCount == 1 ? 0 : math.min(bandCount - 1, age * bandCount ~/ historySamples);
      agesPerBand[band]++;
    }

    return List<_ParticleTrailBand>.generate(bandCount, (index) {
      final normalized = bandCount == 1 ? 0.0 : (index + .5) / bandCount;
      final alpha = config.alpha?._sample(normalized) ?? 1.0;
      return _ParticleTrailBand(
        capacity * agesPerBand[index],
        alpha.clamp(0.0, 1.0).toDouble(),
      );
    }, growable: false);
  }

  @override
  void dispose() {}
}

final class _ParticleTrailBand {
  _ParticleTrailBand(int maximumSegments, this.alphaFactor)
    : points = Float32List(maximumSegments * 4) {
    _buildSlices(maximumSegments);
  }

  final double alphaFactor;
  final Float32List points;
  final List<_ParticleTrailSlice> _slices = <_ParticleTrailSlice>[];
  final ui.Paint paint = ui.Paint();

  int packedSegments = 0;
  int _lastSegments = 0;
  int _cachedPackedColor = -1;
  double _cachedRedMultiplier = double.nan;
  double _cachedGreenMultiplier = double.nan;
  double _cachedBlueMultiplier = double.nan;
  double _cachedAlphaMultiplier = double.nan;
  double _cachedRedOffset = double.nan;
  double _cachedGreenOffset = double.nan;
  double _cachedBlueOffset = double.nan;
  double _cachedAlphaOffset = double.nan;
  double _cachedTransformAlpha = double.nan;

  void beginPack() => packedSegments = 0;

  void push(double x1, double y1, double x2, double y2) {
    final base = packedSegments * 4;
    points[base] = x1;
    points[base + 1] = y1;
    points[base + 2] = x2;
    points[base + 3] = y2;
    packedSegments++;
  }

  void endPack() {
    if (packedSegments < _lastSegments) {
      points.fillRange(packedSegments * 4, _lastSegments * 4, 0.0);
    }
    _lastSegments = packedSegments;
  }

  _ParticleTrailSlice? sliceForPackedSegments() {
    if (packedSegments <= 0) return null;
    for (final slice in _slices) {
      if (slice.length >= packedSegments) return slice;
    }
    return _slices.last;
  }

  void configurePaint(GRenderContext context, ui.Color baseColor) {
    final effectiveAlpha = context.alpha * alphaFactor;
    if (!context.hasColorTransform) {
      if (paint.colorFilter != null) paint.colorFilter = null;
      final packed = _multiplyPackedAlpha(_packColor(baseColor), effectiveAlpha);
      if (_cachedPackedColor != packed) {
        _cachedPackedColor = packed;
        paint.color = ui.Color(packed);
      }
      _cachedRedMultiplier = double.nan;
      return;
    }

    final color = context.colorTransform;
    final unchanged =
        _cachedRedMultiplier == color.redMultiplier &&
        _cachedGreenMultiplier == color.greenMultiplier &&
        _cachedBlueMultiplier == color.blueMultiplier &&
        _cachedAlphaMultiplier == color.alphaMultiplier &&
        _cachedRedOffset == color.redOffset &&
        _cachedGreenOffset == color.greenOffset &&
        _cachedBlueOffset == color.blueOffset &&
        _cachedAlphaOffset == color.alphaOffset &&
        _cachedTransformAlpha == effectiveAlpha;
    if (unchanged) return;

    _cachedRedMultiplier = color.redMultiplier;
    _cachedGreenMultiplier = color.greenMultiplier;
    _cachedBlueMultiplier = color.blueMultiplier;
    _cachedAlphaMultiplier = color.alphaMultiplier;
    _cachedRedOffset = color.redOffset;
    _cachedGreenOffset = color.greenOffset;
    _cachedBlueOffset = color.blueOffset;
    _cachedAlphaOffset = color.alphaOffset;
    _cachedTransformAlpha = effectiveAlpha;
    _cachedPackedColor = -1;
    paint.color = baseColor;
    paint.colorFilter = ui.ColorFilter.matrix(<double>[
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
      color.blueOffset,
      0,
      0,
      0,
      color.alphaMultiplier * effectiveAlpha,
      color.alphaOffset * effectiveAlpha,
    ]);
  }

  void _buildSlices(int maximumSegments) {
    if (maximumSegments == 0) return;
    var length = 1;
    while (true) {
      final sliceLength = math.min(length, maximumSegments);
      _slices.add(
        _ParticleTrailSlice(
          sliceLength,
          Float32List.sublistView(points, 0, sliceLength * 4),
        ),
      );
      if (sliceLength == maximumSegments) break;
      length *= 2;
      if (length > maximumSegments) length = maximumSegments;
    }
  }
}

final class _ParticleTrailSlice {
  const _ParticleTrailSlice(this.length, this.points);

  final int length;
  final Float32List points;
}

/// Rich tapered ribbon renderer using retained packed triangle/color buffers.
final class _ParticleRibbonTrailRenderer implements _ParticleTrailPainter {
  _ParticleRibbonTrailRenderer(int capacity, this.config)
    : _positions = Float32List(capacity * (config.samples - 1) * 12),
      _colors = Int32List(capacity * (config.samples - 1) * 6),
      _textureCoordinates = config.texture == null
          ? null
          : Float32List(capacity * (config.samples - 1) * 12),
      _segmentLengths = Float64List(config.samples - 1),
      _normalX = Float64List(config.samples - 1),
      _normalY = Float64List(config.samples - 1),
      _headColor = _packColor(config.color),
      _tailColor = _packColor(config.tailColor) {
    _configureTextureMapping();
    _buildSlices(capacity * (config.samples - 1));
    _paint.isAntiAlias = true;
    _paint.blendMode = config.blendMode;
    _paint.color = const ui.Color(0xffffffff);
  }

  static final Float64List _identityShaderMatrix = Float64List.fromList(
    <double>[
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      1,
    ],
  );

  final GParticleTrail config;
  final Float32List _positions;
  final Int32List _colors;
  final Float32List? _textureCoordinates;
  final Float64List _segmentLengths;
  final Float64List _normalX;
  final Float64List _normalY;
  final int _headColor;
  final int _tailColor;
  final List<_ParticleRibbonSlice> _slices = <_ParticleRibbonSlice>[];
  final ui.Paint _paint = ui.Paint();
  final GBounds _bounds = GBounds.empty();
  final GBounds _transformedBounds = GBounds.empty();
  final GMatrix2 _inverseWorld = GMatrix2();

  ui.ImageShader? _shader;
  double _uvBaseX = 0.0;
  double _uvBaseY = 0.0;
  double _uvUx = 0.0;
  double _uvUy = 0.0;
  double _uvVx = 0.0;
  double _uvVy = 0.0;
  double _joinX = 0.0;
  double _joinY = 0.0;

  int _packedVersion = -1;
  int _packedParticles = -1;
  int _segments = 0;
  int _lastSegments = 0;
  int _cachedPaintAlpha = -1;
  double _cachedRedMultiplier = double.nan;
  double _cachedGreenMultiplier = double.nan;
  double _cachedBlueMultiplier = double.nan;
  double _cachedAlphaMultiplier = double.nan;
  double _cachedRedOffset = double.nan;
  double _cachedGreenOffset = double.nan;
  double _cachedBlueOffset = double.nan;
  double _cachedAlphaOffset = double.nan;

  @override
  int paint(
    GParticleEmitter emitter,
    ParticleTrailStore history,
    int particleCount,
    GRenderContext context,
  ) {
    final texture = config.texture;
    if (texture?.isDisposed ?? false) {
      assert(false, 'A GTexture referenced by a live particle ribbon was disposed.');
      return 0;
    }
    _ensurePacked(emitter, history, particleCount);
    final slice = _sliceFor(_segments);
    if (slice == null || context.alpha <= 0.0) return 0;
    _configurePaint(context);
    _paint.shader = texture == null ? null : _resolveShader(texture);

    final canvas = context.canvas;
    var cancelledWorld = false;
    if (emitter._space == GParticleSpace.world) {
      if (!emitter.worldMatrix.invertInto(_inverseWorld)) return 0;
      canvas.save();
      context.transform(_inverseWorld);
      cancelledWorld = true;
    }

    try {
      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        slice.positions,
        textureCoordinates: slice.textureCoordinates,
        colors: slice.colors,
      );
      try {
        canvas.drawVertices(vertices, ui.BlendMode.modulate, _paint);
      } finally {
        vertices.dispose();
      }
    } finally {
      if (cancelledWorld) canvas.restore();
    }
    return 1;
  }

  @override
  void includeBounds(
    GParticleEmitter emitter,
    ParticleTrailStore history,
    int particleCount,
    GBounds out, {
    GMatrix2? transform,
  }) {
    _ensurePacked(emitter, history, particleCount);
    if (_bounds.isEmpty) return;
    if (transform == null) {
      out.includeBounds(_bounds);
      return;
    }
    transform.transformBoundsInto(_bounds, _transformedBounds);
    out.includeBounds(_transformedBounds);
  }

  void _ensurePacked(
    GParticleEmitter emitter,
    ParticleTrailStore history,
    int particleCount,
  ) {
    if (_packedVersion == history.version && _packedParticles == particleCount) {
      return;
    }

    final store = emitter._store;
    final historySamples = config.samples - 1;
    final repeatLength = config.textureRepeatLength;
    final textured = _textureCoordinates != null;
    _bounds.setEmpty();
    var segments = 0;

    for (var particle = 0; particle < particleCount; ++particle) {
      final particleAlpha = _particleTrailLifetimeAlpha(emitter, particle);
      var x1 = store.x[particle];
      var y1 = store.y[particle];
      final valid = history.length[particle];
      var totalLength = 0.0;

      for (var age = 0; age < valid; ++age) {
        final older = history.sampleIndex(particle, age);
        final x2 = history.x[older];
        final y2 = history.y[older];
        final dx = x2 - x1;
        final dy = y2 - y1;
        final length2 = dx * dx + dy * dy;
        if (length2 > 1e-12) {
          final length = math.sqrt(length2);
          _segmentLengths[age] = length;
          _normalX[age] = -dy / length;
          _normalY[age] = dx / length;
          totalLength += length;
        } else {
          _segmentLengths[age] = 0.0;
          _normalX[age] = 0.0;
          _normalY[age] = 0.0;
        }
        x1 = x2;
        y1 = y2;
      }

      if (totalLength <= 1e-12) continue;

      x1 = store.x[particle];
      y1 = store.y[particle];
      var traversed = 0.0;
      for (var age = 0; age < valid; ++age) {
        final older = history.sampleIndex(particle, age);
        final x2 = history.x[older];
        final y2 = history.y[older];
        final segmentLength = _segmentLengths[age];
        if (segmentLength > 0.0) {
          final t0 = age / historySamples;
          final t1 = (age + 1) / historySamples;
          final width0 = _lerp(config.width, config.tailWidth, t0) * .5;
          final width1 = _lerp(config.width, config.tailWidth, t1) * .5;

          _computeJoinOffset(age, valid, width0, atStart: true);
          final startOffsetX = _joinX;
          final startOffsetY = _joinY;
          _computeJoinOffset(age, valid, width1, atStart: false);
          final endOffsetX = _joinX;
          final endOffsetY = _joinY;

          final ax = x1 + startOffsetX;
          final ay = y1 + startOffsetY;
          final bx = x1 - startOffsetX;
          final by = y1 - startOffsetY;
          final cx = x2 + endOffsetX;
          final cy = y2 + endOffsetY;
          final dx2 = x2 - endOffsetX;
          final dy2 = y2 - endOffsetY;
          final color0 = _colorAt(t0, particleAlpha);
          final color1 = _colorAt(t1, particleAlpha);
          final p = segments * 12;
          _positions[p] = ax;
          _positions[p + 1] = ay;
          _positions[p + 2] = bx;
          _positions[p + 3] = by;
          _positions[p + 4] = cx;
          _positions[p + 5] = cy;
          _positions[p + 6] = cx;
          _positions[p + 7] = cy;
          _positions[p + 8] = bx;
          _positions[p + 9] = by;
          _positions[p + 10] = dx2;
          _positions[p + 11] = dy2;
          final c = segments * 6;
          _colors[c] = color0;
          _colors[c + 1] = color0;
          _colors[c + 2] = color1;
          _colors[c + 3] = color1;
          _colors[c + 4] = color0;
          _colors[c + 5] = color1;

          if (textured) {
            final u0 = repeatLength == null ? traversed / totalLength : traversed / repeatLength;
            final u1 = repeatLength == null
                ? (traversed + segmentLength) / totalLength
                : (traversed + segmentLength) / repeatLength;
            _writeSegmentTextureCoordinates(p, u0, u1);
          }

          _bounds.includePoint(ax, ay);
          _bounds.includePoint(bx, by);
          _bounds.includePoint(cx, cy);
          _bounds.includePoint(dx2, dy2);
          segments++;
          traversed += segmentLength;
        }
        x1 = x2;
        y1 = y2;
      }
    }

    if (segments < _lastSegments) {
      _positions.fillRange(segments * 12, _lastSegments * 12, 0.0);
      _colors.fillRange(segments * 6, _lastSegments * 6, 0);
      _textureCoordinates?.fillRange(
        segments * 12,
        _lastSegments * 12,
        0.0,
      );
    }
    _segments = segments;
    _lastSegments = segments;
    _packedVersion = history.version;
    _packedParticles = particleCount;
  }

  void _computeJoinOffset(
    int segment,
    int valid,
    double halfWidth, {
    required bool atStart,
  }) {
    final nx = _normalX[segment];
    final ny = _normalY[segment];
    final adjacent = atStart ? segment - 1 : segment + 1;
    if (adjacent < 0 || adjacent >= valid || _segmentLengths[adjacent] <= 0.0) {
      _joinX = nx * halfWidth;
      _joinY = ny * halfWidth;
      return;
    }

    final sumX = nx + _normalX[adjacent];
    final sumY = ny + _normalY[adjacent];
    final sumLength2 = sumX * sumX + sumY * sumY;
    if (sumLength2 <= 1e-12) {
      _joinX = nx * halfWidth;
      _joinY = ny * halfWidth;
      return;
    }

    final inverse = 1.0 / math.sqrt(sumLength2);
    final mx = sumX * inverse;
    final my = sumY * inverse;
    final dot = mx * nx + my * ny;
    if (dot <= .25) {
      _joinX = nx * halfWidth;
      _joinY = ny * halfWidth;
      return;
    }

    final scale = math.min(halfWidth / dot, halfWidth * 2.0);
    _joinX = mx * scale;
    _joinY = my * scale;
  }

  void _configureTextureMapping() {
    final texture = config.texture;
    if (texture == null) return;
    final repeatLength = config.textureRepeatLength;
    if (repeatLength != null) {
      _uvBaseX = .5;
      _uvBaseY = .5;
      _uvUx = texture.image.width.toDouble();
      _uvUy = 0.0;
      _uvVx = 0.0;
      _uvVy = math.max(0.0, texture.image.height - 1.0);
      return;
    }

    final frame = texture.frame;
    final region = frame.region;
    final x0 = region.x + .5;
    final y0 = region.y + .5;
    final xSpan = math.max(0.0, region.w - 1.0);
    final ySpan = math.max(0.0, region.h - 1.0);
    if (frame.rotated) {
      _uvBaseX = x0 + xSpan;
      _uvBaseY = y0;
      _uvUx = 0.0;
      _uvUy = ySpan;
      _uvVx = -xSpan;
      _uvVy = 0.0;
    } else {
      _uvBaseX = x0;
      _uvBaseY = y0;
      _uvUx = xSpan;
      _uvUy = 0.0;
      _uvVx = 0.0;
      _uvVy = ySpan;
    }
  }

  void _writeSegmentTextureCoordinates(int base, double u0, double u1) {
    _writeTextureCoordinate(base, u0, 0.0);
    _writeTextureCoordinate(base + 2, u0, 1.0);
    _writeTextureCoordinate(base + 4, u1, 0.0);
    _writeTextureCoordinate(base + 6, u1, 0.0);
    _writeTextureCoordinate(base + 8, u0, 1.0);
    _writeTextureCoordinate(base + 10, u1, 1.0);
  }

  void _writeTextureCoordinate(int offset, double u, double v) {
    final target = _textureCoordinates!;
    target[offset] = _uvBaseX + _uvUx * u + _uvVx * v;
    target[offset + 1] = _uvBaseY + _uvUy * u + _uvVy * v;
  }

  ui.ImageShader _resolveShader(GTexture texture) {
    final cached = _shader;
    if (cached != null) return cached;
    return _shader = ui.ImageShader(
      texture.image,
      config.textureRepeatLength == null ? ui.TileMode.clamp : ui.TileMode.repeated,
      ui.TileMode.clamp,
      _identityShaderMatrix,
      filterQuality: ui.FilterQuality.low,
    );
  }

  int _colorAt(double t, double particleAlpha) {
    final color = _lerpPackedColor(_headColor, _tailColor, t);
    final trailAlpha = config.alpha?._sample(t) ?? 1.0;
    final alpha = (trailAlpha * particleAlpha).clamp(0.0, 1.0).toDouble();
    return _multiplyPackedAlpha(color, alpha);
  }

  void _configurePaint(GRenderContext context) {
    final alpha = (context.alpha.clamp(0.0, 1.0) * 255).round();
    if (!context.hasColorTransform) {
      if (_paint.colorFilter != null) _paint.colorFilter = null;
      if (_cachedPaintAlpha != alpha) {
        _cachedPaintAlpha = alpha;
        _paint.color = ui.Color.fromARGB(alpha, 255, 255, 255);
      }
      _cachedRedMultiplier = double.nan;
      return;
    }

    final color = context.colorTransform;
    final unchanged =
        _cachedRedMultiplier == color.redMultiplier &&
        _cachedGreenMultiplier == color.greenMultiplier &&
        _cachedBlueMultiplier == color.blueMultiplier &&
        _cachedAlphaMultiplier == color.alphaMultiplier &&
        _cachedRedOffset == color.redOffset &&
        _cachedGreenOffset == color.greenOffset &&
        _cachedBlueOffset == color.blueOffset &&
        _cachedAlphaOffset == color.alphaOffset &&
        _cachedPaintAlpha == alpha;
    if (unchanged) return;

    _cachedRedMultiplier = color.redMultiplier;
    _cachedGreenMultiplier = color.greenMultiplier;
    _cachedBlueMultiplier = color.blueMultiplier;
    _cachedAlphaMultiplier = color.alphaMultiplier;
    _cachedRedOffset = color.redOffset;
    _cachedGreenOffset = color.greenOffset;
    _cachedBlueOffset = color.blueOffset;
    _cachedAlphaOffset = color.alphaOffset;
    _cachedPaintAlpha = alpha;
    final hostAlpha = alpha / 255.0;
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
      color.blueOffset,
      0,
      0,
      0,
      color.alphaMultiplier * hostAlpha,
      color.alphaOffset * hostAlpha,
    ]);
  }

  void _buildSlices(int maximumSegments) {
    if (maximumSegments == 0) return;
    var length = 1;
    while (true) {
      final sliceLength = math.min(length, maximumSegments);
      _slices.add(
        _ParticleRibbonSlice(
          sliceLength,
          Float32List.sublistView(_positions, 0, sliceLength * 12),
          Int32List.sublistView(_colors, 0, sliceLength * 6),
          _textureCoordinates == null
              ? null
              : Float32List.sublistView(
                  _textureCoordinates,
                  0,
                  sliceLength * 12,
                ),
        ),
      );
      if (sliceLength == maximumSegments) break;
      length *= 2;
      if (length > maximumSegments) length = maximumSegments;
    }
  }

  _ParticleRibbonSlice? _sliceFor(int segments) {
    if (segments <= 0) return null;
    for (final slice in _slices) {
      if (slice.length >= segments) return slice;
    }
    return _slices.last;
  }

  @override
  void dispose() {
    _paint.shader = null;
    _shader?.dispose();
    _shader = null;
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

final class _ParticleRibbonSlice {
  const _ParticleRibbonSlice(
    this.length,
    this.positions,
    this.colors,
    this.textureCoordinates,
  );

  final int length;
  final Float32List positions;
  final Int32List colors;
  final Float32List? textureCoordinates;
}
