// A relayed event's source is its entry's kind, never its body: the
// logbook's sender table lets one user write each kind, so that is what
// vouches for where an event came from. This holds the kind and the body to
// that.
import 'dart:convert';
import 'dart:typed_data';

import 'package:is_docking_station_api/is_docking_station_api.dart';
import 'package:is_logbook_format/is_logbook_format.dart' show Kind, ObjectId;
import 'package:test/test.dart';

final _entry = ObjectId.parse('a' * 64)!;
final _teams = RelayedEventSource.parse('teams')!;
final _at = DateTime.utc(2026, 11, 23, 9, 50);
final _bytes = Uint8List.fromList(utf8.encode('{"type":"message"}'));

Uint8List _body(Map<String, Object?> json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

void main() {
  test('a source records its events as <source>-event', () {
    expect(_teams.kind, Kind.parse('teams-event'));
    expect(RelayedEventSource.ofKind(Kind.parse('teams-event')!), _teams);
    expect(
      RelayedEventSource.ofKind(Kind.parse('slack-event')!),
      RelayedEventSource.parse('slack'),
    );
  });

  test('a kind that is no relay\'s names no source', () {
    for (final name in [
      'event',
      'arrived',
      '-event',
      'Teams-event',
      'event-admitted-to-mission',
      'trajectory-closed',
    ]) {
      expect(
        RelayedEventSource.ofKind(Kind.parse(name)!),
        isNull,
        reason: name,
      );
    }
    for (final s in ['', 'Teams', '1teams', 'teams event', 'teams:x']) {
      expect(RelayedEventSource.parse(s), isNull, reason: s);
    }
  });

  test(
    'what a relay writes reads back as itself, its source from its kind',
    () {
      final (kind, body) = encodeRelayedEvent(_teams, at: _at, bytes: _bytes);
      expect(kind, Kind.parse('teams-event'));
      expect(jsonDecode(utf8.decode(body)), {
        'at': '2026-11-23T09:50:00.000Z',
        'bytes': base64Encode(_bytes),
      });
      final event = RelayedEvent.read(_entry, kind, body)!;
      expect(event.entry, _entry);
      expect(event.source, _teams);
      expect(event.at, _at);
      expect(event.bytes, _bytes);
    },
  );

  test('a body naming its own source is refused, whatever it names', () {
    final good = {'at': _at.toIso8601String(), 'bytes': base64Encode(_bytes)};
    for (final json in [
      {...good, 'source': 'teams'},
      {...good, 'source': 'slack'},
      {...good}..remove('at'),
      {...good}..remove('bytes'),
      {...good, 'at': 'yesterday'},
      {...good, 'bytes': '!!'},
    ]) {
      expect(
        RelayedEvent.read(_entry, _teams.kind, _body(json)),
        isNull,
        reason: '$json',
      );
    }
    expect(RelayedEvent.read(_entry, _teams.kind, _body(good)), isNotNull);
    expect(
      RelayedEvent.read(_entry, Kind.parse('event')!, _body(good)),
      isNull,
    );
  });
}
