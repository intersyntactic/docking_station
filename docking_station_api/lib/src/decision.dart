/// What the docking station decides about each event, each sent to the logbook
/// as an entry of its own (RULINGS, "The docking station admits events under
/// trajectories").
///
/// Every event is decided exactly once: [EventAdmittedToMission] under a
/// trajectory, or [EventNotAdmittedToMission], saying why. A decline is
/// recorded as well as an admission, so on a restart the docking station reads
/// back what it decided rather than deciding again. An event with no decision
/// is one it had not reached, never one it turned away, so a translator or a
/// rule changed since cannot admit an old event it once kept out.
///
/// The decisions are one chain in the logbook, each naming the one before it
/// as previous. The logbook refuses an entry whose previous is not its
/// chain's tip, so two docking stations that each believe they hold the
/// chain cannot both decide one event: the second is refused, reads the
/// first one's decision back, and goes on. "None is admitted twice" is the
/// logbook's guarantee, not a set one process keeps. It holds for the first
/// decision too, since its previous is the start entry rather than none: the
/// logbook starts a new chain for any entry with no previous, so two docking
/// stations making a first decision with none would start two.
///
/// Each decision holds what it was decided on (the address, the
/// event's key, the message), so the docking station's state is rebuilt from
/// its decisions alone, whatever a module's translator would make of an old
/// event now.
library;

import 'package:checked_json/checked_json.dart' show JsonObject;
import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId;
import 'package:is_logbook_format/is_logbook_format.dart' show Kind, ObjectId;
import 'package:is_shapes/is_shapes.dart'
    show ActorId, DecidedBy, MissionId, TrajectoryId;

import 'package:is_reply_vocabulary/is_reply_vocabulary.dart'
    show ReplyEndpoint;

import 'translated_event.dart';

/// The kinds of entry the docking station sends, one per event. Its user's
/// row in the logbook's sender table allows these four and nothing else.
abstract final class DecisionEntryKind {
  /// An [EventAdmittedToMission]'s kind.
  static final eventAdmittedToMission = Kind.parse(
    'event-admitted-to-mission',
  )!;

  /// A [EventNotAdmittedToMission]'s kind.
  static final eventNotAdmittedToMission = Kind.parse(
    'event-not-admitted-to-mission',
  )!;

  /// A [MissionEnded]'s kind: the logbook's own, since the logbook reads it
  /// to close the mission's chains.
  static final missionEnded = Kind.missionEnded;

  /// A [TrajectoryClosed]'s kind: the logbook's own, since the logbook reads
  /// it to close the trajectory's chains.
  static final trajectoryClosed = Kind.trajectoryClosed;

  /// Every kind above, as the docking station subscribes to its own
  /// decisions.
  static final all = {
    eventAdmittedToMission,
    eventNotAdmittedToMission,
    missionEnded,
    trajectoryClosed,
  };
}

/// Where an admitted event goes. Something said, or a change, goes
/// [OnTrajectory] a trajectory already started, or
/// [StartsTrajectory], a new one its admission starts. A join goes
/// [IntoMission]: it says who is in a mission, and is under none of its
/// trajectories.
sealed class AdmittedPlacement {
  const AdmittedPlacement();
}

/// Under [trajectory], in the mission it was started in.
final class OnTrajectory extends AdmittedPlacement {
  const OnTrajectory(this.trajectory);

  final TrajectoryId trajectory;
}

/// Under a new trajectory in [mission], which the admission starts and is named
/// by: its id is the hash of the `event-admitted-to-mission` entry that started
/// it. A [TrajectoryId] is given by whoever starts the trajectory, and here
/// that is the docking station, so the entry that started it is its one name,
/// the way a turn's id is the hash of its entry.
final class StartsTrajectory extends AdmittedPlacement {
  const StartsTrajectory(this.mission);

  final MissionPlacement mission;
}

/// Into [mission]: a join, which is about who is in it.
final class IntoMission extends AdmittedPlacement {
  const IntoMission(this.mission);

  final MissionPlacement mission;
}

/// Which mission: [InMission], one already started, or [StartsMission], a new
/// one the admission starts. A mission the docking station starts is named like
/// a trajectory it starts, by the `event-admitted-to-mission` entry's hash, as
/// a [MissionId]. One entry can start both, as a chat's first message does, and
/// then both have its hash, as two kinds of name.
sealed class MissionPlacement {
  const MissionPlacement();
}

