/// Running the docking station: reading the record, deciding each event,
/// and sending each decision to it (RULINGS, "The docking station admits
/// events under journey paths").
library;

import 'package:is_logbook_client/is_logbook_client.dart'
    show
        AlreadyRecorded,
        CaughtUp,
        Entry,
        Kind,
        ObjectId,
        NotTip,
        Subscribed,
        Unanswered,
        WriteFailed,
        WriteRefused,
        WriteResult,
        Written;

import 'decide.dart';
import 'decided.dart';

import 'package:is_admission_vocabulary/is_admission_vocabulary.dart';

import 'rules.dart';

/// The kinds of entry the record names events by: `event`, and `arrived`,
/// which entries recorded before the rename keep for good, since an entry's
/// kind is part of the bytes its hash is taken from (Nick, 16 Nov: "It's an
/// event, not an arrival").
final _eventKinds = {Kind.parse('event')!, Kind.parse('arrived')!};

/// Why [runDockingStation] stopped, when starting it again would stop it the
/// same way: the record holds, or refuses, something no restart changes,
/// such as a second start entry or a decision it can't read.
final class RecordNoRestartChanges implements Exception {
  const RecordNoRestartChanges(this.why);

  final String why;

  @override
  String toString() => 'RecordNoRestartChanges: $why';
}

/// Runs the docking station until [subscribe]'s stream ends, which it never
/// should: the caller treats a return as the record going away.
///
/// It reads the record from its start, subscribing with [subscribe] to its
/// events, its decisions and its start entry, the one entry of [startKind].
/// Each event is read by the one of [readings] for its source, in the
/// record's order, and each decision is taken into a [DecidedSoFar]. Once
/// the subscription has caught up, each event after the start entry with no
/// decision is decided under [missions] and [turns], in order, and sent with
/// [send], naming the decision before it as previous, or the start entry for
/// the first; so is each event after that, as it comes. [subscribe] and
/// [send] are a `LogbookReader`'s and a `LogbookWriter`'s, or stand-ins.
///
/// The start entry is written once, at setup, by whoever sets the docking
/// station up, never by the docking station: two of them starting at once
/// would each write one (Nick, 16 Nov: leave events from before the first
/// run undecided). An event before it is read, so a reading learns from
/// its history, but never decided. With no start entry yet, nothing is
/// decided until one comes. A second start entry, or a decision before
/// the first, stops it: a later start entry that reset what was decided
/// is a call not made (one start entry, intersyntactic-a8 and this
/// session's lean, 16 Nov; the open questions hold it).
///
/// When the record answers [AlreadyRecorded], these exact bytes are in, so
/// this decision is, after the same tip, whoever sent them: it is taken as
/// if [Written]. When it answers [NotTip], the decisions' chain has moved on:
/// another docking station decided first, and its decision comes on the
/// record to be taken like any other. A failed add, or no answer, stops it
/// with a [StateError]: the decision may or may not be in, and deciding on
/// regardless could admit an event twice; started again, it reads back
/// whatever got in. A refusal for some other reason, such as a sender table
/// that doesn't allow the kind, stops it with a [RecordNoRestartChanges], as
/// do a second start entry, a decision before the first, and an entry it
/// can't read: starting again would meet each the same way.
Future<void> runDockingStation({
  required Stream<Subscribed> Function(Set<Kind> kinds) subscribe,
  required Future<WriteResult> Function(
    Kind kind,
    List<int> body, {
    ObjectId? previous,
  })
  send,
  required Kind startKind,
  required Iterable<ModuleReading<Object?>> readings,
  required JourneyRule missions,
  required TurnRule turns,
}) async {
  final folds = <String, _Fold<Object?>>{};
  for (final reading in readings) {
    if (folds.containsKey(reading.source)) {
      throw ArgumentError.value(
        reading.source,
        'readings',
        'two readings for one source',
      );
    }
    folds[reading.source] = _Fold(reading);
  }
  if (_eventKinds.contains(startKind) ||
      DecisionEntryKind.all.contains(startKind)) {
    throw ArgumentError.value(
      startKind,
      'startKind',
      'is the kind of an event or a decision',
    );
  }
  final decided = DecidedSoFar();
  // The start entry, once it has come.
  ObjectId? start;
  // Each event after the start entry read but not yet decided, with its
  // reading, in the record's order.
  final waiting = <ObjectId, EventReading?>{};

  // Decides each waiting event in order. Returns early when another
  // docking station has decided first: its decisions come on the record.
  Future<void> decideWaiting(ObjectId start) async {
    while (waiting.isNotEmpty) {
      final MapEntry(key: event, value: reading) = waiting.entries.first;
      final decision = decide(
        event,
        reading,
        decided,
        missions: missions,
        turns: turns,
      );
      final (kind, body) = encodeDecision(decision);
      final previous = decided.tip ?? start;
      final entry = switch (await send(kind, body, previous: previous)) {
        Written(:final entry) || AlreadyRecorded(:final entry) => entry,
        NotTip() => null,
        WriteRefused(:final why) => throw RecordNoRestartChanges(
          'the decision on ${event.hex} was refused: $why',
        ),
        WriteFailed(:final why) || Unanswered(:final why) => throw StateError(
          'the decision on ${event.hex} may or may not be in: $why',
        ),
      };
      if (entry == null) return;
      decided.take(entry, decision);
      waiting.remove(event);
    }
  }

  var caughtUp = false;
  final kinds = {..._eventKinds, ...DecisionEntryKind.all, startKind};
  await for (final item in subscribe(kinds)) {
    switch (item) {
      case Entry(:final id, :final kind) when _eventKinds.contains(kind):
        // Read whether or not it is decided, so a reading learns from the
        // events before the start entry too.
        final event = RelayedEvent.read(id, item.body);
        final reading = switch (event) {
          final event? => folds[event.source]?.step(event),
          null => null,
        };
        if (start != null) waiting[id] = reading;
      case Entry(:final id, :final kind) when kind == startKind:
        if (start != null) {
          throw RecordNoRestartChanges(
            'a second start entry ${id.hex}, after ${start.hex}',
          );
        }
        start = id;
      case Entry(:final id, :final kind):
        if (start == null) {
          throw RecordNoRestartChanges(
            'the decision ${id.hex} is before any start',
          );
        }
        final decision =
            decodeDecision(kind, item.body) ??
            (throw RecordNoRestartChanges(
              'cannot read the decision ${id.hex}',
            ));
        decided.take(id, decision);
        waiting.remove(decision.event);
      case CaughtUp():
        caughtUp = true;
    }
    if (caughtUp && start != null) await decideWaiting(start);
  }
}

/// One module's reading, folded: it keeps the state the reading returned
/// last, and gives each event to the reading with it.
final class _Fold<S> {
  _Fold(this._reading) : _state = _reading.start;

  final ModuleReading<S> _reading;
  S _state;

  EventReading step(RelayedEvent event) {
    final (state, reading) = _reading.step(_state, event);
    _state = state;
    return reading;
  }
}
