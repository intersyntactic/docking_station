// The airlock is the trusted base, and imports path_start.dart so that what
// strangers sent is never decoded in it.
// That holds only while nothing path_start.dart reaches, in this package or
// any other, imports the packages that decode it. This walks the whole
// graph, so it is a check and not a hope.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// The packages path_start.dart may reach: this one, the three it names,
/// and what they import. checked_json is trusted: it decodes JSON text and
/// reads fields, and decodes no shape a stranger defined.
const _allowed = {
  'checked_json',
  'is_docking_station_api',
  'is_shapes',
  'is_content_id',
  'is_conversation_vocabulary',
  'is_web_address_vocabulary',
};

/// is_conversation_vocabulary also holds what people said, decoded from
/// what strangers sent; path_start.dart may reach only its reply endpoint.
const _allowedConversationVocabularyFiles = {
  'reply_endpoint.dart',
  'reply_endpoint_case.dart',
  'strict_object_reader.dart',
};

/// The files of this package path_start.dart may reach: itself, and the
/// translated event's case names, which import nothing.
const _allowedOwnFiles = {'path_start.dart', 'translated_event_case.dart'};

final _directive = RegExp(
  r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

void main() {
  test('path_start.dart reaches no package that decodes what strangers '
      'sent', () {
    final config = jsonDecode(
      File('.dart_tool/package_config.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final configUri = File('.dart_tool/package_config.json').absolute.uri;
    final libs = {
      for (final p in (config['packages'] as List).cast<Map<String, Object?>>())
        // A root has no trailing `/`, so resolving against it as it is
        // would drop its last segment.
        p['name'] as String: configUri
            .resolve('${p['rootUri']}/')
            .resolve('${p['packageUri'] ?? 'lib/'}'),
    };

    Uri resolve(Uri from, String target) {
      final uri = Uri.parse(target);
      if (uri.scheme != 'package') return from.resolveUri(uri);
      final [name, ...rest] = uri.pathSegments;
      return libs[name]!.resolve(rest.join('/'));
    }

    String? packageOf(Uri file) {
      for (final MapEntry(key: name, value: lib) in libs.entries) {
        if (file.toString().startsWith(lib.toString())) return name;
      }
      return null;
    }

    final start = libs['is_docking_station_api']!.resolve('path_start.dart');
    final seen = <Uri>{};
    final reached = <String>{};
    final todo = [start];
    while (todo.isNotEmpty) {
      final file = todo.removeLast();
      if (!seen.add(file)) continue;
      reached.add(packageOf(file) ?? '$file');
      final source = File.fromUri(file).readAsStringSync();
      for (final match in _directive.allMatches(source)) {
        final target = match[1]!;
        if (target.startsWith('dart:')) continue;
        todo.add(resolve(file, target));
      }
    }

    expect(reached.difference(_allowed), isEmpty, reason: '$reached');
    // And within this package, only path_start and the case names.
    final own = seen
        .where((f) => packageOf(f) == 'is_docking_station_api')
        .map((f) => f.pathSegments.last)
        .toSet();
    expect(own.difference(_allowedOwnFiles), isEmpty, reason: '$own');
    final conversation = seen
        .where((f) => packageOf(f) == 'is_conversation_vocabulary')
        .map((f) => f.pathSegments.last)
        .toSet();
    expect(
      conversation.difference(_allowedConversationVocabularyFiles),
      isEmpty,
      reason: '$conversation',
    );
  });
}
