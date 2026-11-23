// What the docking station sends a logbook, and when: against a logbook kept in
// memory the way the logbook service keeps one.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:checked_json/checked_json.dart' show JsonObject;
import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId, UserSaid;
import 'package:docking_station_service/docking_station_service.dart';
import 'package:is_admission_vocabulary/is_admission_vocabulary.dart';
import 'package:is_logbook_client/is_logbook_client.dart';
import 'package:is_shapes/is_shapes.dart' show ActorId, DecidedBy, TrajectoryId;
import 'package:test/test.dart';

final ann = ActorId.parse('teams:t/p')!;
final chat = AddressInExternalSystem.parse('test:chat')!;

/// The event a decision was decided at; every decision these tests send has
/// one.
extension on AdmissionDecision {
  ObjectId get event => switch (this) {
    DecidedAtEvent(:final event) => event,
    _ => throw StateError('$this was decided at no event'),
  };
}

/// The start entry's kind in these tests. The real one is the service's to
/// name, so the runner is given it.
const _startKind = 'test-start';

/// A logbook in memory: entries in order, a subscription that sends the
/// backlog, then caught-up, then each new entry, and one chain of decisions
/// whose tip a sent decision must name as previous, as the logbook service
/// checks. It starts with its start entry, unless [started] is false.
final class _Logbook {
  _Logbook({bool started = true}) {
    if (started) start();
  }

  final _entries = <Entry>[];
  final _subscribers = <(Set<Kind>, StreamController<Subscribed>)>[];
  ObjectId? _tip;

  /// Each decision sent, refused or not, with the previous it named.
  final sent = <(ObjectId?, AdmissionDecision)>[];

  /// Run once, as the next decision is sent, before it is checked.
  void Function()? beforeNextSend;

  /// What every decision sent is answered with instead, when set.
  WriteResult? answer;

  /// When set, the next decision sent is recorded first, byte for byte, as
  /// if another docking station had sent the same decision just before.
  bool sameBytesFirst = false;

  /// The decisions recorded, in order.
  List<AdmissionDecision> get decisions => [
    for (final entry in _entries) ?decodeDecision(entry.kind, entry.body),
  ];

  /// The first start entry's id.
  ObjectId get startEntry =>
      _entries.firstWhere((e) => e.kind.name == _startKind).id;

  /// The ids of the decisions recorded, in order.
  List<ObjectId> get decisionEntries => [
    for (final entry in _entries)
      if (decodeDecision(entry.kind, entry.body) != null) entry.id,
  ];

  Entry add(String kind, ObjectId? previous, List<int> body) {
    final header = utf8.encode('$kind\n${previous?.hex ?? '-'}\n');
    final bytes = Uint8List.fromList([...header, ...body]);
    // Named by the sha256 of its text, as the logbook names it. A kind made
    // from its name, never one of the docking station's own, so the docking
    // station has to compare kinds by value.
    final entry = Entry(
      id: ObjectId.of(bytes),
      kind: Kind.parse(kind)!,
      previous: previous,
      recorded: bytes,
    );
    _entries.add(entry);
    for (final (kinds, subscriber) in _subscribers) {
      if (kinds.contains(entry.kind)) subscriber.add(entry);
    }
    return entry;
  }

  /// An event from [source], whose bytes are [what] as JSON, recorded as an
  /// entry of [kind].
  Entry recordEvent(
    Map<String, Object?> what, {
    String source = 'test',
    String kind = 'event',
  }) => add(
    kind,
    null,
    utf8.encode(
      jsonEncode({
        'at': '2026-11-16T00:00:00Z',
        'source': source,
        'bytes': base64Encode(utf8.encode(jsonEncode(what))),
      }),
    ),
  );

  /// The start entry, as setup writes it: with no previous, and the first
  /// thing a decision names as previous.
  Entry start() {
    final entry = add(_startKind, null, utf8.encode('{}'));
    _tip ??= entry.id;
    return entry;
  }

  /// [decision], sent by another docking station, naming the tip.
  void decideElsewhere(AdmissionDecision decision) {
    final (kind, body) = encodeDecision(decision);
    _tip = add(kind.name, _tip, body).id;
  }