/// In [mission], already started.
final class InMission extends MissionPlacement {
  const InMission(this.mission);

  final MissionId mission;
}

/// In a new mission, which the admission starts.
final class StartsMission extends MissionPlacement {
  const StartsMission();
}

/// What the docking station decided, and [by] whom, so the logbook tells "the
/// rules let it through" from "the person said yes", as the airlock's does.
///
/// Every entry says who, as `"by": <who>`, where `<who>` is `rules` or
/// `person`. Every decision but [TrajectoryClosedByOperator] is decided at an
/// event, and is a [DecidedAtEvent].
sealed class AdmissionDecision {
  const AdmissionDecision({required this.by});

  /// Who decided it.
  final DecidedBy by;
}

/// A decision about the event recorded at [event].
sealed class DecidedAtEvent implements AdmissionDecision {
  /// The event decided, by its entry's hash.
  ObjectId get event;
}

/// [event], translated as [translatedEvent], admitted by [placement].
///
/// The entry, of kind `event-admitted-to-mission`:
///
///     {"event": <hex>, "by": <who>, "translatedEvent": <translated event>,
///      ...the placement, "rules": <rules>?,
///      "replyEndpoint": <address prefix>?, "startsTurn": <bool>?}
///
/// `<translated event>` is the whole of it, as [encodeTranslatedEvent] writes
/// it, so whatever hands
/// the event to its trajectory's crux reads the node from the decision, and
/// never reads a module's bytes. The placement is `"trajectory": <id>` for
/// [OnTrajectory]; `"startsTrajectory": true` and the mission for
/// [StartsTrajectory]; the mission alone for [IntoMission]. The mission is
/// `"mission": <id>` for [InMission], or `"startsMission": true` for
/// [StartsMission].
///
/// [rules] are there exactly when the admission starts a mission or a
/// trajectory: the rules the mission was admitted under, as the docking
/// station's rule for which address starts a mission gave them, copied into
/// each trajectory it starts. loop_launcher reads a trajectory's rules from the
/// entry that started it, and the airlock enforces them; the docking station
/// passes them through unread.
///
/// [startsTurn] is there exactly when the event is [MessageSaid]: whether the
/// agent answers it, as the docking station's turn rule said. Something said
/// that starts no turn is still admitted under its address's trajectory, so the
/// agent has it as context. It never starts a trajectory, since a trajectory
/// brings up an agent loop: one that starts no turn where its address has no
/// trajectory yet is [SaidStartsNoTurn].
///
/// The event's [containingAddress] is kept so which mission an address in an
/// external system is can be rebuilt from decisions alone; its [from], for
/// rules about who starts turns, such as a cap on turns bots start.
final class EventAdmittedToMission extends AdmissionDecision
    implements DecidedAtEvent {
  /// Throws an [ArgumentError] when [rules] are given for an admission
  /// that starts nothing, or missing for one that starts something; when
  /// [startsTurn] is given for anything but something said, or missing for
  /// something said; and when something said starts a trajectory but no
  /// turn.
  EventAdmittedToMission(
    this.event, {
    required super.by,
    required this.translatedEvent,
    required this.placement,
    this.rules,
    this.startsTurn,
  }) {
    if ((rules != null) != starts(placement)) {
      throw ArgumentError.value(
        rules,
        'rules',
        'given exactly when the admission starts a mission or a trajectory',
      );
    }
    if ((startsTurn != null) != (translatedEvent is MessageSaid)) {
      throw ArgumentError.value(
        startsTurn,
        'startsTurn',
        'given exactly when the event is something said',
      );
    }
    if (placement is StartsTrajectory && startsTurn == false) {
      throw ArgumentError.value(
        startsTurn,
        'startsTurn',
        'something said that starts no turn starts no trajectory',
      );
    }
  }

  @override
  final ObjectId event;
  final AdmissibleEvent translatedEvent;
  final AdmittedPlacement placement;
  final JsonObject? rules;

  /// Whether the agent answers it: for something said, and null for
  /// anything else.
  final bool? startsTurn;

  /// Whether [placement] starts a trajectory or a mission.
  static bool starts(AdmittedPlacement placement) => switch (placement) {
    StartsTrajectory() || IntoMission(mission: StartsMission()) => true,
    OnTrajectory() || IntoMission(mission: InMission()) => false,
  };

  /// Where replies go, on an admission that starts a mission or a
  /// trajectory: [translatedEvent]'s endpoint, copied to the entry's top
  /// level beside [rules] so a reader of a trajectory's start, such as the
  /// airlock, has it without decoding the translated event. Null on any
  /// other admission, and when the module named none.
  ReplyEndpoint? get replyEndpoint =>
      starts(placement) ? translatedEvent.replyEndpoint : null;

  AddressInExternalSystem get addressInExternalSystem =>
      translatedEvent.addressInExternalSystem;
  AddressInExternalSystem? get containingAddress =>
      translatedEvent.containingAddress;
  EventKey get key => translatedEvent.key;
  ActorId? get from => translatedEvent.from;

  /// The message it says, changes or judges; null for a join.
  SourceMessageId? get message => switch (translatedEvent) {
    MessageSaid(:final message) || MessageChanged(:final message) => message,
    ShownMessageJudged(:final to) => to,
    ActorsJoinedAddress() => null,
  };
}

