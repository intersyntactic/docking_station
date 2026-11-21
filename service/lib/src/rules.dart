/// The rules the docking station decides by, passed in: whether an address
/// in an external system comes in at all, and whether something said
/// starts a turn. Both are calls still open, so neither is written here.
///
/// Where an event goes is not a rule. An address goes under a trajectory of
/// its own, in the mission of what it sits within, or its own mission when
/// it sits within nothing: a channel is a mission and each of its threads a
/// trajectory. A change goes where the message it changes went; a verdict
/// goes under its address's trajectory, since what it judges was shown
/// there.
///
/// A rule is asked at most once per event, in the record's order, and what
/// it answered is kept in the decision, never asked again on a restart. So
/// a rule can change between restarts without changing anything it already
/// decided.
library;

import 'package:checked_json/checked_json.dart' show JsonObject;

import 'package:is_admission_vocabulary/is_admission_vocabulary.dart';

/// Whether an address in an external system with no mission yet starts one,
/// and the rules it starts under. Asked about the outermost address, the one
/// a mission is: what threads sit within, such as a channel, or an address
/// that sits within nothing, such as a chat. It is asked on that address's
/// first admissible event, and once a mission has started, the addresses
/// within it join it without asking.
abstract interface class DecidesWhichAddressStartsAMission {
  /// The rules [first]'s mission starts under, or null when it starts none.
  /// Then [first] is [AddressNotAdmittedToMission], and the address's next
  /// event is asked about again.
  ///
  /// The rules are what the airlock enforces on each of the mission's
  /// trajectories, and the docking station never reads them: it records
  /// them in the entry that starts the mission, and copies them into each
  /// entry that starts one of its trajectories, where loop_launcher reads
  /// them.
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
