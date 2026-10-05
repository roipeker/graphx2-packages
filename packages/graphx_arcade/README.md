# graphx_arcade

Small, deterministic 2D arcade physics for GraphX.

Arcade owns simulation and collision state outside core. GraphX nodes remain ordinary retained scene objects; binding only synchronizes position between a body and its node.

## Start here

```dart
final physics = stage.arcade;
physics.gravityY = 900;
physics.fixedStep = 1 / 120;

final playerBody = physics.box(
  player,
  width: 32,
  height: 52,
);

final floorBody = physics.box(
  floor,
  width: 800,
  height: 24,
  type: GBodyType.static,
);

player.body!.velocity.x = inputX * 220;

if (jump) {
  player.body!.velocity.y = -480;
}
```

The common mental model is deliberately small:

- build a normal GraphX scene;
- give collidable nodes a circle or box body;
- change velocity / authored kinematic position;
- react to contacts.

## Body types

`GBodyType.dynamic`
: Arcade owns simulation position and writes the bound node after stepping.

`GBodyType.kinematic`
: authored node movement drives the body. Arcade derives velocity from node movement so moving paddles/platforms participate meaningfully in collision response.

`GBodyType.static`
: immovable collision geometry. Repositioning its node updates the retained collision pose without generating physical velocity.

## Contacts

```dart
ball.body!.onContactBegin.add((contact) {
  if (identical(contact.other, brick.body)) {
    brick.dispose();
  }
});
```

Contacts expose the other body, world-space point, body-relative normal and sensor state. Begin/end views are retained rather than allocated every simulation step.

Contact callbacks run **after the fixed simulation step has finished solving**. The callback therefore sees the resolved velocity and may safely apply game rules such as overriding the outgoing velocity or destroying a contacted body. Re-entering `world.step()` / `world.advance()` from a contact callback is intentionally rejected.

## Fast bodies / CCD

Continuous collision is intentionally explicit today:

```dart
final ballBody = physics.circle(
  ball,
  radius: 8,
  bounce: 1,
  continuous: true,
);
```

Physical CCD targets fast circles against static/kinematic boxes and circles, including thin Breakout-style barriers. Continuous sensor circles also sweep filtered dynamic targets and sensors, which covers fast bullets/triggers without introducing coupled dynamic-body time-of-impact resolution.

## Fixed-step game rules

Arcade exposes the exact simulation cadence without owning game rules:

```dart
physics.onBeforeStep.add((dt) {
  ship.body!.velocity.x += thrust * dt;
});

physics.onAfterStep.add((dt) {
  // Deterministic wrapping, lifetimes, spawn timers, replay bookkeeping, etc.
});
```

Both hooks run once per fixed substep. Contact callbacks run before `onAfterStep`, and recursive `step()` / `advance()` calls from either hook are rejected.

## Manual control and teleport

Dynamic bodies normally own their pose.

For dragging/editor/scripted ownership:

```dart
final control = body.takeControl();

control.moveTo(x, y);

// Hand authority back to simulation.
control.release(
  velocityX: throwX,
  velocityY: throwY,
);
```

Teleporting is separate from physical movement:

```dart
body.teleport(400, 220);
body.teleportFromNode();
```

Teleport does not manufacture swept motion through the space between poses.

## World space and cameras

The default Stage world uses root-local coordinates:

```dart
final physics = stage.arcade;
```

A game/container can own a different physics space:

```dart
final physics = stage.arcade.inSpace(gameWorld);
```

Bound nodes may live deeper inside that space; Arcade uses GraphX's allocation-aware node-space conversion rather than requiring direct children.

Camera or container transforms therefore remain presentation concerns. Physics coordinates do not change when the rendered world is panned, zoomed, rotated or shaken.

## Headless simulation

A world does not require a Stage:

```dart
final world = GArcadeWorld(
  gravityY: 900,
  fixedStep: 1 / 120,
);

final body = world.createCircle(
  radius: 8,
  x: 100,
  y: 80,
);

world.step();
```

Use `createBody`, `createCircle` and `createBox` when no GraphX node is involved.

## Performance shape

The public `GBody` is a stable handle. Hot simulation state is retained in packed typed storage for positions, velocities, flags, shapes and filtering.

The broad phase retains its sweep order between steps and insertion-sorts moved bodies, so coherent arcade motion approaches linear ordering work instead of sorting from scratch every frame.

The steady-state design avoids transient geometry allocation during integration, broad phase, narrow phase and ordinary contact maintenance.

Performance claims beyond that architectural shape should come from package benchmarks rather than assumptions.

## Migration reference

The original Satechi package was exercised by focused Labs for gravity/bounce,
kinematic pointer paddles, and fast-ball CCD. Those scenarios remain useful
behavior references for this GraphX port.

## Acceptance games

The Satechi playground games were architecture pressure tests rather than a
separate game framework, and remain useful GraphX acceptance cases:

- **Breakout** exercises high restitution, fast-ball CCD, paddle kinematics, contact-driven destruction and rapid body churn.
- **Platformer** exercises gravity, grounded/contact state, moving kinematic platforms, sensors and camera/world-space composition.
- **Asteroids** exercises many dynamic bodies, collision filtering, bullet/sensor CCD, deterministic spawn/despawn churn and world wrapping in game rules rather than physics.
- **Pinball** exercises thin obstacles, repeated high-energy contacts, sensors, multiball and authored moving/rotating presentation without adding angular rigid-body physics.

Pinball is also a useful negative result. Its flippers are currently normal rotating GraphX visuals backed by short chains of authored kinematic circle bodies. That composition works with the existing contract and makes its cost visible: extra broad-phase/contact pairs, possible seams between circles and additional CCD impacts. Arcade should gain an authored kinematic segment/capsule only if this or another real workload proves those costs material; the acceptance game is not justification for speculative joints, torque or a general rigid-body model.

## Current scope

The package intentionally owns:

- fixed-step Stage/headless stepping and per-step lifecycle hooks;
- dynamic / kinematic / static bodies;
- circles and axis-aligned boxes;
- gravity and velocity;
- restitution;
- collision layers / masks;
- sensors;
- begin/end contacts;
- continuous fast-circle collision;
- node binding / disposal;
- manual control / teleport;
- simple point hit testing.

It deliberately does not add joints, arbitrary polygons, SAT, rotating rigid bodies, constraint graphs, an ECS/component system or physics concepts to GraphX core.
