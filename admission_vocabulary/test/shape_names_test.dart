// A node's `shape` is one namespace across every package whose nodes travel
// in map form, so two packages naming two shapes alike would make one
// node read as the other. The docking station decodes nodes from several
// packages, so it checks (Nick, 16 Nov). Kept: it guards a wire contract
// across packages, which nothing else checks.
import 'package:is_admission_vocabulary/is_admission_vocabulary.dart';
import 'package:test/test.dart';

void main() {
  test('no two node shapes a reading carries share a name', () {
    final seen = <String, String>{};
    final clashes = <String>[];
    for (final MapEntry(key: field, value: shapes)
        in readingNodeShapes.entries) {
      for (final shape in shapes) {
        if (seen[shape] case final other?) {
          clashes.add('$shape: in `$other` and `$field`');
        }
        seen[shape] = field;
      }
    }
    expect(clashes, isEmpty);
    expect(seen, isNotEmpty);
  });
}
