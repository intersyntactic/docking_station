// The decision entry is a wire contract: whatever reads the logbook reads
// these field names. So this is kept (RULINGS, "Tests prove once": the
// suite keeps wire contracts).
import 'dart:convert';
import 'dart:typed_data';

import 'package:checked_json/checked_json.dart' show JsonObject;
import 'package:is_annotation_shapes/is_annotation_shapes.dart'
    show ProposedCorrectionVerdict;
import 'package:is_conversation_vocabulary/is_conversation_vocabulary.dart'
    show
        ConversationKind,
        Deleted,
        Edited,
        RepliesUnderWebAddress,
        SourceMessageId,
        UserSaid,
        encodeReplyEndpoint;
import 'package:is_docking_station_api/is_docking_station_api.dart';
import 'package:is_logbook_format/is_logbook_format.dart' show Kind, ObjectId;
import 'package:is_shapes/is_shapes.dart'
    show ActorId, DecidedBy, MissionId, TrajectoryId;
import 'package:is_web_address_vocabulary/is_web_address_vocabulary.dart'
    show AddressPrefix, Origin, PathPrefix;
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
final replyEndpoint = RepliesUnderWebAddress(
  AddressPrefix.of(
    Origin.parse('https://smba.trafficmanager.net')!,
    PathPrefix.parse('/amer/v3/conversations/19:x/activities/')!,
  ),
);

final said = MessageSaid(
  addressInExternalSystem: addressInExternalSystem,
  containingAddress: containingAddress,
  addressedTo: bot,
  replyEndpoint: replyEndpoint,
  key: key,
  node: UserSaid(author: from, source: message, text: 'hi'),
  conversationKind: ConversationKind.groupChat,
);

