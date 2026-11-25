/// Closes one trajectory as an operator, from outside its conversation, and
/// exits. Run on the docking station's machine, by the one user the logbook's
/// sender table lets send `trajectory-closed` for an operator.
///
///   dart run bin/close_trajectory.dart
///     --read-socket=PATH      the logbook's read socket
///     --write-socket=PATH     the logbook's write socket
///     --start-kind=KIND       the kind of the docking station's start entry
///     --trajectory=HEX        the trajectory to close
///     --operator=NAME         who is closing it, as a user name is written
///     --reason=TEXT           why, in a few words
///
/// It reads the docking station's decisions, takes the trajectory's mission
/// from them, and sends one [TrajectoryClosedByOperator] on the docking
/// station's chain. The running docking station need not stop.
///
/// It exits 0 with the close's entry id printed; 1 when no trajectory by
/// that id is open; 64 for bad arguments; 65 when the close was not sent or
/// the logbook refused it; 75 when it was sent but no answer said whether it
/// is in, which running it again settles.
library;

import 'dart:io';

import 'package:docking_station_service/docking_station_service.dart';
import 'package:is_docking_station_api/is_docking_station_api.dart'
    show OperatorName;
import 'package:is_logbook_client/is_logbook_client.dart';

const _options = {
  'read-socket',
  'write-socket',
  'start-kind',
  'trajectory',
  'operator',
  'reason',
};

Future<void> main(List<String> arguments) async {
  final given = <String, String>{};
  for (final argument in arguments) {
    final match = RegExp(
      r'^--([a-z-]+)=(.+)$',
      dotAll: true,
    ).firstMatch(argument);
    final name = match?.group(1);
    if (match == null || !_options.contains(name)) {
      _exit('unknown argument: $argument', 64);
    }
    if (given.containsKey(name)) _exit('--$name given twice', 64);
    given[name!] = match.group(2)!;
  }
  for (final name in _options) {
    if (!given.containsKey(name)) _exit('--$name is required', 64);
  }
  final startKind =
      Kind.parse(given['start-kind']!) ??
      _exit('--start-kind "${given['start-kind']}" is not a kind', 64);
  final trajectory =
      TrajectoryId.parse(given['trajectory']!) ??
      _exit('--trajectory "${given['trajectory']}" is not an id', 64);
  final operator =
      OperatorName.parse(given['operator']!) ??
      _exit('--operator "${given['operator']}" is not a user name', 64);
  final reason = given['reason']!;
  if (reason.trim().isEmpty) _exit('--reason is blank', 64);

  final reader = LogbookReader(given['read-socket']!);
  final writer = LogbookWriter(given['write-socket']!);
  final outcome = await closeTrajectoryByOperator(
    subscribe: (kinds) => reader.subscribe(kinds: kinds),
    send: writer.write,
    startKind: startKind,
    trajectory: trajectory,
    operator: operator,
    reason: reason,
  );
  switch (outcome) {
    case OperatorClosedTrajectory(:final entry, :final decision):
      stdout.writeln(
        'closed ${decision.trajectory.hex} in mission '
        '${decision.mission.hex}, at ${entry.hex}',
      );
      exit(0);
    case NoOpenTrajectory():
      _exit('no trajectory ${trajectory.hex} is open', 1);
    case NoStartEntry():
      _exit('the logbook has no start entry of kind $startKind', 1);
    case OperatorCloseNotSent(:final why):
      _exit('not closed: $why', 65);
    case OperatorCloseMayOrMayNotBeIn(:final why):
      _exit('the close may or may not be in ($why); run this again', 75);
  }
}

Never _exit(String why, int code) {
  stderr.writeln('close_trajectory: $why');
  exit(code);
}
