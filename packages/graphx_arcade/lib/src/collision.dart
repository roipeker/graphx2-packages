part of 'package:graphx_arcade/graphx_arcade.dart';

extension _GArcadeCollision on GArcadeWorld {
  bool _canCollide(int a, int b) {
    return (_mask[a] & _layer[b]) != 0 && (_mask[b] & _layer[a]) != 0;
  }

  void _integrateContinuousCircle(int slot, double dt) {
    assert(_shapeKind[slot] == _GShapeKind.circle.index);
    var remaining = dt;
    var impacts = 0;
    var skipSensorSlot = -1;

    while (remaining > 1e-9 && impacts < 4) {
      final startX = _x[slot];
      final startY = _y[slot];
      final moveX = _vx[slot] * remaining;
      final moveY = _vy[slot] * remaining;
      var bestT = 1.0;
      var bestSlot = -1;
      var bestNx = 0.0;
      var bestNy = 0.0;
      var bestPx = 0.0;
      var bestPy = 0.0;

      final elapsed = dt - remaining;
      for (var other = 0; other < _slotCount; other++) {
        if (other == slot ||
            other == skipSensorSlot ||
            _bodies[other] == null ||
            !_enabledBody(other)) {
          continue;
        }
        final sensorPair = _sensorBody(slot) || _sensorBody(other);
        // Physical dynamic-vs-dynamic CCD requires coupled time-of-impact
        // integration. Sensor pairs have no impulse, so their relative sweep
        // is safe and covers fast projectiles/triggers without pretending to
        // provide that larger rigid-body feature.
        if (_type[other] == GBodyType.dynamic.index && !sensorPair) continue;
        if (!_canCollide(slot, other)) continue;

        final otherStartX = _previousX[other] + _vx[other] * elapsed;
        final otherStartY = _previousY[other] + _vy[other] * elapsed;
        final relativeX = moveX - _vx[other] * remaining;
        final relativeY = moveY - _vy[other] * remaining;
        final result = _sweepResult;
        result.reset();
        final hit = _shapeKind[other] == _GShapeKind.box.index
            ? _sweepCircleBox(
                startX,
                startY,
                _shapeA[slot],
                relativeX,
                relativeY,
                otherStartX,
                otherStartY,
                other,
                result,
              )
            : _sweepCircleCircle(
                startX,
                startY,
                _shapeA[slot],
                relativeX,
                relativeY,
                otherStartX,
                otherStartY,
                other,
                result,
              );
        if (!hit || result.t >= bestT) continue;
        bestT = result.t;
        bestSlot = other;
        bestNx = result.normalX;
        bestNy = result.normalY;
        bestPx = startX + moveX * result.t + result.normalX * _shapeA[slot];
        bestPy = startY + moveY * result.t + result.normalY * _shapeA[slot];
      }

      if (bestSlot < 0) {
        _x[slot] = startX + moveX;
        _y[slot] = startY + moveY;
        return;
      }

      _x[slot] = startX + moveX * bestT;
      _y[slot] = startY + moveY * bestT;
      _touchContact(slot, bestSlot, bestNx, bestNy, bestPx, bestPy);
      final sensorHit = _sensorBody(slot) || _sensorBody(bestSlot);
      remaining *= 1 - bestT;
      impacts++;
      if (sensorHit) {
        // Sensors pass through. Ignore the just-touched target for the next
        // sweep so a t=0 boundary hit cannot consume the impact budget.
        skipSensorSlot = bestSlot;
        continue;
      }
      skipSensorSlot = -1;
      _resolveVelocity(slot, bestSlot, bestNx, bestNy);
      _x[slot] -= bestNx * 1e-7;
      _y[slot] -= bestNy * 1e-7;
    }

    if (remaining > 1e-9) {
      _x[slot] += _vx[slot] * remaining;
      _y[slot] += _vy[slot] * remaining;
    }
  }

