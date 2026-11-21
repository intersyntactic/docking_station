/// Deciding one event: whether it comes in, and where it goes.
library;

import 'package:checked_json/checked_json.dart' show JsonObject;
import 'package:is_logbook_client/is_logbook_client.dart' show ObjectId;
import 'package:is_shapes/is_shapes.dart' show DecidedBy;

import 'package:is_admission_vocabulary/is_admission_vocabulary.dart';

import 'decided.dart';
import 'rules.dart';

/// What the docking station decides about the event recorded at [event], read
/// by its module's reading as [reading], given everything [decided] so
/// far. [reading] is null when no reading takes the event's source, or its
/// body is not what a relay records.
///
/// In order: an event whose key was decided already is a [DuplicateEvent]. A
/// close closes its address's trajectory. A change goes where the message it
/// changes went, and a verdict under its address's trajectory. A join goes
/// into its mission, and something said under its address's trajectory,
/// marked with whether the turn rule says it starts a turn, or under a new
/// one when it does. A mission not yet started is started only when
/// [missions] takes it in.
///
/// Every decision it makes is [DecidedBy.rules]: nothing here asks the
/// person.
AdmissionDecision decide(
  ObjectId event,
  EventReading? reading,
  DecidedSoFar decided, {
  required JourneyRule missions,
  required TurnRule turns,
}) {
  const by = DecidedBy.rules;
  final AddressedEvent addressed;
  switch (reading) {
    case null:
      return NoReadingForSource(event, by: by);
    case NothingToAdmit():
      return ReadingFoundNothing(event, by: by);
    case AddressedEvent():
      addressed = reading;
  }
  final AddressedEvent(:addressInExternalSystem, :key) = addressed;
  if (decided.decidedAt(addressInExternalSystem, key) case final first?) {
    return DuplicateEvent(
      event,
      by: by,
      addressInExternalSystem: addressInExternalSystem,
      key: key,
      of: first,
    );
  }

  final AdmissibleEvent admissible;
  switch (addressed) {
    case PersonAskedToCloseTrajectory():
      return switch (decided.trajectoryOf(addressInExternalSystem)) {
        final trajectory? => TrajectoryClosed(
          event,
          by: by,
          reading: addressed,
          trajectory: trajectory,
          mission: decided.missionOfTrajectory(trajectory),
        ),
        null => CloseAskedAtAddressWithNoTrajectory(
          event,
          by: by,
          addressInExternalSystem: addressInExternalSystem,
          key: key,
        ),
      };
    case AdmissibleEvent():
      admissible = addressed;
  }

  EventAdmittedToMission admit(
    AdmittedPlacement placement, {
    JsonObject? rules,
    bool? startsTurn,
  }) => EventAdmittedToMission(
    event,
    by: by,
    reading: admissible,
    placement: placement,
    rules: rules,
    startsTurn: startsTurn,
  );

  switch (admissible) {
    case MessageChanged(:final message):
      return switch (decided.trajectoryOfMessage(
        addressInExternalSystem,
        message,
      )) {
        final trajectory? => admit(OnTrajectory(trajectory)),
        null => ChangeToUnadmittedMessage(
          event,
          by: by,
          addressInExternalSystem: addressInExternalSystem,
          key: key,
          message: message,
        ),
      };
    case ShownMessageJudged():
      return switch (decided.trajectoryOf(addressInExternalSystem)) {
        final trajectory? => admit(OnTrajectory(trajectory)),
        null => JudgedMessageHasNoTrajectory(
          event,
          by: by,
          addressInExternalSystem: addressInExternalSystem,
          key: key,
        ),
      };
    case ActorsJoinedAddress():
      return switch (_mission(admissible, decided, missions)) {
        (InMission() && final mission, _) => admit(IntoMission(mission)),
        (final mission, final rules) => admit(
          IntoMission(mission),
          rules: rules,
        ),
        null => AddressNotAdmittedToMission(
          event,
          by: by,
          addressInExternalSystem: addressInExternalSystem,
          key: key,
        ),
      };
    case MessageSaid():
      final AdmittedPlacement placement;
      JsonObject? rules;
      if (decided.trajectoryOf(addressInExternalSystem)
          case final trajectory?) {
        placement = OnTrajectory(trajectory);
      } else if (_mission(admissible, decided, missions)
          case (final mission, final missionRules)?) {
        placement = StartsTrajectory(mission);
        rules = missionRules;
      } else {
        return AddressNotAdmittedToMission(
          event,
          by: by,
          addressInExternalSystem: addressInExternalSystem,
          key: key,
        );
      }
      final startsTurn = turns.startsTurn(admissible, placement);
      // Something said that starts no turn still goes under a trajectory that
      // has started, as context; it never starts one, since a trajectory brings
      // up an agent loop with nothing to answer.
      if (!startsTurn && placement is StartsTrajectory) {
        return SaidStartsNoTurn(
          event,
          by: by,
          addressInExternalSystem: addressInExternalSystem,
          key: key,
        );
      }
      return admit(placement, rules: rules, startsTurn: startsTurn);
  }
}

/// The mission [first]'s address goes in, with its rules: the
/// mission of what it sits within (or of itself, when it sits within
/// nothing) when that has started; a new one when [rule] takes it in; null
/// when it doesn't.
(MissionPlacement, JsonObject)? _mission(
  AdmissibleEvent first,
  DecidedSoFar decided,
  JourneyRule rule,
) => switch (decided.missionOf(
  first.containingAddress ?? first.addressInExternalSystem,
)) {
  final mission? => (InMission(mission), decided.rulesOf(mission)),
  null => switch (rule.takeIn(first)) {
    final rules? => (const StartsMission(), rules),
    null => null,
  },
};
