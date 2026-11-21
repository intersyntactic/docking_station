// The decision entry is a wire contract: whatever reads the record reads
// these field names. So this is kept (RULINGS, "Tests prove once": the
// suite keeps wire contracts).
import 'dart:convert';
import 'dart:typed_data';

import 'package:checked_json/checked_json.dart' show JsonObject;
import 'package:is_annotation_shapes/is_annotation_shapes.dart'
    show ProposedCorrectionVerdict;
import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show Deleted, Edited, SourceMessageId, UserSaid;
import 'package:is_admission_vocabulary/is_admission_vocabulary.dart';
import 'package:is_logbook_client/is_logbook_client.dart' show Kind, ObjectId;
import 'package:is_shapes/is_shapes.dart'
    show ActorId, DecidedBy, MissionId, TrajectoryId;
import 'package:test/test.dart';

final _a = 'a' * 64, _b = 'b' * 64, _c = 'c' * 64;
final event = ObjectId.parse(_a)!;
final addressInExternalSystem = AddressInExternalSystem.parse(
  'teams:19:x;messageid=1',
)!;
final containingAddress = AddressInExternalSystem.parse('teams:19:x')!;
final key = EventKey.parse('message:1')!;
final from = ActorId.parse('teams:t/p')!;
final bot = ActorId.parse('teams:t/bot:app')!;
final message = SourceMessageId.parse('19:x;messageid=1|1')!;

final said = MessageSaid(
  addressInExternalSystem: addressInExternalSystem,
  containingAddress: containingAddress,
  addressedTo: bot,
  key: key,
  node: UserSaid(author: from, source: message, text: 'hi'),
);

/// One reading of each case, each reading back as itself.
final readings = <AdmissibleEvent>[
  said,
  MessageChanged(
    addressInExternalSystem: addressInExternalSystem,
    containingAddress: containingAddress,
    addressedTo: bot,
    from: from,
    key: key,
    message: message,
    change: const Edited(text: 'hello'),
  ),
  MessageChanged(
    addressInExternalSystem: addressInExternalSystem,
    containingAddress: null,
    addressedTo: null,
    from: null,
    key: key,
    message: message,
    change: const Deleted(),
  ),
  ActorsJoinedAddress.of(
    addressInExternalSystem: containingAddress,
    containingAddress: null,
    addressedTo: null,
    from: from,
    key: key,
    joiners: [from, ActorId.parse('teams:bot')!],
  )!,
  ShownMessageJudged(
    addressInExternalSystem: addressInExternalSystem,
    containingAddress: containingAddress,
    addressedTo: bot,
    from: from,
    key: key,
    to: message,
    verdict: ProposedCorrectionVerdict({'note': 'not yet'}),
  ),
];

final closeAsked = PersonAskedToCloseTrajectory(
  addressInExternalSystem: addressInExternalSystem,
  containingAddress: containingAddress,
  addressedTo: bot,
  from: from,
  key: EventKey.parse('invoke:1')!,
  message: message,
);

const rules = JsonObject.of({'tools': 'all'});

EventAdmittedToMission _admitted(AdmittedPlacement placement, DecidedBy by) =>
    EventAdmittedToMission(
      event,
      by: by,
      reading: said,
      placement: placement,
      rules: EventAdmittedToMission.starts(placement) ? rules : null,
      startsTurn: true,
    );

String _text((Kind, Uint8List) entry) => utf8.decode(entry.$2);

