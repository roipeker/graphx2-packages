/// Data-oriented retained particle systems for GraphX.
///
/// Emitters own fixed-capacity packed simulation data. Optional high-volume
/// features such as fields, constraints, secondary emission, line trails and
/// ribbon trails stay retained at emitter/system level; individual particles
/// remain dense numeric slots rather than scene or behavior objects.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:graphx/graphx.dart';
import 'package:graphx/graphx_debug.dart' show getTimerMicros;
import 'package:graphx_paths/graphx_paths.dart';

import 'src/particle_field.dart';
import 'src/particle_random.dart';
import 'src/particle_store.dart';
import 'src/particle_trail_store.dart';

export 'src/particle_field.dart';

part 'src/blend.dart';
part 'src/config.dart';
part 'src/constraints.dart';
part 'src/emitter.dart';
part 'src/fields.dart';
part 'src/prewarm.dart';
part 'src/secondary.dart';
part 'src/trails.dart';
