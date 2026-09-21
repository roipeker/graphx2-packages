import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_motion/graphx_motion.dart';

void main() {
  test('stagger from start expands to deterministic timeline placements', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    final values = [0.0, 0.0, 0.0];
    final properties = List.generate(
      values.length,
      (i) => MotionProperty<double>(
        read: () => values[i],
        write: (next) => values[i] = next,
      ),
    );

    final timeline = engine.timeline(
      defaults: const MotionSpec(duration: .2, ease: Ease.linear),
    );
    timeline.stagger(
      properties,
      each: .1,
      clip: (property, _) => property.clip(10),
    );

    expect(timeline.duration, closeTo(.4, 1e-9));
    timeline.time = .15;
    expect(values[0], closeTo(7.5, 1e-9));
    expect(values[1], closeTo(2.5, 1e-9));
    expect(values[2], closeTo(0, 1e-9));

    timeline.dispose();
    engine.dispose();
  });

  test('stagger from end reverses placement without reversing item indices', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    final values = [0.0, 0.0, 0.0];
    final properties = List.generate(
      values.length,
      (i) => MotionProperty<double>(
        read: () => values[i],
        write: (next) => values[i] = next,
      ),
    );
    final seenIndices = <int>[];

    final timeline = engine.timeline(
      defaults: const MotionSpec(duration: .2, ease: Ease.linear),
    );
    timeline.stagger(
      properties,
      each: .1,
      from: StaggerFrom.end,
      clip: (property, index) {
        seenIndices.add(index);
        return property.clip(10);
      },
    );

    expect(seenIndices, [0, 1, 2]);
    timeline.time = .05;
    expect(values[0], closeTo(0, 1e-9));
    expect(values[1], closeTo(0, 1e-9));
    expect(values[2], closeTo(2.5, 1e-9));

    timeline.dispose();
    engine.dispose();
  });

  test('center stagger starts odd center and even middle pair at base', () {
    for (final count in [4, 5]) {
      final engine = MotionEngine();
      engine.maxDelta = double.infinity;
      final values = List<double>.filled(count, 0);
      final properties = List.generate(
        count,
        (i) => MotionProperty<double>(
          read: () => values[i],
          write: (next) => values[i] = next,
        ),
      );

      final timeline = engine.timeline(
        defaults: const MotionSpec(duration: .2, ease: Ease.linear),
      );
      timeline.stagger(
        properties,
        each: .1,
        from: StaggerFrom.center,
        clip: (property, _) => property.clip(10),
      );

      timeline.time = .05;
      if (count.isEven) {
        expect(values[1], closeTo(2.5, 1e-9));
        expect(values[2], closeTo(2.5, 1e-9));
        expect(values[0], closeTo(0, 1e-9));
        expect(values[3], closeTo(0, 1e-9));
      } else {
        expect(values[2], closeTo(2.5, 1e-9));
        expect(values[1], closeTo(0, 1e-9));
        expect(values[3], closeTo(0, 1e-9));
      }

      timeline.dispose();
      engine.dispose();
    }
  });

  test('stagger respects labels and remains ordinary seekable timeline content', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    final values = [0.0, 0.0];
    final properties = List.generate(
      values.length,
      (i) => MotionProperty<double>(
        read: () => values[i],
        write: (next) => values[i] = next,
      ),
    );

    final timeline = engine.timeline(
      defaults: const MotionSpec(duration: .2, ease: Ease.linear),
    );
    timeline.wait(.3);
    timeline.label(#entrance);
    timeline.stagger(
      properties,
      each: .1,
      at: #entrance,
      clip: (property, _) => property.clip(10),
    );

    timeline.time = .35;
    expect(values[0], closeTo(2.5, 1e-9));
    expect(values[1], closeTo(0, 1e-9));

    timeline.time = 0;
    expect(values, [0, 0]);

    timeline.dispose();
    engine.dispose();
  });

  test('zero spacing starts every stagger item at the same position', () {
    final engine = MotionEngine();
    engine.maxDelta = double.infinity;
    final values = [0.0, 0.0, 0.0];
    final properties = List.generate(
      values.length,
      (i) => MotionProperty<double>(
        read: () => values[i],
        write: (next) => values[i] = next,
      ),
    );

    final timeline = engine.timeline(
      defaults: const MotionSpec(duration: .2, ease: Ease.linear),
    );
    timeline.stagger(
      properties,
      each: 0,
      from: StaggerFrom.center,
      clip: (property, _) => property.clip(10),
    );

    expect(timeline.duration, closeTo(.2, 1e-9));
    timeline.time = .1;
    expect(values, everyElement(closeTo(5, 1e-9)));

    timeline.dispose();
    engine.dispose();
  });

  test('empty stagger is a no-op and invalid spacing fails early', () {
    final engine = MotionEngine();
    final timeline = engine.timeline();
    timeline.wait(.3);

    timeline.stagger<Object>(
      const [],
      each: .1,
      clip: (_, _) => throw StateError('builder must not run'),
    );
    expect(timeline.duration, closeTo(.3, 1e-9));

    expect(
      () => timeline.stagger<Object>(
        const [Object()],
        each: -1,
        clip: (_, _) => throw StateError('builder must not run'),
      ),
      throwsArgumentError,
    );

    timeline.dispose();
    engine.dispose();
  });
}
