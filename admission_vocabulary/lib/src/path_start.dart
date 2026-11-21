/// Reading an `event-admitted-to-mission` entry for the trajectory it starts
/// and that trajectory's rules, and nothing else: for the airlock, which
/// enforces each trajectory's rules and learns them from the record (RULINGS,
/// "the loop launcher records itself").
///
/// The entry's `reading` is what strangers sent, made into a node. The
/// airlock has no need of it, so it is checked to be an object naming its
/// case and is never decoded: nothing here imports the packages that
/// decode it, and a test holds that. Every other field is read as
/// strictly as `decodeDecision` reads it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:is_logbook/is_logbook.dart' show ObjectId;
import 'package:is_shapes/is_shapes.dart'
    show DecidedBy, MissionId, TrajectoryId;

/// What an `event-admitted-to-mission` entry says about the trajectories it
/// starts: [EntryStartsTrajectory], [EntryStartsNoTrajectory], or
/// [UnreadableTrajectoryEntry]. A reader that enforces rules must stop on the
/// last: a trajectory it skipped is one whose rules it never learnt.
sealed class AdmittedTrajectoryEntry<R> {
  const AdmittedTrajectoryEntry();
}

/// The entry starts [trajectory], in [mission], under [rules].
final class EntryStartsTrajectory<R> extends AdmittedTrajectoryEntry<R> {
  const EntryStartsTrajectory({
    required this.event,
    required this.by,
    required this.trajectory,
    required this.mission,
    required this.rules,
  });

  /// The event admitted, by its entry's hash.
  final ObjectId event;
  final DecidedBy by;
  final TrajectoryId trajectory;
  final MissionId mission;
  final R rules;
}

/// The entry is read, and starts no trajectory: it goes under one
/// already started, or is a join.
final class EntryStartsNoTrajectory<R> extends AdmittedTrajectoryEntry<R> {
  const EntryStartsNoTrajectory();
}

/// The entry is not one `encodeDecision` writes as `event-admitted-to-mission`,
/// for the reason [why].
final class UnreadableTrajectoryEntry<R> extends AdmittedTrajectoryEntry<R> {
  const UnreadableTrajectoryEntry(this.why);

  final String why;

  @override
  String toString() => 'UnreadableTrajectoryEntry: $why';
}

/// The record entry [entry] (its bytes as the record holds them, the
/// `<kind>\n<previous>\n` header included, which its ids are hashes of),
/// read for the trajectory it starts. [rules] reads the rules from their
/// JSON, null when they aren't rules.
AdmittedTrajectoryEntry<R> readTrajectoryStart<R>(
  Uint8List entry, {
  required R? Function(Object? json) rules,
}) {
  UnreadableTrajectoryEntry<R> unreadable(String why) =>
      UnreadableTrajectoryEntry(why);

  final first = entry.indexOf(0x0a);
  final second = first < 0 ? -1 : entry.indexOf(0x0a, first + 1);
  if (second < 0) return unreadable('no `<kind>\\n<previous>\\n` header');
  final kind = ascii.decode(
    Uint8List.sublistView(entry, 0, first),
    allowInvalid: true,
  );
  if (kind != 'event-admitted-to-mission') {
    return unreadable('kind `$kind`, not `event-admitted-to-mission`');
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(Uint8List.sublistView(entry, second + 1)));
  } on FormatException catch (e) {
    return unreadable('not JSON: ${e.message}');
  }
  if (decoded is! Map<String, Object?>) return unreadable('not an object');
  final json = decoded;
  final fields = {'event', 'by', 'reading'};

  final event = switch (json['event']) {
    final String hex => ObjectId.parse(hex),
    _ => null,
  };
  if (event == null) return unreadable('`event` is not an entry hash');
  final by = switch (json['by']) {
    final String name => DecidedBy.values.asNameMap()[name],
    _ => null,
  };
  if (by == null) return unreadable('`by` is not who decided');
  final readingCase = switch (json['reading']) {
    {'case': final String readingCase} => readingCase,
    _ => null,
  };
  if (readingCase == null) return unreadable('`reading` names no case');

  // Where it goes: under a trajectory, or into a mission, starting a trajectory
  // or not.
  TrajectoryId? onTrajectory;
  MissionId? inMission;
  var startsMission = false;
  var startsTrajectory = false;
  if (json.containsKey('trajectory')) {
    onTrajectory = switch (json['trajectory']) {
      final String hex => TrajectoryId.parse(hex),
      _ => null,
    };
    if (onTrajectory == null) return unreadable('`trajectory` is not an id');
    fields.add('trajectory');
  } else {
    if (json.containsKey('mission') == json.containsKey('startsMission')) {
      return unreadable('not exactly one of `mission` and `startsMission`');
    }
    if (json.containsKey('mission')) {
      inMission = switch (json['mission']) {
        final String hex => MissionId.parse(hex),
        _ => null,
      };
      if (inMission == null) return unreadable('`mission` is not an id');
      fields.add('mission');
    } else {
      if (json['startsMission'] != true) {
        return unreadable('`startsMission` is not true');
      }
      startsMission = true;
      fields.add('startsMission');
    }
    if (json.containsKey('startsTrajectory')) {
      if (json['startsTrajectory'] != true) {
        return unreadable('`startsTrajectory` is not true');
      }
      startsTrajectory = true;
      fields.add('startsTrajectory');
    }
  }

  // Rules exactly when it starts a mission or a trajectory, as
  // EventAdmittedToMission.
  final R? read;
  if (json.containsKey('rules')) {
    read = rules(json['rules']);
    if (read == null) return unreadable('`rules` are not rules');
    fields.add('rules');
  } else {
    read = null;
  }
  if ((read != null) != (startsTrajectory || startsMission)) {
    return unreadable('`rules` not given exactly when something starts');
  }

  // Whether it starts a turn, exactly for something said, and never
  // false on a trajectory's start.
  final said = readingCase == 'message-said';
  if (json.containsKey('startsTurn') != said) {
    return unreadable('`startsTurn` not given exactly for something said');
  }
  if (said) {
    final startsTurn = json['startsTurn'];
    if (startsTurn is! bool) return unreadable('`startsTurn` is not a bool');
    if (startsTrajectory && !startsTurn) {
      return unreadable('a path started by something that starts no turn');
    }
    fields.add('startsTurn');
  }

  if (json.length != fields.length) {
    return unreadable(
      'fields beyond ${fields.join(', ')}: '
      '${json.keys.where((k) => !fields.contains(k)).join(', ')}',
    );
  }
  if (!startsTrajectory) return EntryStartsNoTrajectory();
  return EntryStartsTrajectory(
    event: event,
    by: by,
    trajectory: TrajectoryId.of(entry),
    mission: inMission ?? MissionId.of(entry),
    rules: read as R,
  );
}
