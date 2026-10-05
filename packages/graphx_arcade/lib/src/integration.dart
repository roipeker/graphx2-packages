part of 'package:graphx_arcade/graphx_arcade.dart';

extension GStageArcadeExtension on GStage {
  /// Lazily creates the Stage-local default Arcade world in root space.
  GArcadeWorld get arcade {
    final existing = _arcadeByStage[this];
    if (existing != null && !existing.isDisposed) return existing;
    final world = GArcadeWorld.stage(this);
    _arcadeByStage[this] = world;
    return world;
  }
}

extension GArcadeWorldSpaceExtension on GArcadeWorld {
  /// Returns a lazy sibling world whose coordinates are local to [space].
  ///
  /// Camera/container transforms can then move the rendered world without
  /// changing physics coordinates:
  ///
  /// ```dart
  /// final physics = stage.arcade.inSpace(gameWorld);
  /// ```
  GArcadeWorld inSpace(GNode space) {
    _checkAlive();
    final stage = _stage;
    if (stage == null) {
      throw StateError('Headless Arcade worlds do not have GraphX node spaces.');
    }
    if (identical(space, _space)) return this;

    final existing = _arcadeBySpace[space];
    if (existing != null &&
        !existing.isDisposed &&
        identical(existing.stage, stage) &&
        identical(existing.space, space)) {
      return existing;
    }

    final result = GArcadeWorld.stage(
      stage,
      space: space,
      gravityX: gravityX,
      gravityY: gravityY,
      fixedStep: fixedStep,
      maxSubSteps: maxSubSteps,
      interpolate: interpolate,
    );
    _arcadeBySpace[space] = result;
    return result;
  }
}

extension GNodeArcadeExtension on GNode {
  /// The live Arcade body currently bound to this node, if any.
  GBody? get body {
    final value = _bodyByNode[this];
    return value != null && value.isAlive && identical(value.node, this) ? value : null;
  }
}
