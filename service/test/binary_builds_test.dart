// The programs build with the modules they pin. Importing them makes `dart
// test` compile every module they use, which `dart analyze` never does: a
// module pinned against an older is_admission_vocabulary fails here, not at
// deploy.
import 'package:test/test.dart';

import '../bin/close_trajectory.dart' as close_trajectory;
import '../bin/docking_station.dart' as docking_station;

void main() {
  test('the programs build with the modules they pin', () {
    expect(docking_station.main, isA<Function>());
    expect(close_trajectory.main, isA<Function>());
  });
}
