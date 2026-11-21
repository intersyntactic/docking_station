// The program builds with the modules it pins. Importing it makes `dart test`
// compile every module it uses, which `dart analyze` never does: a module
// pinned against an older is_admission_vocabulary fails here, not at deploy.
import 'package:test/test.dart';

import '../bin/docking_station.dart' as docking_station;

void main() {
  test('the program builds with the modules it pins', () {
    expect(docking_station.main, isA<Function>());
  });
}
