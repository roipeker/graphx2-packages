# graphx_motion

Allocation-aware motion, timelines, keyframes, and physics for GraphX.

Use `package:graphx_motion/motion.dart` for the host-independent motion engine, or
`package:graphx_motion/graphx_motion.dart` for GraphX node, stage, filter, image,
shader, path, and color integrations.

## Core model

```text
to(...)          start one destination now
clip(...)        describe one destination
keyframes(...)   describe several destinations
timeline         compose retained clips
stagger(...)     distribute clips in time
spring/damp/...  settle-driven physics
```

The generic engine does not depend on GraphX. The GraphX layer binds it to the
Stage update loop and gives scene objects typed `.motion` facades.

## Node motion

```dart
node.motion.to(
  x: 320,
  y: 180,
  rotation: 1.2,
  scale: 1.15,
  alpha: .8,
  duration: .5,
  ease: Ease.cubic.easeOut,
);
```

Each property keeps independent overwrite identity. Replacing only `x` does not
cancel the same motion's `y`, rotation, scale, or alpha tracks.

Stage defaults are optional:

```dart
stage.motion.defaults = const MotionSpec(
  duration: .35,
  ease: Ease.cubic.easeOut,
);

const pop = MotionSpec(duration: .22, ease: Ease.back.easeOut);

node.motion.to(x: 300);
node.motion.to(scale: 1.15, motion: pop);
node.motion.to(scale: 1.15, motion: pop, duration: .4);
```

Resolution is deterministic:

```text
built-in -> Stage defaults -> MotionSpec -> explicit arguments
```

## Retained clips and timelines

`to()` starts immediately. `clip()` describes the same work without starting it.

```dart
final timeline = stage.motion.timeline();
timeline.add(node.motion.clip(x: 300, alpha: 1));
timeline.add(
  glow.motion.clip(blurX: 18, blurY: 18, spread: 3),
  at: 0,
);
timeline.play();
```

Timelines use the same pooled motion runtimes as immediate motion. Nested timelines
are flattened under one deterministic root playhead.

```dart
final intro = stage.motion.timeline(
  defaults: const MotionSpec(
    duration: .4,
    ease: Ease.cubic.easeOut,
  ),
);
intro.label(#start);
intro.add(title.motion.clip(y: 0, alpha: 1));
intro.add(card.motion.clip(scale: 1, alpha: 1), at: #start);
intro.wait(.1);
intro.call(onIntroDone);
intro.play();
```

Finite motion and timelines share `time`, `progress`, `seek`, `seekTime`, and
`reverse`. A playhead can itself be driven by Motion.

## Keyframes

```dart
final clip = card.motion.keyframes(
  (frames) {
    frames.at(0, y: 30, alpha: 0);
    frames.at(.4, y: -8, scale: 1.12, ease: Ease.back.easeOut);
    frames.at(1, y: 0, scale: 1, alpha: 1);
    return frames;
  },
  duration: .8,
);

timeline.add(clip);
```

Frames are sparse. Missing values resolve from surrounding authored frames and the
actual value captured at clip start.

Generic properties use the same model:

```dart
final radius = MotionProperty<double>(
  owner: state,
  read: () => state.radius,
  write: (value) => state.radius = value,
);

final frames = radius.keyframes(duration: 1);
frames.at(0, 20);
frames.at(.5, 120, ease: Ease.back.easeOut);
frames.at(1, 40);
timeline.add(frames);
```

## Physics

Spring, damp, and inertia are settle-driven rather than deterministic timeline
playheads.

```dart
node.motion.spring(
  x: 320,
  y: 180,
  spring: const Spring(stiffness: 180, damping: 18),
);
```

Physics keeps normal property overwrite semantics, including velocity inheritance
when a spring is retargeted.

## Arbitrary values

Motion is not limited to GraphX objects.

```dart
final progress = MotionProperty<double>(
  owner: controller,
  read: () => controller.progress,
  write: (value) => controller.progress = value,
);

stage.motion.to<double>(progress, 1);
```

Custom owners are caller-managed. GraphX node disposal and lightweight
`GImageInstance` ownership are recognized by the GraphX integration layer.

## Paths

`graphx_motion` depends on `graphx_paths`. A `GPathFollower` exposes stable
motion properties so path progress can participate in ordinary tweens, clips, and
timelines.

## Validation

```bash
flutter analyze
flutter test
```