/// [mission] ended, at [event]: its loops stop, its programs close and its
/// users are freed (loop_launcher), and the logbook takes nothing more on its
/// trajectories' chains (is_logbook). The person's next message in it opens it
/// again, on a new trajectory (RULINGS).
///
/// The docking station ends missions; the agent has no tool that does. What
/// event ends one is not decided yet, so nothing decides one yet; it is read
/// back like any other decision.
///
/// The entry, of kind `mission-ended`:
///
///     {"event": <hex>, "by": <who>, "mission": <id>}
final class MissionEnded extends AdmissionDecision implements DecidedAtEvent {
  const MissionEnded(this.event, {required super.by, required this.mission});

  @override
  final ObjectId event;
  final MissionId mission;
}

/// [trajectory], in [mission], closed: its loop stops and its users are freed
/// (loop_launcher), and the logbook takes nothing more on its chains
/// (is_logbook). The next message at its address starts a new trajectory, in
/// the same mission. The case says who closed it.
///
/// The entry, of kind `trajectory-closed`, is one of the cases' below. The
/// logbook reads its `trajectory` to close the chains, whichever case it is.
sealed class TrajectoryClosed extends AdmissionDecision {
  const TrajectoryClosed({
    required super.by,
    required this.trajectory,
    required this.mission,
  });

  final TrajectoryId trajectory;
  final MissionId mission;
}

/// Closed at [event], because a person at its address asked
/// ([translatedEvent]).
///
/// Anyone at the address may close it, so it is decided [DecidedBy.rules],
/// and [translatedEvent] says who asked.
///
///     {"event": <hex>, "by": <who>, "translatedEvent": <translated event>,
///      "trajectory": <id>, "mission": <id>}
final class TrajectoryClosedBecausePersonAsked extends TrajectoryClosed
    implements DecidedAtEvent {
  const TrajectoryClosedBecausePersonAsked(
    this.event, {
    required super.by,
    required this.translatedEvent,
    required super.trajectory,
    required super.mission,
  });

  @override
  final ObjectId event;
  final PersonAskedToCloseTrajectory translatedEvent;
}

/// Closed by [operator], a person running the docking station's close
/// command on its machine, from outside the trajectory's conversation, for
/// [reason]. No event caused it, so it names none, and it is decided
/// [DecidedBy.person].
///
///     {"by": "person", "trajectory": <id>, "mission": <id>,
///      "operator": <name>, "reason": <text>}
final class TrajectoryClosedByOperator extends TrajectoryClosed {
  /// Throws an [ArgumentError] when [reason] is blank.
  TrajectoryClosedByOperator({
    required super.trajectory,
    required super.mission,
    required this.operator,
    required this.reason,
  }) : super(by: DecidedBy.person) {
    if (reason.trim().isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'is blank');
    }
  }

  final OperatorName operator;

  /// Why, in the operator's words.
  final String reason;
}

/// The name of a person who operates the docking station's machine, as a
/// user name is written: a lowercase letter or `_`, then up to 31 lowercase
/// letters, digits, `_` and `-`.
final class OperatorName {
  const OperatorName._(this.value);

  final String value;

  static final _name = RegExp(r'^[a-z_][a-z0-9_-]{0,31}$');

  /// [s] as an operator's name; null unless it is one.
  static OperatorName? parse(String s) =>
      _name.hasMatch(s) ? OperatorName._(s) : null;

