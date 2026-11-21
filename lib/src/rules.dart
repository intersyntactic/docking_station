/// The rules the docking station decides by, passed in: whether an address
/// in an external system comes in at all, and whether something said
/// starts a turn. Both are calls still open, so neither is written here.
///
/// Where an event goes is not a rule. An address goes under a trajectory of
/// its own, in the mission of what it sits within, or its own mission when
/// it sits within nothing (Nick, 2026-11-15: "channel = journey, thread =
/// journey path", since renamed mission and trajectory). A change goes
/// where the message it changes went; a verdict goes under its address's
/// trajectory, since what it judges was shown there.
///
/// A rule is asked at most once per event, in the record's order, and what
/// it answered is kept in the decision, never asked again on a restart. So
/// a rule can change between restarts without changing anything it already
/// decided.
library;

import 'package:checked_json/checked_json.dart' show JsonObject;

import 'package:is_admission_vocabulary/is_admission_vocabulary.dart';

/// Whether an address in an external system whose mission hasn't started
/// comes in. Asked for the first admissible event of the address a mission
/// is: what threads sit within, or an address that sits within nothing,
/// such as a chat. Once it has come in, the addresses within it come in
/// with it, without asking.
abstract interface class JourneyRule {
  /// The rules [first]'s mission is admitted under, or null when it isn't
  /// admitted. Then [first] is [AddressNotAdmittedToMission], and the
  /// address's next event is asked about again.
  ///
  /// The rules are what the airlock enforces on each of the mission's
  /// trajectories, and the docking station never reads them: it records
  /// them in the entry that starts the mission, and copies them into each
  /// entry that starts one of its trajectories, where loop_launcher reads
  /// them (Nick, 16 Nov: the entry that starts a trajectory records its
  /// rules).
  JsonObject? takeIn(AdmissibleEvent first);
}

/// Whether something said starts a turn: a person's turn, in a
/// trajectory's terms, which the agent then takes its own turn in answer to.
abstract interface class TurnRule {
  /// Whether [said] starts a turn under [placement]. When it doesn't, it is
  /// admitted as context, with [EventAdmittedToMission.startsTurn] false, on a
  /// trajectory already started; where it would have started one, it is
  /// [SaidStartsNoTurn], and nothing it would have started is started.
  bool startsTurn(MessageSaid said, AdmittedPlacement placement);
}
