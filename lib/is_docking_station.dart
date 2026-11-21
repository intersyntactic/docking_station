/// The docking station's engine: [decide], which decides one event under the
/// rules passed in; [DecidedSoFar], what the decisions add up to when read
/// back; and [runDockingStation], which subscribes to the record and sends
/// each decision to it. It re-exports is_admission_vocabulary, the readings
/// and decisions other repos import, until the engine moves into the service.
library;

export 'package:is_admission_vocabulary/is_admission_vocabulary.dart';

export 'src/decide.dart';
export 'src/decided.dart';
export 'src/rules.dart';
export 'src/run.dart';
