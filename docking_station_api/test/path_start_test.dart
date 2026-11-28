// readTrajectoryStart reads the `event-admitted-to-mission` wire on its own,
// apart from decodeDecision, so the airlock never decodes a translated event.
// Two readers of one wire can drift apart: this holds them together over every
// admitted case the docking station writes, and holds the narrow reader as
// strict as the full one everywhere outside `translatedEvent`.
import 'dart:convert';
import 'dart:typed_data';

import 'package:checked_json/checked_json.dart' show JsonObject;
import 'package:is_conversation_vocabulary/is_conversation_vocabulary.dart'
    show
        PinnedBodyFields,
        ReplyEndpoint,
        RepliesWithPinnedBodyFields,
        encodeReplyEndpoint;
import 'package:is_docking_station_api/is_docking_station_api.dart';
import 'package:is_docking_station_api/path_start.dart';
import 'package:is_shapes/is_shapes.dart'
    show DecidedBy, MissionId, TrajectoryId;
import 'package:is_web_address_vocabulary/is_web_address_vocabulary.dart'
    show Origin, WebPath;
import 'package:test/test.dart';

import 'decision_wire_test.dart' show event, translatedEvents, rules, said;

final _b = 'b' * 64, _c = 'c' * 64;

/// [decision] as the logbook holds it: the header its ids are hashed with,
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
      AdmissibleEvent translatedEvent,
      AdmittedPlacement placement, {
      bool startsTurn = true,
    }) => EventAdmittedToMission(
      event,
      by: DecidedBy.person,
      translatedEvent: translatedEvent,
      placement: placement,
      rules: EventAdmittedToMission.starts(placement) ? rules : null,
      startsTurn: translatedEvent is MessageSaid ? startsTurn : null,
    );
    final decisions = [
      for (final translatedEvent in translatedEvents)
        if (translatedEvent is ActorsJoinedAddress) ...[
          admitted(translatedEvent, IntoMission(InMission(mission))),
          admitted(translatedEvent, const IntoMission(StartsMission())),
        ] else
          admitted(translatedEvent, OnTrajectory(trajectory)),
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
          expect(starts.replyEndpoint, full.replyEndpoint);
          expect(starts.replyEndpoint, isNotNull);
        case _:
          expect(
            narrow,
            isA<EntryStartsNoTrajectory<JsonObject>>(),
            reason: '$full',
          );
      }
    }
  });

  EventAdmittedToMission startsWith(ReplyEndpoint endpoint) =>
      EventAdmittedToMission(
        event,
        by: DecidedBy.rules,
        translatedEvent: MessageSaid(
          addressInExternalSystem: said.addressInExternalSystem,
          containingAddress: said.containingAddress,
          addressedTo: said.addressedTo,
          replyEndpoint: endpoint,
          key: said.key,
          node: said.node,
          conversationKind: said.conversationKind,
        ),
        placement: const StartsTrajectory(StartsMission()),
        rules: rules,
        startsTurn: true,
      );

  RepliesWithPinnedBodyFields pinned(
    String origin,
    String path,
    Map<String, String> fields, {
    Set<String> mustBeAbsent = const {},
  }) => RepliesWithPinnedBodyFields.at(
    origin: Origin.parse(origin)!,
    path: WebPath.parse(path)!,
    pinned: PinnedBodyFields.of(fields, mustBeAbsent: mustBeAbsent)!,
  )!;

  test('reads an endpoint with pinned body fields as decodeDecision does', () {
    for (final endpoint in [
      pinned('https://graph.facebook.com', '/v27.0/106540352242922/messages', {
        'messaging_product': 'whatsapp',
        'recipient_type': 'individual',
        'to': '61400000000',
      }),
      pinned('https://slack.com', '/api/chat.postMessage', {
        'channel': 'C0123ABCD',
        'thread_ts': '1700000000.000100',
      }),
    ]) {
      final decision = startsWith(endpoint);
      final full =
          decodeDecision(
                DecisionEntryKind.eventAdmittedToMission,
                encodeDecision(decision).$2,
              )!
              as EventAdmittedToMission;
      final narrow = _read(_entry(decision)) as EntryStartsTrajectory;
      expect(full.replyEndpoint, endpoint);
      expect(narrow.replyEndpoint, endpoint);
    }
  });

  test('a decision recorded with a Slack endpoint as 0.9 wrote it still '
      'reads, in both readers, as its pinned fields', () {
    // The endpoint exactly as is_conversation_vocabulary 0.1 wrote it, in
    // both places an admission carries it, threaded and not. The service
    // replays its own decisions at start and stops on one it can't read.
    final cases = <Map<String, Object?>, RepliesWithPinnedBodyFields>{
      {
        'case': 'in-slack-conversation',
        'origin': 'https://slack.com',
        'channel': 'C0123ABCD',
        'thread': '1700000000.000100',
      }: pinned('https://slack.com', '/api/chat.postMessage', {
        'channel': 'C0123ABCD',
        'thread_ts': '1700000000.000100',
      }),
      // Sent at the conversation's top level, so a reply may not pick a
      // thread.
      {
        'case': 'in-slack-conversation',
        'origin': 'https://slack.com',
        'channel': 'D0123ABCD',
      }: pinned(
        'https://slack.com',
        '/api/chat.postMessage',
        {'channel': 'D0123ABCD'},
        mustBeAbsent: {'thread_ts'},
      ),
    };
    final written = startsWith(
      pinned('https://slack.com', '/api/chat.postMessage', {'channel': 'x'}),
    );
    for (final MapEntry(key: asFirstWritten, value: meant) in cases.entries) {
      final json = jsonDecode(utf8.decode(encodeDecision(written).$2));
      if (json case {
        'translatedEvent': final Map<String, Object?> translatedEvent,
      }) {
        translatedEvent['replyEndpoint'] = asFirstWritten;
      }
      if (json case final Map<String, Object?> top) {
        top['replyEndpoint'] = asFirstWritten;
      }
      final body = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      final full = decodeDecision(
        DecisionEntryKind.eventAdmittedToMission,
        body,
      ) as EventAdmittedToMission?;
      expect(full?.replyEndpoint, meant);
      final entry = Uint8List.fromList([
        ...utf8.encode('${DecisionEntryKind.eventAdmittedToMission}\n-\n'),
        ...body,
      ]);
      expect((_read(entry) as EntryStartsTrajectory).replyEndpoint, meant);
      // Written back, it takes the new form.
      expect(
        encodeReplyEndpoint(full!.replyEndpoint!).raw('case'),
        'with-pinned-body-fields',
      );
    }
  });

  test('a trajectory is named by the whole entry, header included', () {
    final decision = EventAdmittedToMission(
      event,
      by: DecidedBy.rules,
      translatedEvent: said,
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
      'translatedEvent': {'case': 'message-said', 'node': 'never decoded'},
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
      _raw('event-admitted-to-mission', {
        ...good,
        'translatedEvent': 'message-said',
      }),
      _raw('event-admitted-to-mission', {
        ...good,
        'translatedEvent': <String, Object?>{},
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
        'translatedEvent': {'case': 'actors-joined-address'},
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