/// One translated event of each case, each read back as itself.
final translatedEvents = <AdmissibleEvent>[
  said,
  MessageChanged(
    addressInExternalSystem: addressInExternalSystem,
    containingAddress: containingAddress,
    addressedTo: bot,
    replyEndpoint: replyEndpoint,
    from: from,
    key: key,
    message: message,
    change: const Edited(text: 'hello'),
  ),
  MessageChanged(
    addressInExternalSystem: addressInExternalSystem,
    containingAddress: null,
    addressedTo: null,
    replyEndpoint: null,
    from: null,
    key: key,
    message: message,
    change: const Deleted(),
  ),
  ActorsJoinedAddress.of(
    addressInExternalSystem: containingAddress,
    containingAddress: null,
    addressedTo: null,
    replyEndpoint: null,
    from: from,
    key: key,
    joiners: [from, ActorId.parse('teams:bot')!],
  )!,
  ShownMessageJudged(
    addressInExternalSystem: addressInExternalSystem,
    containingAddress: containingAddress,
    addressedTo: bot,
    replyEndpoint: replyEndpoint,
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
  replyEndpoint: replyEndpoint,
  from: from,
  key: EventKey.parse('invoke:1')!,
  message: message,
  trajectory: TrajectoryId.parse(_c)!,
);

final rules = JsonObject.of({'tools': 'all'});

EventAdmittedToMission _admitted(AdmittedPlacement placement, DecidedBy by) =>
    EventAdmittedToMission(
      event,
      by: by,
      translatedEvent: said,
      placement: placement,
      rules: EventAdmittedToMission.starts(placement) ? rules : null,
      startsTurn: true,
    );

String _text((Kind, Uint8List) entry) => utf8.decode(entry.$2);

const _replyEndpointField =
    '"replyEndpoint":{"case":"under-web-address","addressPrefix":'
    '{"origin":"https://smba.trafficmanager.net",'
    '"pathPrefix":"/amer/v3/conversations/19:x/activities/"}}';

void main() {
  group('the kind of conversation something said was in', () {
    MessageSaid saidIn(ConversationKind kind) => MessageSaid(
      addressInExternalSystem: addressInExternalSystem,
      containingAddress: containingAddress,
      addressedTo: bot,
      replyEndpoint: replyEndpoint,
      key: key,
      node: said.node,
      conversationKind: kind,
    );

    test('every kind reads back as itself', () {
      for (final kind in ConversationKind.values) {
        final read = decodeTranslatedEvent(
          JsonObject.decode(jsonEncode(encodeTranslatedEvent(saidIn(kind)))),
        );
        expect((read as MessageSaid).conversationKind, kind);
      }
    });

    test('an entry written before the field existed reads as not known', () {
      final json = JsonObject.decode(jsonEncode(encodeTranslatedEvent(said)))
          .without(const {'conversationKind'});
      final read = decodeTranslatedEvent(json) as MessageSaid;
      expect(read.conversationKind, ConversationKind.notKnown);
    });

    test('a kind it does not know is refused, not read as not known', () {
      for (final wrong in <Object?>['channel', '', 1, null]) {
        final json = JsonObject.decode(jsonEncode(encodeTranslatedEvent(said)))
            .withFields({'conversationKind': wrong});
        expect(
          () => decodeTranslatedEvent(json),
          throwsA(isA<FormatException>()),
          reason: '$wrong',
        );
      }
    });
  });

  test('an admission that starts a mission and its first trajectory', () {
    final entry = encodeDecision(
      _admitted(const StartsTrajectory(StartsMission()), DecidedBy.rules),
    );
    expect(entry.$1, DecisionEntryKind.eventAdmittedToMission);
    expect(
      _text(entry),
      '{"event":"$_a","by":"rules","translatedEvent":{"case":"message-said",'
      '"addressInExternalSystem":"teams:19:x;messageid=1",'
      '"containingAddress":"teams:19:x","addressedTo":"teams:t/bot:app",'
      '$_replyEndpointField,'
      '"key":"message:1","node":{"shape":"UserSaid","author":"teams:t/p",'
      '"source":"19:x;messageid=1|1","text":"hi"},'
      '"conversationKind":"group-chat"},'
      '"startsTrajectory":true,"startsMission":true,'
      '"rules":{"tools":"all"},$_replyEndpointField,"startsTurn":true}',
    );
  });

  test('a start entry carries its translated event\'s reply endpoint, and '
      'only that', () {
    Map<String, Object?> json(EventAdmittedToMission decision) =>
        jsonDecode(utf8.decode(encodeDecision(decision).$2))
            as Map<String, Object?>;
    EventAdmittedToMission? read(Map<String, Object?> json) => decodeDecision(
      DecisionEntryKind.eventAdmittedToMission,
      Uint8List.fromList(utf8.encode(jsonEncode(json))),
    ) as EventAdmittedToMission?;
    final starts = _admitted(
      const StartsTrajectory(StartsMission()),
      DecidedBy.rules,
    );
    final onTrajectory = _admitted(
      OnTrajectory(TrajectoryId.parse(_c)!),
      DecidedBy.rules,
    );
    expect(starts.replyEndpoint, replyEndpoint);
    expect(onTrajectory.replyEndpoint, isNull);
    expect(json(onTrajectory).containsKey('replyEndpoint'), isFalse);
    expect(read(json(starts))?.replyEndpoint, replyEndpoint);

    final elsewhere = encodeReplyEndpoint(
      RepliesUnderWebAddress(
        AddressPrefix.of(
          Origin.parse('https://elsewhere.example.com')!,
          PathPrefix.parse('/')!,
        ),
      ),
    );
    for (final bad in [
      json(starts)..remove('replyEndpoint'),
      json(starts)..['replyEndpoint'] = elsewhere,
      json(onTrajectory)
        ..['replyEndpoint'] = encodeReplyEndpoint(replyEndpoint),
      json(starts)..['replyEndpoint'] = 'https://smba.trafficmanager.net/',
    ]) {
      expect(read(bad), isNull, reason: '$bad');
    }
  });

  test('a reply endpoint with an extra field, on it or in its address '
      'prefix, is refused', () {
    final good = encodeReplyEndpoint(replyEndpoint);
    final prefix = good.object('addressPrefix');
    for (final endpoint in [
      good.withFields({'extra': 1}),
      good.withFields({
        'addressPrefix': prefix.withFields({'extra': 1}),
      }),
    ]) {
      final entry = jsonDecode(
        utf8.decode(
          encodeDecision(
            _admitted(const StartsTrajectory(StartsMission()), DecidedBy.rules),
          ).$2,
        ),
      ) as Map<String, Object?>;
      entry['replyEndpoint'] = endpoint;
      (entry['translatedEvent']! as Map<String, Object?>)['replyEndpoint'] =
          endpoint;
      expect(
        decodeDecision(
          DecisionEntryKind.eventAdmittedToMission,
          Uint8List.fromList(utf8.encode(jsonEncode(entry))),
        ),
        isNull,
        reason: '$endpoint',
      );
    }
  });

  test(
    'an entry naming a field twice is refused, even with the same value',
    () {
      final (kind, body) = encodeDecision(
        _admitted(const StartsTrajectory(StartsMission()), DecidedBy.rules),
      );
      final text = utf8.decode(body);
      final MapEntry(:key, :value) =
          (jsonDecode(text) as Map<String, Object?>).entries.first;
      final twice = text.replaceFirst(
        '{',
        '{${jsonEncode(key)}:${jsonEncode(value)},',
      );
      expect(decodeDecision(kind, body), isNotNull);
      expect(
        decodeDecision(kind, Uint8List.fromList(utf8.encode(twice))),
        isNull,
      );
    },
  );

  test('a close names the trajectory it closes, and one that names none is '
      'refused', () {
    final json = encodeTranslatedEvent(closeAsked).asUncheckedMap();
    expect(json['trajectory'], _c);
    expect(
      (decodeTranslatedEvent(
        JsonObject.of(json),
      ) as PersonAskedToCloseTrajectory).trajectory,
      TrajectoryId.parse(_c),
    );
    for (final bad in [
      {...json}..remove('trajectory'),
      {...json, 'trajectory': 'not-a-trajectory'},
    ]) {
      expect(
        () => decodeTranslatedEvent(JsonObject.of(bad)),
        throwsFormatException,
        reason: '$bad',
      );
    }
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

  test('a close by an operator names no event and was decided by a person', () {
    final entry = encodeDecision(
      TrajectoryClosedByOperator(
        trajectory: TrajectoryId.parse(_c)!,
        mission: MissionId.parse(_b)!,
        operator: OperatorName.parse('nick')!,
        reason: 'clearing test trajectories',
      ),
    );
    expect(entry.$1, DecisionEntryKind.trajectoryClosed);
    expect(
      _text(entry),
      '{"by":"person","trajectory":"$_c","mission":"$_b",'
      '"operator":"nick","reason":"clearing test trajectories"}',
    );
    expect(
      () => TrajectoryClosedByOperator(
        trajectory: TrajectoryId.parse(_c)!,
        mission: MissionId.parse(_b)!,
        operator: OperatorName.parse('nick')!,
        reason: '  ',
      ),
      throwsArgumentError,
    );
    expect([
      for (final s in ['nick', '_ops', 'a-b_1']) OperatorName.parse(s),
    ], everyElement(isNotNull));
    expect([
      for (final s in ['', 'Nick', '1nick', 'ni ck', 'a' * 33])
        OperatorName.parse(s),
    ], everyElement(isNull));
  });

  // A round trip can't catch a renamed word, since the writer and the
  // reader rename together. These are the words already promised to
  // infra's sender rows, loop_launcher and the airlock.
  test('the logbook words are the ones promised to their readers', () {
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
        why(NoTranslatorForSource(event, by: DecidedBy.rules)),
        why(TranslatorFoundNothing(event, by: DecidedBy.rules)),
        for (final decline in [
          AddressNotAdmittedToMission.new,
          SaidStartsNoTurn.new,
          JudgedMessageHasNoTrajectory.new,
          CloseAskedForTrajectoryNotOpenAtAddress.new,
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
        'no-translator-for-source',
        'translator-found-nothing',
        'address-not-admitted-to-mission',
        'said-starts-no-turn',
        'judged-message-has-no-trajectory',
        'close-asked-for-trajectory-not-open-at-address',
      ],
    );
    expect(
      encodeTranslatedEvent(closeAsked).string('case'),
      'person-asked-to-close-trajectory',
    );
    expect([
      for (final translatedEvent in translatedEvents)
        encodeTranslatedEvent(translatedEvent).asUncheckedMap(),
    ], everyElement(contains('addressInExternalSystem')));
    expect(
      [
        for (final translatedEvent in translatedEvents)
          encodeTranslatedEvent(translatedEvent).string('case'),
      ],
      [
        'message-said',
        'message-changed',
        'message-changed',
        'actors-joined-address',
        'shown-message-judged',
      ],
    );
    expect(
      encodeTranslatedEvent(said).string('containingAddress'),
      'teams:19:x',
    );
    expect(
      encodeTranslatedEvent(said).string('addressedTo'),
      'teams:t/bot:app',
    );
  });

  test('every case reads back as what was written, whoever decided it', () {
    final mission = MissionId.parse(_b)!;
    final trajectory = TrajectoryId.parse(_c)!;
    for (final by in DecidedBy.values) {
      final decisions = <AdmissionDecision>[
        _admitted(OnTrajectory(trajectory), by),
        _admitted(StartsTrajectory(InMission(mission)), by),
        _admitted(const StartsTrajectory(StartsMission()), by),
        for (final translatedEvent in translatedEvents)
          EventAdmittedToMission(
            event,
            by: by,
            translatedEvent: translatedEvent,
            placement: OnTrajectory(trajectory),
            startsTurn: translatedEvent is MessageSaid ? true : null,
          ),
        EventAdmittedToMission(
          event,
          by: by,
          translatedEvent: said,
          placement: OnTrajectory(trajectory),
          startsTurn: false,
        ),
        EventAdmittedToMission(
          event,
          by: by,
          translatedEvent: translatedEvents[3],
          placement: IntoMission(InMission(mission)),
        ),
        _admitted(const IntoMission(StartsMission()), by),
        MissionEnded(event, by: by, mission: mission),
        TrajectoryClosedBecausePersonAsked(
          event,
          by: by,
          translatedEvent: closeAsked,
          trajectory: trajectory,
          mission: mission,
        ),
        TrajectoryClosedByOperator(
          trajectory: trajectory,
          mission: mission,
          operator: OperatorName.parse('nick')!,
          reason: 'clearing test trajectories',
        ),
        CloseAskedForTrajectoryNotOpenAtAddress(
          event,
          by: by,
          addressInExternalSystem: addressInExternalSystem,
          key: key,
        ),
        NoTranslatorForSource(event, by: by),
        TranslatorFoundNothing(event, by: by),
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
    final translatedEvent = {
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
      'translatedEvent': translatedEvent,
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
        translatedEvent: translatedEvents
            .whereType<ActorsJoinedAddress>()
            .single,
        placement: IntoMission(InMission(MissionId.parse(_b)!)),
      ),
    );
    final join = jsonDecode(utf8.decode(joinBody)) as Map<String, Object?>;
    expect(decodeDecision(joinKind, bytes(join)), isNotNull);
    final closeAskedJson = encodeTranslatedEvent(closeAsked).asUncheckedMap();
    final closed = {
      'event': _a,
      'by': 'rules',
      'translatedEvent': closeAskedJson,
      'trajectory': _c,
      'mission': _b,
    };
    final byOperator = {
      'by': 'person',
      'trajectory': _c,
      'mission': _b,
      'operator': 'nick',
      'reason': 'stuck loop',
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
      (
        DecisionEntryKind.eventAdmittedToMission,
        {...good}..remove('translatedEvent'),
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {...good, 'translatedEvent': 'message-said'},
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {
          ...good,
          'translatedEvent': {...translatedEvent, 'extra': 1},
        },
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {
          ...good,
          'translatedEvent': {...translatedEvent}..remove('key'),
        },
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {
          ...good,
          'translatedEvent': {...translatedEvent, 'case': 'x'},
        },
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {
          ...good,
          'translatedEvent': {...translatedEvent, 'from': 'teams:p'},
        },
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {
          ...good,
          'translatedEvent': {...translatedEvent, 'containingAddress': null},
        },
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {
          ...good,
          'translatedEvent': {...translatedEvent, 'addressedTo': null},
        },
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {
          ...good,
          'translatedEvent': {
            ...translatedEvent,
            'addressedTo': 'not an actor',
          },
        },
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {
          ...good,
          'translatedEvent': {
            ...translatedEvent,
            'node': {'shape': 'Edited', 'text': 'hi'},
          },
        },
      ),
      (
        DecisionEntryKind.eventAdmittedToMission,
        {
          ...good,
          'translatedEvent': {
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
          'translatedEvent': {
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
          'why': 'no-translator-for-source',
          'key': 'k',
        },
      ),
      (
        DecisionEntryKind.eventNotAdmittedToMission,
        {'event': _a, 'by': 'rules', 'why': 'never-heard-of-it'},
      ),
      (
        DecisionEntryKind.eventNotAdmittedToMission,
        {'event': _a, 'why': 'no-translator-for-source'},
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
        {'event': _a, 'by': 'rules', 'why': 'no-translator-for-source'},
      ),
      // A close is never admitted, and only a close closes a trajectory.
      (
        DecisionEntryKind.eventAdmittedToMission,
        {...good, 'translatedEvent': closeAskedJson}..remove('startsTurn'),
      ),
      (
        DecisionEntryKind.trajectoryClosed,
        {...closed, 'translatedEvent': translatedEvent},
      ),
      (DecisionEntryKind.trajectoryClosed, {...closed}..remove('mission')),
      (DecisionEntryKind.trajectoryClosed, {...closed, 'startsTurn': true}),
      // A close by an operator is decided by a person, names who and why,
      // and never an event or a translated event.
      (DecisionEntryKind.trajectoryClosed, {...byOperator, 'by': 'rules'}),
      (DecisionEntryKind.trajectoryClosed, {...byOperator, 'event': _a}),
      (
        DecisionEntryKind.trajectoryClosed,
        {...byOperator, 'translatedEvent': closeAskedJson},
      ),
      (DecisionEntryKind.trajectoryClosed, {...byOperator}..remove('reason')),
      (DecisionEntryKind.trajectoryClosed, {...byOperator, 'reason': ' '}),
      (DecisionEntryKind.trajectoryClosed, {...byOperator, 'reason': 1}),
      (DecisionEntryKind.trajectoryClosed, {...byOperator, 'operator': 'Nick'}),
      (DecisionEntryKind.trajectoryClosed, {...byOperator}..remove('mission')),
      (DecisionEntryKind.trajectoryClosed, {...byOperator, 'extra': 1}),
      (DecisionEntryKind.missionEnded, {...byOperator}),
    ];
    expect(
      decodeDecision(DecisionEntryKind.trajectoryClosed, bytes(closed)),
      isNotNull,
    );
    expect(
      decodeDecision(DecisionEntryKind.trajectoryClosed, bytes(byOperator)),
      isA<TrajectoryClosedByOperator>(),
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