void main() {
  test('an admission that starts a mission and its first trajectory', () {
    final entry = encodeDecision(
      _admitted(const StartsTrajectory(StartsMission()), DecidedBy.rules),
    );
    expect(entry.$1, DecisionEntryKind.eventAdmittedToMission);
    expect(
      _text(entry),
      '{"event":"$_a","by":"rules","reading":{"case":"message-said",'
      '"addressInExternalSystem":"teams:19:x;messageid=1",'
      '"containingAddress":"teams:19:x","addressedTo":"teams:t/bot:app",'
      '"key":"message:1","node":{"shape":"UserSaid","author":"teams:t/p",'
      '"source":"19:x;messageid=1|1","text":"hi"}},'
      '"startsTrajectory":true,"startsMission":true,'
      '"rules":{"tools":"all"},"startsTurn":true}',
    );
  });

  test('a duplicate', () {
    final entry = encodeDecision(
      DuplicateEvent(
        event,
        by: DecidedBy.rules,
        addressInExternalSystem: addressInExternalSystem,
        key: key,
        of: ObjectId.parse(_b)!,
      ),
    );
    expect(entry.$1, DecisionEntryKind.eventNotAdmittedToMission);
    expect(
      _text(entry),
      '{"event":"$_a","by":"rules","why":"duplicate-event",'
      '"addressInExternalSystem":"teams:19:x;messageid=1","key":"message:1",'
      '"of":"$_b"}',
    );
  });

  // A round trip can't catch a renamed word, since the writer and the
  // reader rename together. These are the words already promised to
  // infra's sender rows, loop_launcher and the airlock (Nick, 17 Nov).
  test('the record words are the ones Nick chose', () {
    expect(DecisionEntryKind.all.map((kind) => kind.name), {
      'event-admitted-to-mission',
      'event-not-admitted-to-mission',
      'mission-ended',
      'trajectory-closed',
    });
    String why(EventNotAdmittedToMission decision) =>
        (jsonDecode(_text(encodeDecision(decision))) as Map)['why'] as String;
    expect(
      [
        why(NoReadingForSource(event, by: DecidedBy.rules)),
        why(ReadingFoundNothing(event, by: DecidedBy.rules)),
        for (final decline in [
          AddressNotAdmittedToMission.new,
          SaidStartsNoTurn.new,
          JudgedMessageHasNoTrajectory.new,
          CloseAskedAtAddressWithNoTrajectory.new,
        ])
          why(
            decline(
              event,
              by: DecidedBy.rules,
              addressInExternalSystem: addressInExternalSystem,
              key: key,
            ),
          ),
      ],
      [
        'no-reading-for-source',
        'reading-found-nothing',
        'address-not-admitted-to-mission',
        'said-starts-no-turn',
        'judged-message-has-no-trajectory',
        'close-asked-at-address-with-no-trajectory',
      ],
    );
    expect(
      encodeReading(closeAsked).string('case'),
      'person-asked-to-close-trajectory',
    );
    expect([
      for (final reading in readings) encodeReading(reading).asUncheckedMap(),
    ], everyElement(contains('addressInExternalSystem')));
    expect(
      [for (final reading in readings) encodeReading(reading).string('case')],
      [
        'message-said',
        'message-changed',
        'message-changed',
        'actors-joined-address',
        'shown-message-judged',
      ],
    );
    expect(encodeReading(said).string('containingAddress'), 'teams:19:x');
    expect(encodeReading(said).string('addressedTo'), 'teams:t/bot:app');
  });

  test('every case reads back as what was written, whoever decided it', () {
    final mission = MissionId.parse(_b)!;
    final trajectory = TrajectoryId.parse(_c)!;
    for (final by in DecidedBy.values) {
      final decisions = <AdmissionDecision>[
        _admitted(OnTrajectory(trajectory), by),
        _admitted(StartsTrajectory(InMission(mission)), by),
        _admitted(const StartsTrajectory(StartsMission()), by),
        for (final reading in readings)
          EventAdmittedToMission(
            event,
            by: by,
            reading: reading,
            placement: OnTrajectory(trajectory),
            startsTurn: reading is MessageSaid ? true : null,
          ),
        EventAdmittedToMission(
          event,
          by: by,
          reading: said,
          placement: OnTrajectory(trajectory),
          startsTurn: false,
        ),
        EventAdmittedToMission(
          event,
          by: by,
          reading: readings[3],
          placement: IntoMission(InMission(mission)),
        ),
        _admitted(const IntoMission(StartsMission()), by),
        MissionEnded(event, by: by, mission: mission),
        TrajectoryClosed(
          event,
          by: by,
          reading: closeAsked,
          trajectory: trajectory,
          mission: mission,
        ),
        CloseAskedAtAddressWithNoTrajectory(
          event,
          by: by,
          addressInExternalSystem: addressInExternalSystem,
          key: key,
        ),
        NoReadingForSource(event, by: by),
        ReadingFoundNothing(event, by: by),
        DuplicateEvent(
          event,
          by: by,
          addressInExternalSystem: addressInExternalSystem,
          key: key,
          of: event,
        ),
        AddressNotAdmittedToMission(
          event,
          by: by,
          addressInExternalSystem: addressInExternalSystem,
          key: key,
        ),
        SaidStartsNoTurn(
          event,
          by: by,
          addressInExternalSystem: addressInExternalSystem,
          key: key,
        ),
        JudgedMessageHasNoTrajectory(
          event,
          by: by,
          addressInExternalSystem: addressInExternalSystem,
          key: key,
        ),
        ChangeToUnadmittedMessage(
          event,
          by: by,
          addressInExternalSystem: addressInExternalSystem,
          key: key,
          message: message,
        ),
      ];
      for (final decision in decisions) {
        final (kind, body) = encodeDecision(decision);
        final back = decodeDecision(kind, body);
        expect(back, isNotNull, reason: utf8.decode(body));
        expect(back.runtimeType, decision.runtimeType);
        expect(_text(encodeDecision(back!)), utf8.decode(body));
      }
    }
  });

  test('anything else reads as null', () {
    Uint8List bytes(Map<String, Object?> json) =>
        Uint8List.fromList(utf8.encode(jsonEncode(json)));
    final reading = {
      'case': 'message-said',
      'addressInExternalSystem': 'teams:c',
      'key': 'k',
      'node': {
        'shape': 'UserSaid',
        'author': 'teams:p',
        'source': 'c|1',
        'text': 'hi',
      },
    };
    final good = {
      'event': _a,
      'by': 'rules',
      'reading': reading,
      'trajectory': _c,
      'startsTurn': true,
    };
    expect(
      decodeDecision(DecisionEntryKind.eventAdmittedToMission, bytes(good)),
      isNotNull,
    );
    expect(
      decodeDecision(
        DecisionEntryKind.eventAdmittedToMission,
        bytes({...good, 'startsTurn': false}),
      ),
      isNotNull,
    );
    final (joinKind, joinBody) = encodeDecision(
      EventAdmittedToMission(
        event,
        by: DecidedBy.rules,
        reading: readings.whereType<ActorsJoinedAddress>().single,
        placement: IntoMission(InMission(MissionId.parse(_b)!)),
      ),
    );
    final join = jsonDecode(utf8.decode(joinBody)) as Map<String, Object?>;
    expect(decodeDecision(joinKind, bytes(join)), isNotNull);
    final closeReading = encodeReading(closeAsked).asUncheckedMap();
    final closed = {
      'event': _a,
      'by': 'rules',
      'reading': closeReading,
      'trajectory': _c,
      'mission': _b,
    };
    final bad = <(Kind, Map<String, Object?>)>[
      // Something said must say whether it starts a turn, as a bool.
      (
        DecisionEntryKind.eventAdmittedToMission,
        {...good}..remove('startsTurn'),
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {...good, 'startsTurn': 'yes'},
      ),
      // Nothing but something said says it.
      (joinKind, {...join, 'startsTurn': true}),
      (DecisionEntryKind.eventNotAdmittedToMission, good),
      (DecisionEntryKind.eventAdmittedToMission, {...good, 'extra': 1}),
      (DecisionEntryKind.eventAdmittedToMission, {...good}..remove('reading')),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {...good, 'reading': 'message-said'},
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {
          ...good,
          'reading': {...reading, 'extra': 1},
        },
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {
          ...good,
          'reading': {...reading}..remove('key'),
        },
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {
          ...good,
          'reading': {...reading, 'case': 'x'},
        },
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {
          ...good,
          'reading': {...reading, 'from': 'teams:p'},
        },
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {
          ...good,
          'reading': {...reading, 'containingAddress': null},
        },
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {
          ...good,
          'reading': {...reading, 'addressedTo': null},
        },
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {
          ...good,
          'reading': {...reading, 'addressedTo': 'not an actor'},
        },
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {
          ...good,
          'reading': {
            ...reading,
            'node': {'shape': 'Edited', 'text': 'hi'},
          },
        },
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {
          ...good,
          'reading': {
            'case': 'actors-joined-address',
            'addressInExternalSystem': 'teams:c',
            'key': 'k',
            'joiners': <String>[],
          },
        },
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {
          ...good,
          'reading': {
            'case': 'shown-message-judged',
            'addressInExternalSystem': 'teams:c',
            'key': 'k',
            'to': 'c|1',
            'verdict': {'shape': 'ApprovedVerdict'},
          },
        },
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {...good, 'addressInExternalSystem': 'teams:c'},
      ),
      (DecisionEntryKind.eventAdmittedToMission, {...good}..remove('by')),
      (DecisionEntryKind.eventAdmittedToMission, {...good, 'by': 'nick'}),
      (DecisionEntryKind.eventAdmittedToMission, {...good, 'by': null}),
      (DecisionEntryKind.eventAdmittedToMission, {...good, 'event': 'nothex'}),
      (DecisionEntryKind.eventAdmittedToMission, {...good, 'mission': _b}),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {...good}
          ..remove('trajectory')
          ..addAll({'mission': _b, 'startsMission': true}),
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {...good}
          ..remove('trajectory')
          ..addAll({'startsTrajectory': false, 'mission': _b}),
      ),
      (
        DecisionEntryKind.eventNotAdmittedToMission,
        {
          'event': _a,
          'by': 'rules',
          'why': 'no-reading-for-source',
          'key': 'k',
        },
      ),
      (
        DecisionEntryKind.eventNotAdmittedToMission,
        {'event': _a, 'by': 'rules', 'why': 'never-heard-of-it'},
      ),
      (
        DecisionEntryKind.eventNotAdmittedToMission,
        {'event': _a, 'why': 'no-reading-for-source'},
      ),
      (DecisionEntryKind.missionEnded, {'event': _a, 'by': 'rules'}),
      (
        DecisionEntryKind.missionEnded,
        {'event': _a, 'by': 'rules', 'mission': 'x'},
      ),
      (
        DecisionEntryKind.missionEnded,
        {'event': _a, 'by': 'rules', 'mission': _b, 'why': 'done'},
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {'event': _a, 'by': 'rules', 'mission': _b},
      ),
      (
        Kind.parse('event')!,
        {'event': _a, 'by': 'rules', 'why': 'no-reading-for-source'},
      ),
      // A close is never admitted, and only a close closes a trajectory.
      (
        DecisionEntryKind.eventAdmittedToMission,
        {...good, 'reading': closeReading}..remove('startsTurn'),
      ),
      (DecisionEntryKind.trajectoryClosed, {...closed, 'reading': reading}),
      (DecisionEntryKind.trajectoryClosed, {...closed}..remove('mission')),
      (DecisionEntryKind.trajectoryClosed, {...closed, 'startsTurn': true}),
    ];
    expect(
      decodeDecision(DecisionEntryKind.trajectoryClosed, bytes(closed)),
      isNotNull,
    );
    for (final (kind, json) in bad) {
      expect(decodeDecision(kind, bytes(json)), isNull, reason: '$json');
    }
    final starts = {
      ...good,
      'startsTrajectory': true,
      'startsMission': true,
      'rules': {'tools': 'all'},
    }..remove('trajectory');
    expect(
      decodeDecision(DecisionEntryKind.eventAdmittedToMission, bytes(starts)),
      isNotNull,
    );
    for (final json in [
      {
        ...good,
        'rules': {'tools': 'all'},
      },
      {...starts}..remove('rules'),
      {...starts, 'rules': 'all'},
      {...starts, 'rules': null},
      // Something said that starts no turn starts no trajectory.
      {...starts, 'startsTurn': false},
    ]) {
      expect(
        decodeDecision(DecisionEntryKind.eventAdmittedToMission, bytes(json)),
        isNull,
        reason: '$json',
      );
    }
    expect(
      decodeDecision(
        DecisionEntryKind.eventAdmittedToMission,
        Uint8List.fromList([0xff]),
      ),
      isNull,
    );
  });
}
