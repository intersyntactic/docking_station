/// An operator closing a trajectory from outside its conversation: one
/// [TrajectoryClosedByOperator], sent on the docking station's chain of
/// decisions.
library;

import 'package:is_admission_vocabulary/is_admission_vocabulary.dart';
import 'package:is_logbook_client/is_logbook_client.dart'
    show
        AlreadyRecorded,
        CaughtUp,
        Entry,
        Kind,
        NotTip,
        ObjectId,
        Subscribed,
        Unanswered,
        WriteFailed,
        WriteRefused,
        WriteResult,
        Written;
import 'package:is_shapes/is_shapes.dart' show TrajectoryId;

import 'decided.dart';

/// How [closeTrajectoryByOperator] ended.
sealed class OperatorCloseOutcome {
  const OperatorCloseOutcome();
}

/// The close is in the logbook, at [entry].
final class OperatorClosedTrajectory extends OperatorCloseOutcome {
  const OperatorClosedTrajectory(this.entry, this.decision);

  final ObjectId entry;
  final TrajectoryClosedByOperator decision;
}

/// The docking station's decisions hold no open trajectory by that id: it
/// was never started, or is closed already, or its mission ended.
final class NoOpenTrajectory extends OperatorCloseOutcome {
  const NoOpenTrajectory();
}

/// The logbook has no start entry yet, so the docking station has decided
/// nothing and no trajectory is open.
final class NoStartEntry extends OperatorCloseOutcome {
  const NoStartEntry();
}

/// Nothing was sent, or what was sent is not in: the logbook refused it, an
/// entry on the chain could not be read, or the chain kept moving. [why]
/// says which.
final class OperatorCloseNotSent extends OperatorCloseOutcome {
  const OperatorCloseNotSent(this.why);

  final String why;
}

/// The close was sent but no answer said whether it is in. Running the
/// command again reads it back: a trajectory it closed is no longer open.
final class OperatorCloseMayOrMayNotBeIn extends OperatorCloseOutcome {
  const OperatorCloseMayOrMayNotBeIn(this.why);

  final String why;
}

/// Closes [trajectory] as [operator], for [reason].
///
/// It reads the docking station's decisions from the logbook's start with
/// [subscribe] until caught up, into a [DecidedSoFar], and takes the
/// trajectory's mission from them, so nothing is closed that the docking
/// station does not hold open. It then sends the close with [send], naming
/// the last decision as previous, or the start entry, the one entry of
/// [startKind], when there is none. So the close is one more link in the
/// docking station's own chain, and the running docking station reads it
/// back like any decision and forgets the trajectory.
///
/// The running docking station may decide an event between the read and the
/// send. The logbook then answers [NotTip], and the close reads the chain
/// again and tries again, up to [attempts] times; the docking station meets
/// the same answer when the close goes first, and reads the close back. So
/// neither has to stop for the other.
Future<OperatorCloseOutcome> closeTrajectoryByOperator({
  required Stream<Subscribed> Function(Set<Kind> kinds) subscribe,
  required Future<WriteResult> Function(
    Kind kind,
    List<int> body, {
    ObjectId? previous,
  })
  send,
  required Kind startKind,
  required TrajectoryId trajectory,
  required OperatorName operator,
  required String reason,
  int attempts = 5,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    final decided = DecidedSoFar();
    ObjectId? start;
    await for (final item in subscribe({...DecisionEntryKind.all, startKind})) {
      switch (item) {
        case Entry(:final id, :final kind) when kind == startKind:
          start ??= id;
        case Entry(:final id, :final kind, :final body):
          final decision = decodeDecision(kind, body);
          if (decision == null) {
            return OperatorCloseNotSent('cannot read the decision ${id.hex}');
          }
          decided.take(id, decision);
        case CaughtUp():
          break;
      }
      if (item is CaughtUp) break;
    }
    final previous = decided.tip ?? start;
    if (previous == null) return const NoStartEntry();
    final mission = decided.missionOfOpenTrajectory(trajectory);
    if (mission == null) return const NoOpenTrajectory();

    final decision = TrajectoryClosedByOperator(
      trajectory: trajectory,
      mission: mission,
      operator: operator,
      reason: reason,
    );
    final (kind, body) = encodeDecision(decision);
    switch (await send(kind, body, previous: previous)) {
      case Written(:final entry) || AlreadyRecorded(:final entry):
        return OperatorClosedTrajectory(entry, decision);
      case NotTip():
        continue;
      case WriteRefused(:final why):
        return OperatorCloseNotSent('the logbook refused it: $why');
      case WriteFailed(:final why) || Unanswered(:final why):
        return OperatorCloseMayOrMayNotBeIn(why);
    }
  }
  return OperatorCloseNotSent(
    'the decisions\' chain moved on $attempts times before the close got in',
  );
}