  bool _sweepCircleBox(
    double x,
    double y,
    double radius,
    double dx,
    double dy,
    double boxX,
    double boxY,
    int box,
    _GSweepResult out,
  ) {
    final minX = boxX - _shapeA[box] - radius;
    final maxX = boxX + _shapeA[box] + radius;
    final minY = boxY - _shapeB[box] - radius;
    final maxY = boxY + _shapeB[box] + radius;

    var txMin = double.negativeInfinity;
    var txMax = double.infinity;
    var tyMin = double.negativeInfinity;
    var tyMax = double.infinity;

    if (dx == 0) {
      if (x < minX || x > maxX) return false;
    } else {
      final inv = 1 / dx;
      final t1 = (minX - x) * inv;
      final t2 = (maxX - x) * inv;
      txMin = math.min(t1, t2);
      txMax = math.max(t1, t2);
    }

    if (dy == 0) {
      if (y < minY || y > maxY) return false;
    } else {
      final inv = 1 / dy;
      final t1 = (minY - y) * inv;
      final t2 = (maxY - y) * inv;
      tyMin = math.min(t1, t2);
      tyMax = math.max(t1, t2);
    }

    final enter = math.max(txMin, tyMin);
    final exit = math.min(txMax, tyMax);
    if (enter > exit || exit < 0 || enter < 0 || enter > 1) return false;

    out.t = enter;
    if (txMin > tyMin) {
      out.normalX = dx > 0 ? 1 : -1;
      out.normalY = 0;
    } else {
      out.normalX = 0;
      out.normalY = dy > 0 ? 1 : -1;
    }
    return true;
  }

  bool _sweepCircleCircle(
    double x,
    double y,
    double radius,
    double relativeX,
    double relativeY,
    double otherX,
    double otherY,
    int other,
    _GSweepResult out,
  ) {
    final totalRadius = radius + _shapeA[other];
    final rx = x - otherX;
    final ry = y - otherY;
    final a = relativeX * relativeX + relativeY * relativeY;
    if (a <= 1e-18) return false;
    final b = 2 * (rx * relativeX + ry * relativeY);
    final c = rx * rx + ry * ry - totalRadius * totalRadius;
    final discriminant = b * b - 4 * a * c;
    if (discriminant < 0) return false;
    final t = (-b - math.sqrt(discriminant)) / (2 * a);
    if (t < 0 || t > 1) return false;

    final qx = rx + relativeX * t;
    final qy = ry + relativeY * t;
    final length = math.sqrt(qx * qx + qy * qy);
    if (length <= 1e-12) return false;
    out.t = t;
    out.normalX = -qx / length;
    out.normalY = -qy / length;
    return true;
  }

  void _solveOverlaps() {
    if (_sweepMembershipDirty) {
      var count = 0;
      for (var slot = 0; slot < _slotCount; slot++) {
        if (_bodies[slot] == null || !_enabledBody(slot)) continue;
        _sweepOrder[count++] = slot;
      }
      _sweepCount = count;
      _sweepMembershipDirty = false;
    }
    final count = _sweepCount;

    // Retain last step's sorted order and insertion-sort moved endpoints.
    // Typical arcade motion therefore approaches O(n) after the initial sort.
    // Ties use stable slot ids so pair order remains deterministic.
    for (var i = 1; i < count; i++) {
      final value = _sweepOrder[i];
      final minX = _minX(value);
      var j = i - 1;
      while (j >= 0) {
        final other = _sweepOrder[j];
        final otherMin = _minX(other);
        if (otherMin < minX || (otherMin == minX && other < value)) break;
        _sweepOrder[j + 1] = other;
        j--;
      }
      _sweepOrder[j + 1] = value;
    }

    for (var i = 0; i < count; i++) {
      final a = _sweepOrder[i];
      final maxX = _maxX(a);
      for (var j = i + 1; j < count; j++) {
        final b = _sweepOrder[j];
        if (_minX(b) > maxX) break;
        if (!_canCollide(a, b)) continue;
        if (_type[a] != GBodyType.dynamic.index && _type[b] != GBodyType.dynamic.index) {
          if (!_sensorBody(a) && !_sensorBody(b)) continue;
        }
        _resolvePair(a, b);
      }
    }
  }

  double _minX(int slot) => _x[slot] - _shapeA[slot];
  double _maxX(int slot) => _x[slot] + _shapeA[slot];

  void _resolvePair(int a, int b) {
    final result = _sweepResult;
    result.reset();
    final ak = _shapeKind[a];
    final bk = _shapeKind[b];
    final overlaps = ak == _GShapeKind.box.index
        ? (bk == _GShapeKind.box.index
              ? _overlapBoxBox(a, b, result)
              : _overlapCircleBox(b, a, result, invert: true))
        : (bk == _GShapeKind.box.index
              ? _overlapCircleBox(a, b, result)
              : _overlapCircleCircle(a, b, result));
    if (!overlaps) return;

    _touchContact(
      a,
      b,
      result.normalX,
      result.normalY,
      result.pointX,
      result.pointY,
    );
    if (_sensorBody(a) || _sensorBody(b)) return;
    _correctPenetration(a, b, result.normalX, result.normalY, result.penetration);
    _resolveVelocity(a, b, result.normalX, result.normalY);
  }

