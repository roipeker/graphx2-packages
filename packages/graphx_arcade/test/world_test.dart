import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx.dart';
import 'package:graphx_arcade/graphx_arcade.dart';

void main() {
  group('GArcadeWorld', () {
    test('headless fixed step integrates gravity deterministically', () {
      final world = GArcadeWorld(
        gravityY: 60,
        fixedStep: 1 / 60,
        interpolate: false,
      );
      final body = world.createCircle(
        radius: 4,
        x: 0,
        y: 0,
      );

      world.step();

      expect(body.velocityY, closeTo(1, 1e-12));
      expect(body.y, closeTo(1 / 60, 1e-12));
      world.dispose();
    });

    test('continuous circle cannot tunnel through a thin static box', () {
      final world = GArcadeWorld(
        fixedStep: .25,
        interpolate: false,
      );
      final wall = world.createBox(
        width: 2,
        height: 100,
        x: 20,
        y: 0,
        type: GBodyType.static,
        bounce: 1,
      );
      final ball = world.createCircle(
        radius: 2,
        x: 0,
        y: 0,
        bounce: 1,
        continuous: true,
      );
      ball.velocityX = 100;

      var begins = 0;
      ball.onContactBegin.add((contact) {
        begins++;
        expect(contact.other, same(wall));
        expect(contact.normalX, greaterThan(0));
        expect(
          ball.velocityX,
          lessThan(0),
          reason: 'begin callbacks run after collision response',
        );
      });

      world.step(.25);

      expect(begins, 1);
      expect(ball.velocityX, lessThan(0));
      expect(ball.x, lessThan(20));
      world.dispose();
    });

    test(
      'contact callback may override response and destroy other body safely',
      () {
        final world = GArcadeWorld(
          fixedStep: .25,
          interpolate: false,
        );
        final wall = world.createBox(
          width: 2,
          height: 100,
          x: 20,
          y: 0,
          type: GBodyType.static,
          bounce: 1,
        );
        final ball = world.createCircle(
          radius: 2,
          x: 0,
          y: 0,
          bounce: 1,
          continuous: true,
        );
        ball.velocityX = 100;

        ball.onContactBegin.add((contact) {
          expect(ball.velocityX, lessThan(0));
          ball.velocityX = -37;
          contact.other.destroy();
        });

        world.step(.25);

        expect(ball.velocityX, -37);
        expect(wall.isAlive, isFalse);
        expect(world.bodyCount, 1);
        world.dispose();
      },
    );

    test('sensor contacts begin and end without changing velocity', () {
      final world = GArcadeWorld(
        fixedStep: .25,
        interpolate: false,
      );
      final sensor = world.createBox(
        width: 10,
        height: 20,
        x: 10,
        y: 0,
        type: GBodyType.static,
        sensor: true,
      );
      final body = world.createCircle(
        radius: 2,
        x: 0,
        y: 0,
      );
      body.velocityX = 20;

      var begins = 0;
      var ends = 0;
      body.onContactBegin.add((contact) {
        begins++;
        expect(contact.other, same(sensor));
        expect(contact.isSensor, isTrue);
      });
      body.onContactEnd.add((contact) {
        ends++;
        expect(contact.other, same(sensor));
      });

      world.step(.25);
      expect(begins, 1);
      expect(body.velocityX, 20);

      world.step(.75);
      expect(ends, 1);
      expect(body.velocityX, 20);
      world.dispose();
    });

    test('Stage world runs in postUpdate and node disposal destroys body', () {
      final root = GRoot();
      final node = root.addChild(GNode(name: 'actor'));
      node.setPosition(10, 20);
      final stage = GStage(root);
      stage.mount();
      stage.setViewport(320, 240);
      final world = stage.arcade;
      world.fixedStep = 1 / 60;
      world.interpolate = false;
      final body = world.circle(node, radius: 5);
      body.velocityX = 60;

      stage.tick(1 / 60);

      expect(body.x, closeTo(11, 1e-12));
      expect(node.x, closeTo(11, 1e-12));
      expect(node.body, same(body));

      node.dispose();

      expect(body.isAlive, isFalse);
      expect(node.body, isNull);
      expect(world.bodyCount, 0);
      stage.dispose();
    });

    test('kinematic node motion becomes physical velocity in same tick', () {
      final root = GRoot();
      final paddle = root.addChild(GNode(name: 'paddle'));
      paddle.setPosition(20, 40);
      final stage = GStage(root);
      stage.mount();
      stage.setViewport(320, 240);
      stage.maxDelta = .2;
      final world = stage.arcade;
      world.fixedStep = .1;
      world.interpolate = false;
      final body = world.box(
        paddle,
        width: 40,
        height: 10,
        type: GBodyType.kinematic,
      );

      paddle.x = 40;
      stage.tick(.1);

      expect(body.velocityX, closeTo(200, 1e-12));
      expect(body.x, closeTo(40, 1e-12));
      stage.dispose();
    });

    test(
      'kinematic authored movement survives a render frame without a substep',
      () {
        final root = GRoot();
        final paddle = root.addChild(GNode(name: 'paddle'));
        paddle.setPosition(20, 40);
        final stage = GStage(root);
        stage.mount();
        stage.setViewport(320, 240);
        final world = stage.arcade;
        world.fixedStep = .1;
        world.interpolate = false;
        final body = world.box(
          paddle,
          width: 40,
          height: 10,
          type: GBodyType.kinematic,
        );

        paddle.x = 30;
        stage.tick(.05);
        expect(body.x, closeTo(20, 1e-12));

        // The authored node stops before the next render frame. The pending
        // displacement still belongs to the next fixed simulation step.
        stage.tick(.05);

        expect(body.x, closeTo(30, 1e-12));
        expect(body.velocityX, closeTo(100, 1e-12));
        stage.dispose();
      },
    );

    test('nested bindings resolve through explicit world space', () {
      final root = GRoot();
      final space = root.addChild(GNode(name: 'world'));
      space.setPosition(30, 20);
      final group = space.addChild(GNode(name: 'group'));
      group.setPosition(100, 50);
      final actor = group.addChild(GNode(name: 'actor'));
      actor.setPosition(10, 5);
      final stage = GStage(root);
      stage.mount();
      stage.setViewport(640, 480);
      final world = stage.arcade.inSpace(space);
      world.fixedStep = 1 / 60;
      world.interpolate = false;
      final body = world.circle(actor, radius: 5);

      expect(body.x, closeTo(110, 1e-12));
      expect(body.y, closeTo(55, 1e-12));

      body.teleport(150, 80);

      expect(actor.x, closeTo(50, 1e-12));
      expect(actor.y, closeTo(30, 1e-12));
      stage.dispose();
    });

    test('takeControl hands a dynamic body to authored node motion', () {
      final root = GRoot();
      final node = root.addChild(GNode(name: 'dragged'));
      node.setPosition(10, 10);
      final stage = GStage(root);
      stage.mount();
      stage.setViewport(320, 240);
      stage.maxDelta = .2;
      final world = stage.arcade;
      world.fixedStep = .1;
      world.interpolate = false;
      final body = world.circle(node, radius: 5);
      body.velocityX = 50;
      final control = body.takeControl();

      control.moveTo(60, 25);
      stage.tick(.1);

      expect(body.x, closeTo(60, 1e-12));
      expect(body.y, closeTo(25, 1e-12));

      control.release(velocityX: 120, velocityY: -30);
      expect(body.velocityX, 120);
      expect(body.velocityY, -30);

      stage.tick(.1);
      expect(body.x, closeTo(72, 1e-12));
      expect(body.y, closeTo(22, 1e-12));
      stage.dispose();
    });

    test('retained contact view stays current while grounded', () {
      final world = GArcadeWorld(
        gravityY: 60,
        fixedStep: 1 / 60,
        interpolate: false,
      );
      final floor = world.createBox(
        width: 100,
        height: 10,
        x: 0,
        y: 20,
        type: GBodyType.static,
      );
      final player = world.createBox(
        width: 10,
        height: 10,
        x: 0,
        y: 10.1,
      );

      GBodyContact? support;
      var begins = 0;
      var ends = 0;
      player.onContactBegin.add((contact) {
        begins++;
        support = contact;
      });
      player.onContactEnd.add((contact) {
        ends++;
        expect(contact, same(support));
      });

      world.step();

      expect(begins, 1);
      expect(support, isNotNull);
      expect(support!.other, same(floor));
      expect(support!.normalY, greaterThan(.9));

      world.step();
      expect(begins, 1);
      expect(support!.normalY, greaterThan(.9));

      player.velocityY = -60;
      world.step();

      expect(ends, 1);
      world.dispose();
    });

    test('node-authored kinematic lift pushes a dynamic rider', () {
      final root = GRoot();
      final lift = root.addChild(GNode(name: 'lift'));
      lift.setPosition(0, 20);
      final rider = root.addChild(GNode(name: 'rider'));
      rider.setPosition(0, 10);
      final stage = GStage(root);
      stage.mount();
      stage.setViewport(320, 240);
      stage.maxDelta = .2;
      final world = stage.arcade;
      world.fixedStep = .1;
      world.interpolate = false;
      final liftBody = world.box(
        lift,
        width: 100,
        height: 10,
        type: GBodyType.kinematic,
      );
      final riderBody = world.box(
        rider,
        width: 10,
        height: 10,
      );

      lift.y = 15;
      stage.tick(.1);

      expect(liftBody.velocityY, closeTo(-50, 1e-12));
      expect(riderBody.velocityY, closeTo(-50, 1e-12));
      expect(riderBody.y, closeTo(5, 1e-6));
      stage.dispose();
    });

    test('fixed-step advance is invariant to render-frame partitioning', () {
      final a = GArcadeWorld(
        gravityY: 900,
        fixedStep: 1 / 120,
        maxSubSteps: 8,
        interpolate: false,
      );
      final b = GArcadeWorld(
        gravityY: 900,
        fixedStep: 1 / 120,
        maxSubSteps: 8,
        interpolate: false,
      );
      final bodyA = a.createBox(width: 10, height: 10);
      final bodyB = b.createBox(width: 10, height: 10);

      a.advance(1 / 30);
      b.advance(1 / 60);
      b.advance(1 / 60);

      expect(bodyA.x, closeTo(bodyB.x, 1e-12));
      expect(bodyA.y, closeTo(bodyB.y, 1e-12));
      expect(bodyA.velocityY, closeTo(bodyB.velocityY, 1e-12));
      a.dispose();
      b.dispose();
    });

    test('fixed-step hooks run once per substep and can author simulation', () {
      final world = GArcadeWorld(
        fixedStep: .1,
        maxSubSteps: 8,
        interpolate: false,
      );
      final body = world.createCircle(radius: 2);
      final phases = <String>[];

      world.onBeforeStep.add((dt) {
        expect(dt, .1);
        phases.add('before');
        body.velocityX += 10;
      });
      world.onAfterStep.add((dt) {
        expect(dt, .1);
        phases.add('after');
      });

      world.advance(.31);

      expect(
        phases,
        <String>['before', 'after', 'before', 'after', 'before', 'after'],
      );
      expect(body.velocityX, closeTo(30, 1e-12));
      expect(body.x, closeTo(6, 1e-12));
      world.dispose();
    });

    test('fixed-step hooks reject recursive stepping', () {
      final world = GArcadeWorld(fixedStep: .1, interpolate: false);
      var calls = 0;

      world.onBeforeStep.add((_) {
        calls++;
        expect(world.step, throwsStateError);
      });

      world.step();

      expect(calls, 1);
      world.dispose();
    });

    test('continuous sensor circle sweeps a dynamic target without impulse', () {
      final world = GArcadeWorld(
        fixedStep: .25,
        interpolate: false,
      );
      final target = world.createCircle(
        radius: 2,
        x: 20,
        y: 0,
        layer: 1 << 1,
        mask: 1 << 0,
      );
      target.velocityY = 4;
      final bullet = world.createCircle(
        radius: 1,
        x: 0,
        y: 0,
        sensor: true,
        continuous: true,
        layer: 1 << 0,
        mask: 1 << 1,
      );
      bullet.velocityX = 100;

      var begins = 0;
      bullet.onContactBegin.add((contact) {
        begins++;
        expect(contact.other, same(target));
        expect(contact.isSensor, isTrue);
      });

      world.step(.25);

      expect(begins, 1);
      expect(bullet.velocityX, 100);
      expect(target.velocityX, 0);
      expect(target.velocityY, 4);
      expect(bullet.x, closeTo(25, 1e-5));
      expect(target.y, closeTo(1, 1e-12));
      world.dispose();
    });
  });
}
