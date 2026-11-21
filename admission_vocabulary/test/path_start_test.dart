// readTrajectoryStart reads the `event-admitted-to-mission` wire on its own,
// apart from decodeDecision, so the airlock never decodes a reading. Two
// readers of one wire can drift apart: this holds them together over every
// admitted case the docking station writes, and holds the narrow reader as
// strict as the full one everywhere outside `reading`.
import 'dart:convert';
import 'dart:typed_data';

import 'package:checked_json/checked_json.dart' show JsonObject;
import 'package:is_admission_vocabulary/is_admission_vocabulary.dart';
import 'package:is_admission_vocabulary/path_start.dart';
import 'package:is_shapes/is_shapes.dart'
    show DecidedBy, MissionId, TrajectoryId;
import 'package:test/test.dart';

import 'decision_wire_test.dart' show event, readings, rules, said;

final _b = 'b' * 64, _c = 'c' * 64;

/// [decision] as the record holds it: the header its ids are hashed with,
/// then its body.
Uint8List _entry(AdmissionDecision decision, {String previous = '-'}) {
  final (kind, body) = encodeDecision(decision);
  return Uint8List.fromList([...utf8.encode('$kind\n$previous\n'), ...body]);
}

Uint8List _raw(String kind, Map<String, Object?> json) =>
    Uint8List.fromList(utf8.encode('$kind\n-\n${jsonEncode(json)}'));

AdmittedTrajectoryEntry<JsonObject> _read(Uint8List entry) =>
    readTrajectoryStart(entry, rules: JsonObject.parse);

void main() {
  test('agrees with decodeDecision on every admitted case', () {
    final mission = MissionId.parse(_b)!;
    final trajectory = TrajectoryId.parse(_c)!;
    EventAdmittedToMission admitted(
      AdmissibleEvent reading,
      AdmittedPlacement placement, {
      bool startsTurn = true,
    }) => EventAdmittedToMission(
      event,
      by: DecidedBy.person,
      reading: reading,
      placement: placement,
      rules: EventAdmittedToMission.starts(placement) ? rules : null,
      startsTurn: reading is MessageSaid ? startsTurn : null,
    );
    final decisions = [
      for (final reading in readings)
        if (reading is ActorsJoinedAddress) ...[
          admitted(reading, IntoMission(InMission(mission))),
          admitted(reading, const IntoMission(StartsMission())),
        ] else
          admitted(reading, OnTrajectory(trajectory)),
      admitted(said, OnTrajectory(trajectory), startsTurn: false),
      admitted(said, StartsTrajectory(InMission(mission))),
      admitted(said, const StartsTrajectory(StartsMission())),
    ];
    for (final decision in decisions) {
      final entry = _entry(decision);
      final full = decodeDecision(
        DecisionEntryKind.eventAdmittedToMission,
        encodeDecision(decision).$2,
      )!;
      final narrow = _read(entry);
      switch ((full as EventAdmittedToMission).placement) {
        case StartsTrajectory(mission: final placement):
          final starts = narrow as EntryStartsTrajectory<JsonObject>;
          expect(starts.event, full.event);
          expect(starts.by, full.by);
          expect(starts.trajectory, TrajectoryId.of(entry));
          expect(starts.mission, switch (placement) {
            InMission(:final mission) => mission,
            StartsMission() => MissionId.of(entry),
          });
          expect(starts.rules.asUncheckedMap(), full.rules!.asUncheckedMap());
        case _:
          expect(
            narrow,
            isA<EntryStartsNoTrajectory<JsonObject>>(),
            reason: '$full',
          );
      }
    }
  });

  test('a trajectory is named by the whole entry, header included', () {
    final decision = EventAdmittedToMission(
      event,
      by: DecidedBy.rules,
      reading: said,
      placement: const StartsTrajectory(StartsMission()),
      rules: rules,
      startsTurn: true,
    );
    final a = _read(_entry(decision)) as EntryStartsTrajectory;
    final b = _read(_entry(decision, previous: _b)) as EntryStartsTrajectory;
    expect(a.trajectory, isNot(b.trajectory));
  });

  test('anything else is unreadable, never no trajectory', () {
    final good = {
      'event': 'a' * 64,
      'by': 'rules',
      'reading': {'case': 'message-said', 'node': 'never decoded'},
      'startsTrajectory': true,
      'startsMission': true,
      'rules': {'tools': 'all'},
      'startsTurn': true,
    };
    expect(
      _read(_raw('event-admitted-to-mission', good)),
      isA<EntryStartsTrajectory<JsonObject>>(),
    );
    final under = {...good, 'trajectory': _c}
      ..remove('startsTrajectory')
      ..remove('startsMission')
      ..remove('rules');
    expect(
      _read(_raw('event-admitted-to-mission', under)),
      isA<EntryStartsNoTrajectory<JsonObject>>(),
    );

    final bad = <Uint8List>[
      Uint8List.fromList(utf8.encode('event-admitted-to-mission')),
      _raw('event-not-admitted-to-mission', good),
      _raw('event-admitted-to-mission', {...good, 'extra': 1}),
      _raw('event-admitted-to-mission', {...good, 'event': 'x'}),
      _raw('event-admitted-to-mission', {...good, 'by': 'nobody'}),
      _raw('event-admitted-to-mission', {...good, 'reading': 'message-said'}),
      _raw('event-admitted-to-mission', {
        ...good,
        'reading': <String, Object?>{},
      }),
      _raw('event-admitted-to-mission', {...good}..remove('rules')),
      _raw('event-admitted-to-mission', {...good, 'rules': 'all'}),
      _raw('event-admitted-to-mission', {
        ...under,
        'rules': {'tools': 'all'},
      }),
      _raw('event-admitted-to-mission', {...good}..remove('startsTurn')),
      _raw('event-admitted-to-mission', {...good, 'startsTurn': 'yes'}),
      _raw('event-admitted-to-mission', {...good, 'startsTurn': false}),
      _raw('event-admitted-to-mission', {
        ...good,
        'reading': {'case': 'actors-joined-address'},
      }),
      _raw('event-admitted-to-mission', {...good, 'mission': _b}),
      _raw('event-admitted-to-mission', {...good, 'startsTrajectory': 1}),
      _raw('event-admitted-to-mission', {...under, 'trajectory': 'x'}),
      Uint8List.fromList([
        ...utf8.encode('event-admitted-to-mission\n-\n'),
        0xff,
      ]),
    ];
    for (final entry in bad) {
      expect(
        _read(entry),
        isA<UnreadableTrajectoryEntry<JsonObject>>(),
        reason: utf8.decode(entry, allowMalformed: true),
      );
    }
  });
}
