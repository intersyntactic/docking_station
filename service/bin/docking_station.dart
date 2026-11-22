/// The docking station as a service: it reads the logbook through its read
/// socket, decides each event, and sends each decision through its write
/// socket.
///
///   dart run bin/docking_station.dart
///     --read-socket=PATH                   the logbook's read socket
///     --write-socket=PATH                  the logbook's write socket
///     --config=/etc/.../config.json        the addresses let in, as
///                                          [AddressesLetIn] reads them
///     --flight-rules=/etc/.../flight-rules.json
///                                          the flight rules each mission
///                                          starts under, read as
///                                          [FlightRulesByMissionAddress]
///     --start-kind=KIND                    the kind of the start entry,
///                                          written once at setup
///
/// It exits non-zero whenever the docking station stops, whether it returns
/// or throws: it should run for as long as the logbook does, so the service
/// manager starts it again, and it reads back whatever got in. Except for
/// what a restart can't change: 64 for bad arguments, 78 for a config or
/// rules file it can't read, 65 for a logbook it can't go on from (a second
/// start entry, a decision before the first or one it can't read, a refused
/// decision).
library;

import 'dart:io';

import 'package:docking_station_service/docking_station_service.dart';
import 'package:is_logbook_client/is_logbook_client.dart';
import 'package:is_teams_module/is_teams_module.dart' show TeamsReading;

const _options = {
  'read-socket',
  'write-socket',
  'config',
  'flight-rules',
  'start-kind',
};

Future<void> main(List<String> arguments) async {
  final given = <String, String>{};
  for (final argument in arguments) {
    final match = RegExp(r'^--([a-z-]+)=(.+)$').firstMatch(argument);
    final name = match?.group(1);
    if (match == null || !_options.contains(name)) {
      _abort('unknown argument: $argument', 64);
    }
    if (given.containsKey(name)) _abort('--$name given twice', 64);
    given[name!] = match.group(2)!;
  }
  for (final name in _options) {
    if (!given.containsKey(name)) _abort('--$name is required', 64);
  }

  final startKind =
      Kind.parse(given['start-kind']!) ??
      _abort('--start-kind "${given['start-kind']}" is not a kind', 64);
  final flightRules = await _read(
    given['flight-rules']!,
    'the rules file',
    FlightRulesByMissionAddress.parse,
  );
  final addressesLetIn = await _read(
    given['config']!,
    'the config',
    (text) => AddressesLetIn.parse(text, flightRules: flightRules),
  );

  final reader = LogbookReader(given['read-socket']!);
  final writer = LogbookWriter(given['write-socket']!);
  stderr.writeln(
    'docking station: ${addressesLetIn.addresses.length} addresses let in, '
    'start entry of kind $startKind',
  );
  // A logbook no restart changes exits 65, which the service manager doesn't
  // restart. Anything else is left uncaught, so the program exits 255 with
  // it printed and is started again: a [StateError] for a decision that may
  // or may not be in, a [ReadFailure] for the read socket gone.
  try {
    await runDockingStation(
      subscribe: (kinds) => reader.subscribe(kinds: kinds),
      send: writer.write,
      startKind: startKind,
      readings: const [TeamsReading()],
      missions: addressesLetIn,
      turns: const EverySaidStartsATurn(),
    );
  } on LogbookNoRestartChanges catch (e) {
    _abort(e.why, 65);
  }
  _abort('stopped: the logbook\'s subscription ended', 1);
}

/// [path]'s contents as [read] reads them, or exit 78 naming [what].
Future<T> _read<T>(String path, String what, T Function(String) read) async {
  final String text;
  try {
    text = await File(path).readAsString();
  } on FileSystemException catch (e) {
    _abort('$what could not be read: ${e.message}', 78);
  }
  try {
    return read(text);
  } on FormatException catch (e) {
    _abort('$what is not one this reads: ${e.message}', 78);
  }
}

Never _abort(String why, int code) {
  stderr.writeln('abort: $why');
  exit(code);
}
