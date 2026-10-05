import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_particles/src/particle_random.dart';

void main() {
  test('xorshift sequence is stable for a seeded stream', () {
    final random = ParticleRandom(42);
    expect(random.nextUint32(), 11355432);
    expect(random.nextUint32(), 2836018348);
    expect(random.nextUint32(), 476557059);
    expect(random.nextUint32(), 3648046016);
    expect(random.nextUint32(), 3759983556);
  });

  test('resetting a seed reproduces the stream', () {
    final random = ParticleRandom(0x1234);
    final first = List<int>.generate(16, (_) => random.nextUint32());
    random.seed = 0x1234;
    final second = List<int>.generate(16, (_) => random.nextUint32());
    expect(second, first);
  });

  test('zero seed maps to the documented non-zero stream', () {
    final a = ParticleRandom(0);
    final b = ParticleRandom(0x6d2b79f5);
    for (var i = 0; i < 16; ++i) {
      expect(a.nextUint32(), b.nextUint32());
    }
  });

  test('nextInt stays inside its half-open range', () {
    final random = ParticleRandom(7);
    for (var i = 0; i < 1000; ++i) {
      expect(random.nextInt(7), inInclusiveRange(0, 6));
    }
    expect(() => random.nextInt(0), throwsRangeError);
  });
}
