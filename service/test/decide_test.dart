// What [decide] makes of events against what [DecidedSoFar] holds, without a
// logbook: the questions one decision asks of the ones before it.
import 'dart:convert';

import 'package:checked_json/checked_json.dart' show JsonObject;
import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId, UserSaid;
import 'package:docking_station_service/docking_station_service.dart';
import 'package:is_admission_vocabulary/is_admission_vocabulary.dart';
import 'package:is_logbook_client/is_logbook_client.dart' show ObjectId;
import 'package:is_shapes/is_shapes.dart'
    show ActorId, DecidedBy, MissionId, TrajectoryId;
import 'package:test/test.dart';

final class _All implements DecidesWhichAddressStartsAMission, TurnRule {
  @override
  JsonObject takeIn(AdmissibleEvent first) =>
      const JsonObject.of({'tools': 'all'});

  @override
  bool startsTurn(MessageSaid said, AdmittedPlacement placement) => true;
}

/// Starts a turn only for something said that says `@agent`.
final class _Mentions implements TurnRule {
  @override
  bool startsTurn(MessageSaid said, AdmittedPlacement placement) =>
      said.node.text.contains('@agent');
}

ObjectId _hash(String s) => ObjectId.of(utf8.encode(s));

void main() {
  test('every duplicate names the first event with its key, not the copy '
      'before it', () {
    final said = MessageSaid(
      addressInExternalSystem: AddressInExternalSystem.parse('test:chat')!,
      containingAddress: null,
      addressedTo: null,
      key: EventKey.parse('message:1')!,
      node: UserSaid(
        author: ActorId.parse('teams:t/p')!,
        source: SourceMessageId.parse('chat|1')!,
        text: 'hello',
      ),
    );
    final decided = DecidedSoFar();
    final events = [for (final name in 'ABCD'.split('')) _hash(name)];
    final ofs = <ObjectId>[];
    for (final (i, event) in events.indexed) {
      final decision = decide(
        event,
        said,
        decided,
        missions: _All(),
        turns: _All(),
      );
      if (decision case DuplicateEvent(:final of)) ofs.add(of);
      decided.take(_hash('decision $i'), decision);
    }
    // A third copy is where naming the copy before shows: two copies name
    // the first either way.
    expect(ofs, [events[0], events[0], events[0]]);
  });

  test('something said that starts no turn is context on a trajectory already '
      'started, and never starts one', () {
    final chat = AddressInExternalSystem.parse('test:chat')!;
    final decided = DecidedSoFar();
    AdmissionDecision step(String key, String text) {
      final decision = decide(
        _hash(key),
        MessageSaid(
          addressInExternalSystem: chat,
          containingAddress: null,
          addressedTo: null,
          key: EventKey.parse(key)!,
          node: UserSaid(
            author: ActorId.parse('teams:t/p')!,
            source: SourceMessageId.parse('chat|$key')!,
            text: text,
          ),
        ),
        decided,
        missions: _All(),
        turns: _Mentions(),
      );
      decided.take(_hash('decision $key'), decision);
      return decision;
    }

    expect(step('a', 'morning all'), isA<SaidStartsNoTurn>());
    final started = step('b', '@agent hello') as EventAdmittedToMission;
    expect(started.placement, isA<StartsTrajectory>());
    expect(started.startsTurn, isTrue);
    final context = step('c', 'lunch?') as EventAdmittedToMission;
    expect(
      context.placement,
      isA<OnTrajectory>().having(
        (p) => p.trajectory.hex,
        'trajectory',
        _hash('decision b').hex,
      ),
    );
    expect(context.startsTurn, isFalse);
    expect(context.rules, isNull);
  });

  test('a trajectory started in a mission already admitted records the rules '
      'the mission was admitted under, without asking the rule again', () {
    final channel = AddressInExternalSystem.parse('test:channel')!;
    MessageSaid said(String thread, String key) => MessageSaid(
      addressInExternalSystem: AddressInExternalSystem.parse(
        'test:channel;$thread',
      )!,
      containingAddress: channel,
      addressedTo: null,
      key: EventKey.parse(key)!,
      node: UserSaid(
        author: ActorId.parse('teams:t/p')!,
        source: SourceMessageId.parse('$thread|$key')!,
        text: 'hi',
      ),
    );
    final rule = _Counting();
    final decided = DecidedSoFar();
    final first = decide(
      _hash('A'),
      said('t1', 'a'),
      decided,
      missions: rule,
      turns: _All(),
    );
    decided.take(_hash('decision A'), first);
    final second = decide(
      _hash('B'),
      said('t2', 'b'),
      decided,
      missions: rule,
      turns: _All(),
    );
    expect(rule.asked, 1);
    expect(
      (first as EventAdmittedToMission).placement,
      isA<StartsTrajectory>(),
    );
    final placement = (second as EventAdmittedToMission).placement;
    expect(
      placement,
      isA<StartsTrajectory>().having(
        (p) => p.mission,
        'mission',
        isA<InMission>().having(
          (j) => j.mission,
          'mission',
          MissionId.parse(_hash('decision A').hex),
        ),
      ),
    );
    expect(second.rules?.asUncheckedMap(), {'asked': 1});
  });

  test('after a mission ends, its address starts a new trajectory in the '
      'same mission, under the same rules', () {
    final channel = AddressInExternalSystem.parse('test:channel')!;
    MessageSaid said(String key) => MessageSaid(
      addressInExternalSystem: AddressInExternalSystem.parse(
        'test:channel;t1',
      )!,
      containingAddress: channel,
      addressedTo: null,
      key: EventKey.parse(key)!,
      node: UserSaid(
        author: ActorId.parse('teams:t/p')!,
        source: SourceMessageId.parse('t1|$key')!,
        text: 'hi',
      ),
    );
    final rule = _Counting();
    final decided = DecidedSoFar();
    AdmissionDecision step(String key) {
      final decision = decide(
        _hash(key),
        said(key),
        decided,
        missions: rule,
        turns: _All(),
      );
      decided.take(_hash('decision $key'), decision);
      return decision;
    }

    final first = step('a') as EventAdmittedToMission;
    final mission = MissionId.parse(_hash('decision a').hex)!;
    expect(
      step('b'),
      isA<EventAdmittedToMission>().having(
        (a) => a.placement,
        'placement',
        isA<OnTrajectory>(),
      ),
    );
    decided.take(
      _hash('end'),
      MissionEnded(
        _hash('asked to end'),
        by: DecidedBy.person,
        mission: mission,
      ),
    );
    final again = step('c') as EventAdmittedToMission;
    expect(
      again.placement,
      isA<StartsTrajectory>().having(
        (p) => p.mission,
        'mission',
        isA<InMission>().having((j) => j.mission, 'mission', mission),
      ),
    );
    expect(again.rules?.asUncheckedMap(), first.rules?.asUncheckedMap());
    expect(rule.asked, 1);
  });

  test('a close closes only its thread\'s trajectory; the thread\'s next '
      'message starts a new one in the same mission', () {
    final channel = AddressInExternalSystem.parse('test:channel')!;
    AddressInExternalSystem thread(String t) =>
        AddressInExternalSystem.parse('test:channel;$t')!;
    final decided = DecidedSoFar();
    AdmissionDecision step(String key, AddressedEvent reading) {
      final decision = decide(
        _hash(key),
        reading,
        decided,
        missions: _All(),
        turns: _All(),
      );
      decided.take(_hash('decision $key'), decision);
      return decision;
    }

    AdmissionDecision say(String t, String key) => step(
      key,
      MessageSaid(
        addressInExternalSystem: thread(t),
        containingAddress: channel,
        addressedTo: null,
        key: EventKey.parse(key)!,
        node: UserSaid(
          author: ActorId.parse('teams:t/p')!,
          source: SourceMessageId.parse('$t|$key')!,
          text: 'hi',
        ),
      ),
    );
    AdmissionDecision close(String t, String key) => step(
      key,
      PersonAskedToCloseTrajectory(
        addressInExternalSystem: thread(t),
        containingAddress: channel,
        addressedTo: null,
        from: ActorId.parse('teams:t/q')!,
        key: EventKey.parse(key)!,
        message: SourceMessageId.parse('$t|card')!,
      ),
    );
    TrajectoryId started(String key) =>
        TrajectoryId.parse(_hash('decision $key').hex)!;

    say('t1', 'a');
    final mission = MissionId.parse(_hash('decision a').hex)!;
    say('t2', 'b');

    expect(
      close('t1', 'c'),
      isA<TrajectoryClosed>()
          .having((c) => c.trajectory, 'trajectory', started('a'))
          .having((c) => c.mission, 'mission', mission)
          .having((c) => c.reading.from.value, 'who asked', 'teams:t/q'),
    );
    expect(
      (say('t2', 'd') as EventAdmittedToMission).placement,
      isA<OnTrajectory>().having((p) => p.trajectory, 'the same', started('b')),
    );
    expect(
      close('t1', 'e'),
      isA<CloseAskedAtAddressWithNoTrajectory>(),
      reason: 'closed already',
    );
    expect(close('t1', 'c'), isA<DuplicateEvent>());
    expect(
      (say('t1', 'f') as EventAdmittedToMission).placement,
      isA<StartsTrajectory>().having(
        (p) => p.mission,
        'mission',
        isA<InMission>().having((m) => m.mission, 'mission', mission),
      ),
    );
    expect(close('t3', 'g'), isA<CloseAskedAtAddressWithNoTrajectory>());
  });
}

/// Takes every mission in, under rules that say how many times it was
/// asked.
final class _Counting implements DecidesWhichAddressStartsAMission {
  var asked = 0;

  @override
  JsonObject takeIn(AdmissibleEvent first) => JsonObject.of({'asked': ++asked});
}