  bool _overlapBoxBox(int a, int b, _GSweepResult out) {
    final dx = _x[b] - _x[a];
    final px = _shapeA[a] + _shapeA[b] - dx.abs();
    if (px <= 0) return false;
    final dy = _y[b] - _y[a];
    final py = _shapeB[a] + _shapeB[b] - dy.abs();
    if (py <= 0) return false;

    if (px < py) {
      out.normalX = dx >= 0 ? 1 : -1;
      out.normalY = 0;
      out.penetration = px;
      out.pointX = _x[a] + out.normalX * _shapeA[a];
      out.pointY = (_y[a] + _y[b]) * .5;
    } else {
      out.normalX = 0;
      out.normalY = dy >= 0 ? 1 : -1;
      out.penetration = py;
      out.pointX = (_x[a] + _x[b]) * .5;
      out.pointY = _y[a] + out.normalY * _shapeB[a];
    }
    return true;
  }

  bool _overlapCircleCircle(int a, int b, _GSweepResult out) {
    final dx = _x[b] - _x[a];
    final dy = _y[b] - _y[a];
    final radius = _shapeA[a] + _shapeA[b];
    final dist2 = dx * dx + dy * dy;
    if (dist2 >= radius * radius) return false;
    if (dist2 <= 1e-18) {
      out.normalX = 1;
      out.normalY = 0;
      out.penetration = radius;
      out.pointX = _x[a] + _shapeA[a];
      out.pointY = _y[a];
      return true;
    }
    final distance = math.sqrt(dist2);
    final nx = dx / distance;
    final ny = dy / distance;
    out.normalX = nx;
    out.normalY = ny;
    out.penetration = radius - distance;
    out.pointX = _x[a] + nx * _shapeA[a];
    out.pointY = _y[a] + ny * _shapeA[a];
    return true;
  }

  bool _overlapCircleBox(
    int circle,
    int box,
    _GSweepResult out, {
    bool invert = false,
  }) {
    final cx = _x[circle];
    final cy = _y[circle];
    final minX = _x[box] - _shapeA[box];
    final maxX = _x[box] + _shapeA[box];
    final minY = _y[box] - _shapeB[box];
    final maxY = _y[box] + _shapeB[box];
    final closestX = cx.clamp(minX, maxX).toDouble();
    final closestY = cy.clamp(minY, maxY).toDouble();
    final dx = closestX - cx;
    final dy = closestY - cy;
    final radius = _shapeA[circle];
    final dist2 = dx * dx + dy * dy;
    if (dist2 >= radius * radius && dist2 != 0) return false;

    double nx;
    double ny;
    double penetration;
    double pointX;
    double pointY;

    if (dist2 > 1e-18) {
      final distance = math.sqrt(dist2);
      nx = dx / distance;
      ny = dy / distance;
      penetration = radius - distance;
      pointX = closestX;
      pointY = closestY;
    } else {
      final left = cx - minX;
      final right = maxX - cx;
      final top = cy - minY;
      final bottom = maxY - cy;
      final horizontal = math.min(left, right);
      final vertical = math.min(top, bottom);
      if (horizontal < vertical) {
        if (left < right) {
          nx = 1;
          pointX = minX;
          penetration = radius + left;
        } else {
          nx = -1;
          pointX = maxX;
          penetration = radius + right;
        }
        ny = 0;
        pointY = cy;
      } else {
        nx = 0;
        if (top < bottom) {
          ny = 1;
          pointY = minY;
          penetration = radius + top;
        } else {
          ny = -1;
          pointY = maxY;
          penetration = radius + bottom;
        }
        pointX = cx;
      }
    }

    if (invert) {
      nx = -nx;
      ny = -ny;
    }
    out.normalX = nx;
    out.normalY = ny;
    out.penetration = penetration;
    out.pointX = pointX;
    out.pointY = pointY;
    return true;
  }

  double _effectiveInvMass(int slot) {
    return _type[slot] == GBodyType.dynamic.index && !_controlledBody(slot) ? _invMass[slot] : 0;
  }

  void _correctPenetration(
    int a,
    int b,
    double nx,
    double ny,
    double penetration,
  ) {
    if (penetration <= 0) return;
    final ia = _effectiveInvMass(a);
    final ib = _effectiveInvMass(b);
    final total = ia + ib;
    if (total <= 0) return;
    final correction = math.max(0.0, penetration - 1e-7) / total;
    if (ia > 0) {
      _x[a] -= nx * correction * ia;
      _y[a] -= ny * correction * ia;
    }
    if (ib > 0) {
      _x[b] += nx * correction * ib;
      _y[b] += ny * correction * ib;
    }
  }

