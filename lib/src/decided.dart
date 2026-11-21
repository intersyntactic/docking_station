/// What the docking station has decided, rebuilt from its own decisions
/// alone, read back from the record in order (RULINGS: which address
/// is under which trajectory "is rebuilt by reading its own decisions
/// back, not by working them out again").
library;

import 'package:checked_json/checked_json.dart' show JsonObject;
import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId;
import 'package:is_logbook_client/is_logbook_client.dart' show ObjectId;
import 'package:is_shapes/is_shapes.dart' show MissionId, TrajectoryId;

import 'package:is_admission_vocabulary/is_admission_vocabulary.dart';

/// Every decision so far, as the questions deciding the next event asks.
///
/// How it is used: the docking station subscribes to the record's events and
/// its own `event-admitted-to-mission` and `event-not-admitted-to-mission`
/// entries from the record's start. It folds each event through its module's
/// reading and [take]s each decision. At `caught-up` it decides, in order, each
/// event that has no decision. Those are only ever the last few, because it
/// records each decision before deciding the next. Then it decides each new
/// event as it comes. Each decision is sent naming [tip] as previous. A
/// `not-tip` refusal means another docking station decided first, and its
/// decision comes on the record to be taken like any other.
final class DecidedSoFar {
  ObjectId? _tip;
  final _taken = <ObjectId>{};
  final _decidedEvents = <ObjectId>{};
  final _events = <(AddressInExternalSystem, EventKey), ObjectId>{};
  final _trajectories = <AddressInExternalSystem, TrajectoryId>{};
  final _trajectoryMissions = <TrajectoryId, MissionId>{};
  final _missions = <AddressInExternalSystem, MissionId>{};
  final _rules = <MissionId, JsonObject>{};
  final _messages =
      <(AddressInExternalSystem, SourceMessageId), TrajectoryId>{};

  /// The last decision: what the next one names as previous. Null before the
  /// first.
  ObjectId? get tip => _tip;

  /// Whether [event] has been decided.
  bool has(ObjectId event) => _decidedEvents.contains(event);

  /// The event that [key] in [addressInExternalSystem] was decided at,
  /// whichever way it went. Null when no event with that key has been decided.
  ObjectId? decidedAt(
    AddressInExternalSystem addressInExternalSystem,
    EventKey key,
  ) => _events[(addressInExternalSystem, key)];

  /// The trajectory [addressInExternalSystem] is under. Null when it is under
  /// none yet.
  TrajectoryId? trajectoryOf(AddressInExternalSystem addressInExternalSystem) =>
      _trajectories[addressInExternalSystem];

  /// The mission [outside] is: an address others sit within, such as a
  /// channel, or one that sits within nothing, such as a chat. Null before
  /// it starts.
  MissionId? missionOf(AddressInExternalSystem outside) => _missions[outside];

  /// The rules [mission] was admitted under. Only for a mission that
  /// [missionOf] has given, since every entry that starts one records them.
  JsonObject rulesOf(MissionId mission) => _rules[mission]!;

  /// The mission [trajectory] was started in. Only for a trajectory that
  /// [trajectoryOf] has given, since the entry that starts one names its
  /// mission.
  MissionId missionOfTrajectory(TrajectoryId trajectory) =>
      _trajectoryMissions[trajectory]!;

  /// The trajectory the message [message] in [addressInExternalSystem] was
  /// admitted under: where a change to it goes. Null when it was never
  /// admitted.
  TrajectoryId? trajectoryOfMessage(
    AddressInExternalSystem addressInExternalSystem,
    SourceMessageId message,
  ) => _messages[(addressInExternalSystem, message)];

  /// Takes in [decision], recorded at [entry]. An [EventAdmittedToMission] that
  /// starts a trajectory or a mission names it by [entry].
  ///
  /// An entry already taken is ignored, so the docking station's own decision,
  /// taken when the record accepts it and read back later, can never move
  /// [tip] back.
  void take(ObjectId entry, AdmissionDecision decision) {
    if (!_taken.add(entry)) return;
    _tip = entry;
    _decidedEvents.add(decision.event);
    switch (decision) {
      case EventAdmittedToMission():
        _admit(entry, decision);
      // The first event with a key keeps it, so every duplicate after names
      // that one, never the copy before it.
      case NotAdmittedKeyedEvent(
        :final addressInExternalSystem,
        :final key,
        :final event,
      ):
        _events.putIfAbsent((addressInExternalSystem, key), () => event);
      case MissionEnded(:final mission):
        _forget({
          for (final MapEntry(key: trajectory, value: of)
              in _trajectoryMissions.entries)
            if (of == mission) trajectory,
        });
      case TrajectoryClosed(:final reading, :final trajectory):
        _events[(reading.addressInExternalSystem, reading.key)] =
            decision.event;
        _forget({trajectory});
      case NoReadingForSource() || ReadingFoundNothing():
        break;
    }
  }

  /// Forgets [closed], trajectories whose chains the record now closes, and
  /// the messages admitted under them. Their addresses then start new
  /// trajectories, in the same missions, and a change to a message admitted
  /// before is a change to one never admitted.
  void _forget(Set<TrajectoryId> closed) {
    _trajectories.removeWhere((_, trajectory) => closed.contains(trajectory));
    _messages.removeWhere((_, trajectory) => closed.contains(trajectory));
    _trajectoryMissions.removeWhere(
      (trajectory, _) => closed.contains(trajectory),
    );
  }

  void _admit(ObjectId entry, EventAdmittedToMission admitted) {
    final EventAdmittedToMission(:addressInExternalSystem, :key, :message) =
        admitted;
    _events[(addressInExternalSystem, key)] = admitted.event;
    final outside = admitted.containingAddress ?? addressInExternalSystem;

    MissionId mission(MissionPlacement placement) => switch (placement) {
      InMission(:final mission) => mission,
      StartsMission() => _start(entry, outside, admitted.rules!),
    };

    final TrajectoryId? on;
    switch (admitted.placement) {
      case OnTrajectory(:final trajectory):
        on = trajectory;
      case StartsTrajectory(mission: final placement):
        final started = on = TrajectoryId.parse(entry.hex)!;
        _trajectories[addressInExternalSystem] = started;
        _trajectoryMissions[started] = mission(placement);
      case IntoMission(mission: final placement):
        mission(placement);
        on = null;
    }
    if ((on, message) case (final trajectory?, final message?)) {
      _messages[(addressInExternalSystem, message)] = trajectory;
    }
  }

  /// Starts the mission [outside] is, named by [entry], under [rules].
  MissionId _start(
    ObjectId entry,
    AddressInExternalSystem outside,
    JsonObject rules,
  ) {
    final mission = _missions[outside] = MissionId.parse(entry.hex)!;
    _rules[mission] = rules;
    return mission;
  }
}
