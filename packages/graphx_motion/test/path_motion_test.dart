import 'package:flutter_test/flutter_test.dart';
import 'package:graphx/graphx.dart';
import 'package:graphx_motion/graphx_motion.dart';
import 'package:graphx_paths/graphx_paths.dart';

void main() {
  test('path follower exposes stable reusable progress property', () {
    final path = GPath();
    path.moveTo(0, 0);
    path.lineTo(100, 0);
    final node = GNode();
    final follower = GPathFollower(path, target: node);
    final property = follower.motionProgress;

    expect(identical(property, follower.motionProgress), isTrue);

    property.set(.75);
    expect(follower.progress, .75);
    expect(node.x, closeTo(75, 1e-9));
    expect(node.y, closeTo(0, 1e-9));

    property.set(.25);
    expect(follower.progress, .25);
    expect(node.x, closeTo(25, 1e-9));
  });
}