  void _resolveVelocity(int a, int b, double nx, double ny) {
    final ia = _effectiveInvMass(a);
    final ib = _effectiveInvMass(b);
    final total = ia + ib;
    if (total <= 0) return;

    final rvx = _vx[b] - _vx[a];
    final rvy = _vy[b] - _vy[a];
    final normalVelocity = rvx * nx + rvy * ny;
    if (normalVelocity >= 0) return;

    final restitution = math.max(_bounce[a], _bounce[b]);
    final impulse = -(1 + restitution) * normalVelocity / total;
    if (ia > 0) {
      _vx[a] -= impulse * nx * ia;
      _vy[a] -= impulse * ny * ia;
    }
    if (ib > 0) {
      _vx[b] += impulse * nx * ib;
      _vy[b] += impulse * ny * ib;
    }
  }

  int _contactKey(int a, int b) {
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    return (lo << 32) | hi;
  }

  void _touchContact(
    int a,
    int b,
    double nx,
    double ny,
    double pointX,
    double pointY,
  ) {
    final key = _contactKey(a, b);
    var state = _contacts[key];
    final bodyA = _bodies[a];
    final bodyB = _bodies[b];
    if (bodyA == null || bodyB == null) return;

    if (state == null) {
      final aView = GBodyContact._(bodyA, bodyB);
      final bView = GBodyContact._(bodyB, bodyA);
      state = _GContactState(a, b, aView, bView);
      _contacts[key] = state;
      _updateContactViews(state, a, nx, ny, pointX, pointY);
      state.seenStep = _stepSerial;
      _contactBegins.add(state);
      return;
    }

    _updateContactViews(state, a, nx, ny, pointX, pointY);
    state.seenStep = _stepSerial;
  }

  void _updateContactViews(
    _GContactState state,
    int reportedA,
    double nx,
    double ny,
    double pointX,
    double pointY,
  ) {
    final same = state.aSlot == reportedA;
    state.aView.normalX = same ? nx : -nx;
    state.aView.normalY = same ? ny : -ny;
    state.aView.pointX = pointX;
    state.aView.pointY = pointY;
    state.bView.normalX = same ? -nx : nx;
    state.bView.normalY = same ? -ny : ny;
    state.bView.pointX = pointX;
    state.bView.pointY = pointY;
  }

  void _finishContacts() {
    _staleContacts.clear();
    for (final entry in _contacts.entries) {
      if (entry.value.seenStep != _stepSerial) {
        _staleContacts.add(entry.key);
      }
    }
    for (final key in _staleContacts) {
      final state = _contacts.remove(key);
      if (state == null) continue;
      _contactEnds.add(state);
    }
  }

  void _removeContactsFor(int slot) {
    _staleContacts.clear();
    for (final entry in _contacts.entries) {
      final state = entry.value;
      if (state.aSlot == slot || state.bSlot == slot) {
        _staleContacts.add(entry.key);
      }
    }
    for (final key in _staleContacts) {
      final state = _contacts.remove(key);
      if (state == null) continue;
      _contactEnds.add(state);
    }
  }

  void _dispatchContactEvents() {
    if (_dispatchingContacts) return;
    _dispatchingContacts = true;
    try {
      var index = 0;
      while (index < _contactBegins.length) {
        final state = _contactBegins[index++];
        final bodyA = state.aView.body;
        if (bodyA.isAlive) bodyA._contactBegin?.emit(state.aView);
        final bodyB = state.bView.body;
        if (bodyB.isAlive) bodyB._contactBegin?.emit(state.bView);
      }
      _contactBegins.clear();

      index = 0;
      while (index < _contactEnds.length) {
        final state = _contactEnds[index++];
        final bodyA = state.aView.body;
        if (bodyA.isAlive) bodyA._contactEnd?.emit(state.aView);
        final bodyB = state.bView.body;
        if (bodyB.isAlive) bodyB._contactEnd?.emit(state.bView);
      }
      _contactEnds.clear();
    } finally {
      _dispatchingContacts = false;
    }
  }
}

final class _GContactState {
  _GContactState(this.aSlot, this.bSlot, this.aView, this.bView);

  final int aSlot;
  final int bSlot;
  final GBodyContact aView;
  final GBodyContact bView;
  int seenStep = -1;
}

final class _GSweepResult {
  double t = 1;
  double normalX = 0;
  double normalY = 0;
  double pointX = 0;
  double pointY = 0;
  double penetration = 0;

  void reset() {
    t = 1;
    normalX = normalY = pointX = pointY = penetration = 0;
  }
}