  Stream<Subscribed> subscribe(Set<Kind> kinds) {
    final subscriber = StreamController<Subscribed>();
    for (final entry in _entries) {
      if (kinds.contains(entry.kind)) subscriber.add(entry);
    }
    subscriber.add(CaughtUp(_entries.lastOrNull?.id));
    _subscribers.add((kinds, subscriber));
    return subscriber.stream;
  }

  Future<WriteResult> send(
    Kind kind,
    List<int> body, {
    ObjectId? previous,
  }) async {
    sent.add((previous, decodeDecision(kind, Uint8List.fromList(body))!));
    final before = beforeNextSend;
    beforeNextSend = null;
    before?.call();
    if (sameBytesFirst) {
      sameBytesFirst = false;
      _tip = add(kind.name, previous, body).id;
    }
    if (answer case final answer?) return answer;
    // As the logbook does: bytes already in are answered before the tip is
    // checked, since their header names the previous they were sent after.
    final id = ObjectId.of(
      Uint8List.fromList([
        ...utf8.encode('${kind.name}\n${previous?.hex ?? '-'}\n'),
        ...body,
      ]),
    );
    if (_entries.any((entry) => entry.id == id)) return AlreadyRecorded(id);
    if (previous != _tip) return NotTip(_tip!);
    _tip = add(kind.name, previous, body).id;
    return Written(_tip!);
  }

  Future<void> close() async {
    for (final (_, subscriber) in _subscribers) {
      await subscriber.close();
    }
  }
}

/// Reads an event's bytes, `{"said": <text>, "key": <key>}`, as [ann]
/// saying it in [chat]; anything else as nothing to admit. Keeps which
/// events it was given, in order.
final class _Reading implements ModuleReading<int> {
  final given = <ObjectId>[];

  @override
  String get source => 'test';

  @override
  int get start => 0;

  @override
  (int, EventReading) step(int state, RelayedEvent event) {
    given.add(event.entry);
    final what = jsonDecode(utf8.decode(event.bytes)) as Map<String, Object?>;
    if (what case {'said': final String text, 'key': final String key}) {
      return (
        state + 1,
        MessageSaid(
          addressInExternalSystem: chat,
          containingAddress: null,
          addressedTo: null,
          key: EventKey.parse(key)!,
          node: UserSaid(
            author: ann,
            source: SourceMessageId.parse('chat|$key')!,
            text: text,
          ),
        ),
      );
    }
    return (state + 1, const NothingToAdmit());
  }
}

final class _TakesIn implements DecidesWhichAddressStartsAMission {
  const _TakesIn();

  @override
  JsonObject takeIn(AdmissibleEvent first) =>
      const JsonObject.of({'tools': 'all'});
}

final class _EverySaid implements TurnRule {
  const _EverySaid();

  @override
  bool startsTurn(MessageSaid said, AdmittedPlacement placement) => true;
}

Future<void> _run(_Logbook logbook, _Reading reading) => runDockingStation(
  subscribe: logbook.subscribe,
  send: logbook.send,
  startKind: Kind.parse(_startKind)!,
  readings: [reading],
  missions: const _TakesIn(),
  turns: const _EverySaid(),
);

/// Runs the docking station on [logbook] until it has done all it can, then
/// ends the logbook and waits for it to finish.
Future<void> _runToEnd(_Logbook logbook, _Reading reading) async {
  final running = _run(logbook, reading);
  await pumpEventQueue();
  await logbook.close();
  await running;
}

EventAdmittedToMission _startsChat(ObjectId event, String key) =>
    EventAdmittedToMission(
      event,
      by: DecidedBy.rules,
      reading: MessageSaid(
        addressInExternalSystem: chat,
        containingAddress: null,
        addressedTo: null,
        key: EventKey.parse(key)!,
        node: UserSaid(
          author: ann,
          source: SourceMessageId.parse('chat|$key')!,
          text: 'hi',
        ),
      ),
      placement: const StartsTrajectory(StartsMission()),
      rules: const JsonObject.of({'tools': 'all'}),
      startsTurn: true,
    );

