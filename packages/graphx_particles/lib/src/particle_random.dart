final class ParticleRandom {
  ParticleRandom(int seed) : _state = _normalizeSeed(seed);

  static const int _mask = 0xffffffff;
  static const int _fallbackSeed = 0x6d2b79f5;
  static const double _uint32Scale = 1.0 / 4294967296.0;

  int _state;

  int get state => _state;

  set seed(int value) => _state = _normalizeSeed(value);

  int nextUint32() {
    var x = _state;
    x ^= (x << 13) & _mask;
    x ^= x >> 17;
    x ^= (x << 5) & _mask;
    x &= _mask;
    _state = x;
    return x;
  }

  double nextDouble() => nextUint32() * _uint32Scale;

  int nextInt(int max) {
    if (max <= 0) {
      throw RangeError.range(max, 1, null, 'max');
    }
    return (nextUint32() * max) >> 32;
  }

  static int _normalizeSeed(int value) {
    final normalized = value & _mask;
    return normalized == 0 ? _fallbackSeed : normalized;
  }
}