  @override
  bool operator ==(Object other) =>
      other is OperatorName && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// [event] not admitted to any mission: nothing comes of it, and nothing
/// will, whatever
/// changes later. The case says why.
///
/// The entry, of kind `event-not-admitted-to-mission`:
///
///     {"event": <hex>, "by": <who>, "why": <case>, ...the case's own fields}
///
/// `<case>` is `no-translator-for-source`, `translator-found-nothing`,
/// `duplicate-event`, `address-not-admitted-to-mission`,
/// `said-starts-no-turn`, `judged-message-has-no-trajectory`,
/// `close-asked-for-trajectory-not-open-at-address` or
/// `change-to-unadmitted-message`.
sealed class EventNotAdmittedToMission extends AdmissionDecision
    implements DecidedAtEvent {
  const EventNotAdmittedToMission(this.event, {required super.by});

  @override
  final ObjectId event;
}

/// No translator takes the event's source, or its body is not what a relay
/// records. A source whose module has no translator yet has its events
/// not admitted, so a translator added later starts from the events after it.
final class NoTranslatorForSource extends EventNotAdmittedToMission {
  const NoTranslatorForSource(super.event, {required super.by});
}

/// The module's translator found nothing to admit.
final class TranslatorFoundNothing extends EventNotAdmittedToMission {
  const TranslatorFoundNothing(super.event, {required super.by});
}

/// An event a translator named by its key, not admitted. A key is decided once,
/// whichever way it went, so a second event with the same key is a
/// [DuplicateEvent], even when the first was not admitted.
sealed class NotAdmittedKeyedEvent extends EventNotAdmittedToMission {
  const NotAdmittedKeyedEvent(
    super.event, {
    required super.by,
    required this.addressInExternalSystem,
    required this.key,
  });

  final AddressInExternalSystem addressInExternalSystem;
  final EventKey key;
}

/// [key] in [addressInExternalSystem] was decided already, at the event [of]:
/// its relay recorded one thing twice, as two events with one key.
/// `"of": <hex>`.
final class DuplicateEvent extends NotAdmittedKeyedEvent {
  const DuplicateEvent(
    super.event, {
    required super.by,
    required super.addressInExternalSystem,
    required super.key,
    required this.of,
  });

  final ObjectId of;
}

/// [addressInExternalSystem]'s mission hasn't started, and the docking
/// station's rule for which address starts a mission doesn't start one for
/// it. The next event from it is asked about again.
final class AddressNotAdmittedToMission extends NotAdmittedKeyedEvent {
  const AddressNotAdmittedToMission(
    super.event, {
    required super.by,
    required super.addressInExternalSystem,
    required super.key,
  });
}

/// Something said that the turn rule says starts no turn, in an address
/// with no trajectory yet. Where it has one, it is admitted, with
/// [EventAdmittedToMission.startsTurn] false.
final class SaidStartsNoTurn extends NotAdmittedKeyedEvent {
  const SaidStartsNoTurn(
    super.event, {
    required super.by,
    required super.addressInExternalSystem,
    required super.key,
  });
}

/// A verdict in [addressInExternalSystem], which is under no trajectory, so no
/// turn of the agent's there could have shown what was judged.
final class JudgedMessageHasNoTrajectory extends NotAdmittedKeyedEvent {
  const JudgedMessageHasNoTrajectory(
    super.event, {
    required super.by,
    required super.addressInExternalSystem,
    required super.key,
  });
}

/// A close asked in [addressInExternalSystem] for a trajectory that is not
/// the one open there: it is closed already, or it is another address's,
/// or none is open there.
final class CloseAskedForTrajectoryNotOpenAtAddress
    extends NotAdmittedKeyedEvent {
  const CloseAskedForTrajectoryNotOpenAtAddress(
    super.event, {
    required super.by,
    required super.addressInExternalSystem,
    required super.key,
  });
}

/// A change to [message], which was never admitted, or was admitted in a
/// mission since ended or a trajectory since closed, so there is no turn
/// for it to change.
/// `"message": <source>`.
final class ChangeToUnadmittedMessage extends NotAdmittedKeyedEvent {
  const ChangeToUnadmittedMessage(
    super.event, {
    required super.by,
    required super.addressInExternalSystem,
    required super.key,
    required this.message,
  });

  final SourceMessageId message;
}