void main() {
  test('once caught up, decides each waiting event, each naming the '
      'one before', () async {
    final logbook = _Logbook();
    final a = logbook.recordEvent({'said': 'hello', 'key': 'a'});
    final b = logbook.recordEvent({'said': 'again', 'key': 'b'});
    await _runToEnd(logbook, _Reading());

    final [(firstPrevious, first), (secondPrevious, second)] = logbook.sent;
    final [firstEntry, _] = logbook.decisionEntries;
    expect(firstPrevious, logbook.startEntry);
    expect(first.event, a.id);
    expect(first.by, DecidedBy.rules);
    expect(
      (first as EventAdmittedToMission).placement,
      isA<StartsTrajectory>().having(
        (p) => p.mission,
        'mission',
        isA<StartsMission>(),
      ),
    );
    expect(secondPrevious, firstEntry);
    expect(second.event, b.id);
    expect(
      ((second as EventAdmittedToMission).placement as OnTrajectory)
          .trajectory
          .hex,
      firstEntry.hex,
    );
  });

  test('takes the decisions in the logbook, and decides only what is left, '
      'reading every event', () async {
    final logbook = _Logbook();
    final reading = _Reading();
    final a = logbook.recordEvent({'said': 'hello', 'key': 'a'});
    logbook.decideElsewhere(_startsChat(a.id, 'a'));
    final b = logbook.recordEvent({'said': 'again', 'key': 'b'});
    await _runToEnd(logbook, reading);

    final aDecision = logbook.decisionEntries.first;
    final [(previous, decision)] = logbook.sent;
    expect(reading.given, [a.id, b.id]);
    expect(previous, aDecision);
    expect(decision.event, b.id);
    expect(
      ((decision as EventAdmittedToMission).placement as OnTrajectory)
          .trajectory
          .hex,
      aDecision.hex,
    );
  });

  test('decides an event that comes after catching up, as it comes', () async {
    final logbook = _Logbook();
    final running = _run(logbook, _Reading());
    await pumpEventQueue();
    expect(logbook.sent, isEmpty);

    final c = logbook.recordEvent({'said': 'late', 'key': 'c'});
    await pumpEventQueue();
    await logbook.close();
    await running;

    final [(_, decision)] = logbook.sent;
    expect(decision.event, c.id);
    expect(logbook.decisions.map((d) => d.event), [c.id]);
  });

  test('when another docking station decided first, takes its decision and '
      'sends nothing more', () async {
    final logbook = _Logbook();
    final a0 = logbook.recordEvent({'said': 'hello', 'key': 'a0'});
    logbook.decideElsewhere(_startsChat(a0.id, 'a0'));
    final a = logbook.recordEvent({'said': 'again', 'key': 'a'});
    logbook.beforeNextSend = () => logbook.decideElsewhere(
      SaidStartsNoTurn(
        a.id,
        by: DecidedBy.rules,
        addressInExternalSystem: chat,
        key: EventKey.parse('a')!,
      ),
    );
    await _runToEnd(logbook, _Reading());

    expect(logbook.sent, hasLength(1));
    expect(logbook.decisions.map((d) => d.event), [a0.id, a.id]);
    expect(logbook.decisions.last, isA<SaidStartsNoTurn>());
  });

  for (final (what, answer, stops) in [
    (
      'a refusal',
      const WriteRefused('kind-not-allowed event-admitted-to-mission'),
      isA<LogbookNoRestartChanges>(),
    ),
    // The decision may be in: started again, it reads back whatever got in.
    ('a failed add', const WriteFailed('disk full'), isA<StateError>()),
    (
      'no answer',
      const Unanswered('closed before answering'),
      isA<StateError>(),
    ),
  ]) {
    test('$what, rather than not-tip, stops it', () async {
      final logbook = _Logbook();
      final a0 = logbook.recordEvent({'said': 'hello', 'key': 'a0'});
      logbook.decideElsewhere(_startsChat(a0.id, 'a0'));
      logbook.recordEvent({'said': 'again', 'key': 'a'});
      logbook.answer = answer;

      await expectLater(_run(logbook, _Reading()), throwsA(stops));
      expect(logbook.decisions, hasLength(1));
      await logbook.close();
    });
  }

  test('a decision it cannot read stops it', () async {
    final logbook = _Logbook();
    logbook.add(
      'event-admitted-to-mission',
      null,
      utf8.encode('{"not": "a decision"}'),
    );

    await expectLater(
      _run(logbook, _Reading()),
      throwsA(isA<LogbookNoRestartChanges>()),
    );
    await logbook.close();
  });

  test(
    'an event from a source no reading takes is not admitted, unread',
    () async {
      final logbook = _Logbook();
      final x = logbook.recordEvent({
        'said': 'hi',
        'key': 'x',
      }, source: 'elsewhere');
      final reading = _Reading();
      await _runToEnd(logbook, reading);

      final [(_, decision)] = logbook.sent;
      expect(decision, isA<NoReadingForSource>());
      expect(decision.event, x.id);
      expect(reading.given, isEmpty);
    },
  );

  test('reads an event recorded before the rename, as `arrived`', () async {
    final logbook = _Logbook();
    final reading = _Reading();
    final old = logbook.recordEvent({
      'said': 'hello',
      'key': 'a',
    }, kind: 'arrived');
    final now = logbook.recordEvent({'said': 'again', 'key': 'b'});
    await _runToEnd(logbook, reading);

    expect(reading.given, [old.id, now.id]);
    expect(logbook.decisions.map((d) => d.event), [old.id, now.id]);
  });

  test('an event before the start entry is read but never decided, and the '
      'first decision names the start entry', () async {
    final logbook = _Logbook(started: false);
    final reading = _Reading();
    final before = logbook.recordEvent({'said': 'test', 'key': 'a'});
    final start = logbook.start();
    final after = logbook.recordEvent({'said': 'real', 'key': 'b'});
    await _runToEnd(logbook, reading);

    expect(reading.given, [before.id, after.id]);
    final [(previous, decision)] = logbook.sent;
    expect(previous, start.id);
    expect(decision.event, after.id);
  });

  test('with no start entry, decides nothing until one comes', () async {
    final logbook = _Logbook(started: false);
    logbook.recordEvent({'said': 'test', 'key': 'a'});
    final running = _run(logbook, _Reading());
    await pumpEventQueue();
    expect(logbook.sent, isEmpty);

    final start = logbook.start();
    final after = logbook.recordEvent({'said': 'real', 'key': 'b'});
    await pumpEventQueue();
    await logbook.close();
    await running;

    final [(previous, decision)] = logbook.sent;
    expect(previous, start.id);
    expect(decision.event, after.id);
  });

  test('when two docking stations make the first decision at once, the '
      'second takes the first one\'s', () async {
    final logbook = _Logbook();
    final a = logbook.recordEvent({'said': 'hello', 'key': 'a'});
    logbook.beforeNextSend = () =>
        logbook.decideElsewhere(_startsChat(a.id, 'a'));
    await _runToEnd(logbook, _Reading());

    // Its own first decision named the start entry, as the other's did,
    // so the logbook refused it rather than starting a second chain.
    expect(logbook.sent, hasLength(1));
    expect(logbook.decisions.map((d) => d.event), [a.id]);
  });

  test('a decision whose exact bytes are already in is taken as written, '
      'and the next names it', () async {
    final logbook = _Logbook();
    final a = logbook.recordEvent({'said': 'hello', 'key': 'a'});
    logbook.sameBytesFirst = true;
    final running = _run(logbook, _Reading());
    await pumpEventQueue();
    final b = logbook.recordEvent({'said': 'again', 'key': 'b'});
    await pumpEventQueue();
    await logbook.close();
    await running;

    // Recorded once, not twice, and the docking station went on.
    expect(logbook.decisions.map((d) => d.event), [a.id, b.id]);
    final [_, (previous, _)] = logbook.sent;
    expect(previous, logbook.decisionEntries.first);
  });

  test('a second start entry stops it', () async {
    final logbook = _Logbook();
    logbook.start();

    await expectLater(
      _run(logbook, _Reading()),
      throwsA(isA<LogbookNoRestartChanges>()),
    );
    await logbook.close();
  });

  test('a decision before the start entry stops it', () async {
    final logbook = _Logbook(started: false);
    final a = logbook.recordEvent({'said': 'hello', 'key': 'a'});
    logbook.decideElsewhere(_startsChat(a.id, 'a'));
    logbook.start();

    await expectLater(
      _run(logbook, _Reading()),
      throwsA(isA<LogbookNoRestartChanges>()),
    );
    await logbook.close();
  });

  test('the start entry\'s kind is no event\'s or decision\'s', () async {
    for (final kind in [
      'event',
      'arrived',
      'event-admitted-to-mission',
      'event-not-admitted-to-mission',
      'mission-ended',
    ]) {
      final logbook = _Logbook();
      await expectLater(
        runDockingStation(
          subscribe: logbook.subscribe,
          send: logbook.send,
          startKind: Kind.parse(kind)!,
          readings: [_Reading()],
          missions: const _TakesIn(),
          turns: const _EverySaid(),
        ),
        throwsA(isA<ArgumentError>()),
        reason: kind,
      );
    }
  });

  group('an operator closing a trajectory', () {
    final nick = OperatorName.parse('nick')!;

    Future<OperatorCloseOutcome> close(
      _Logbook logbook,
      TrajectoryId trajectory,
    ) => closeTrajectoryByOperator(
      subscribe: logbook.subscribe,
      send: logbook.send,
      startKind: Kind.parse(_startKind)!,
      trajectory: trajectory,
      operator: nick,
      reason: 'clearing test trajectories',
    );

    test('closes it while the docking station runs, which reads the close '
        'back and starts a new trajectory at its address', () async {
      final logbook = _Logbook();
      final running = _run(logbook, _Reading());
      logbook.recordEvent({'said': 'hello', 'key': 'a'});
      await pumpEventQueue();
      final started = TrajectoryId.parse(logbook.decisionEntries.single.hex)!;

      final outcome = await close(logbook, started);
      expect(
        outcome,
        isA<OperatorClosedTrajectory>()
            .having((c) => c.decision.trajectory, 'trajectory', started)
            .having((c) => c.decision.mission.hex, 'mission', started.hex),
      );
      final (previous, _) = logbook.sent.last;
      expect(previous, logbook.decisionEntries.first);

      logbook.recordEvent({'said': 'again', 'key': 'b'});
      await pumpEventQueue();
      await logbook.close();
      await running;

      final after = logbook.decisions.last as EventAdmittedToMission;
      expect(
        after.placement,
        isA<StartsTrajectory>().having(
          (p) => p.mission,
          'in the same mission',
          isA<InMission>().having((m) => m.mission.hex, 'mission', started.hex),
        ),
      );
    });

    test('reads the chain again when the docking station decided between '
        'its read and its send', () async {
      final logbook = _Logbook();
      final a = logbook.recordEvent({'said': 'hello', 'key': 'a'});
      logbook.decideElsewhere(_startsChat(a.id, 'a'));
      final started = TrajectoryId.parse(logbook.decisionEntries.single.hex)!;
      final b = logbook.recordEvent({'said': 'again', 'key': 'b'});
      logbook.beforeNextSend = () => logbook.decideElsewhere(
        SaidStartsNoTurn(
          b.id,
          by: DecidedBy.rules,
          addressInExternalSystem: chat,
          key: EventKey.parse('b')!,
        ),
      );

      expect(await close(logbook, started), isA<OperatorClosedTrajectory>());
      final [(firstTry, _), (secondTry, _)] = logbook.sent;
      expect(firstTry, logbook.decisionEntries[0]);
      expect(secondTry, logbook.decisionEntries[1]);
      expect(logbook.decisions.last, isA<TrajectoryClosedByOperator>());
    });

    test('closes nothing that is not open', () async {
      final logbook = _Logbook();
      final a = logbook.recordEvent({'said': 'hello', 'key': 'a'});
      logbook.decideElsewhere(_startsChat(a.id, 'a'));
      final started = TrajectoryId.parse(logbook.decisionEntries.single.hex)!;

      expect(await close(logbook, started), isA<OperatorClosedTrajectory>());
      expect(await close(logbook, started), isA<NoOpenTrajectory>());
      expect(
        await close(logbook, TrajectoryId.parse('e' * 64)!),
        isA<NoOpenTrajectory>(),
      );
      expect(
        await close(_Logbook(started: false), started),
        isA<NoStartEntry>(),
      );
      expect(logbook.sent, hasLength(1));
    });

    test('says a close may or may not be in when the logbook does not '
        'answer', () async {
      final logbook = _Logbook()..answer = const Unanswered('timed out');
      final a = logbook.recordEvent({'said': 'hello', 'key': 'a'});
      logbook.decideElsewhere(_startsChat(a.id, 'a'));
      final started = TrajectoryId.parse(logbook.decisionEntries.single.hex)!;

      expect(
        await close(logbook, started),
        isA<OperatorCloseMayOrMayNotBeIn>(),
      );
    });
  });
}
