/// Running the docking station: reading the logbook, deciding each event,
/// and sending each decision to it.
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

import 'package:is_docking_station_api/is_docking_station_api.dart';

import 'rules.dart';

/// The kinds of entry the logbook names events by: `event`, and `arrived`,
/// which entries recorded before the rename keep for good, since an entry's
/// kind is part of the bytes its hash is taken from.
final _eventKinds = {Kind.parse('event')!, Kind.parse('arrived')!};

/// Why [runDockingStation] stopped, when starting it again would stop it the
/// same way: the logbook holds, or refuses, something no restart changes,
/// such as a second start entry or a decision it can't read.
final class LogbookNoRestartChanges implements Exception {
  const LogbookNoRestartChanges(this.why);

  final String why;

  @override
  String toString() => 'LogbookNoRestartChanges: $why';
}

/// Runs the docking station until [subscribe]'s stream ends, which it never
/// should: the caller treats a return as the logbook going away.
///
/// It reads the logbook from its start, subscribing with [subscribe] to its
/// events, its decisions and its start entry, the one entry of [startKind].
/// Each event is translated by the one of [translators] for its source, in
/// the logbook's order, and each decision is taken into a [DecidedSoFar]. Once
/// the subscription has caught up, each event after the start entry with no
/// decision is decided under [missions] and [turns], in order, and sent with
/// [send], naming the decision before it as previous, or the start entry for
/// the first; so is each event after that, as it comes. [subscribe] and
/// [send] are a `LogbookReader`'s and a `LogbookWriter`'s, or stand-ins.
///
/// The start entry is written once, at setup, by whoever sets the docking
/// station up, never by the docking station: two of them starting at once
/// would each write one. An event before it is translated, so a translator
/// learns from its history, but never decided. With no start entry yet, nothing is
/// decided until one comes. A second start entry, or a decision before the
/// first, stops it: there is one start entry, and nothing resets what was
/// decided.
///
/// When the logbook answers [AlreadyRecorded], these exact bytes are in, so
/// this decision is, after the same tip, whoever sent them: it is taken as
/// if [Written]. When it answers [NotTip], the decisions' chain has moved on:
/// another docking station decided first, and its decision comes on the
/// logbook to be taken like any other. A failed add, or no answer, stops it
/// with a [StateError]: the decision may or may not be in, and deciding on
/// regardless could admit an event twice; started again, it reads back
/// whatever got in. A refusal for some other reason, such as a sender table
/// that doesn't allow the kind, stops it with a [LogbookNoRestartChanges], as
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
  required Iterable<TranslatesRelayedEvents<Object?>> translators,
  required DecidesWhichAddressStartsAMission missions,
  required TurnRule turns,
}) async {
  final bySource = <String, _TranslatorWithState<Object?>>{};
  for (final translator in translators) {
    if (bySource.containsKey(translator.source)) {
      throw ArgumentError.value(
        translator.source,
        'translators',
        'two translators for one source',
      );
    }
    bySource[translator.source] = _TranslatorWithState(translator);
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
  // translation, in the logbook's order.
  final waiting = <ObjectId, TranslatedEvent?>{};

  // Decides each waiting event in order. Returns early when another
  // docking station has decided first: its decisions come on the logbook.
  Future<void> decideWaiting(ObjectId start) async {
    while (waiting.isNotEmpty) {
      final MapEntry(key: event, value: translated) = waiting.entries.first;
      final decision = decide(
        event,
        translated,
        decided,
        missions: missions,
        turns: turns,
      );
      final (kind, body) = encodeDecision(decision);
      final previous = decided.tip ?? start;
      final entry = switch (await send(kind, body, previous: previous)) {
        Written(:final entry) || AlreadyRecorded(:final entry) => entry,
        NotTip() => null,
        WriteRefused(:final why) => throw LogbookNoRestartChanges(
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
        // Translated whether or not it is decided, so a translator learns
        // from the events before the start entry too.
        final event = RelayedEvent.read(id, item.body);
        final translated = switch (event) {
          final event? => bySource[event.source]?.step(event),
          null => null,
        };
        if (start != null) waiting[id] = translated;
      case Entry(:final id, :final kind) when kind == startKind:
        if (start != null) {
          throw LogbookNoRestartChanges(
            'a second start entry ${id.hex}, after ${start.hex}',
          );
        }
        start = id;
      case Entry(:final id, :final kind):
        if (start == null) {
          throw LogbookNoRestartChanges(
            'the decision ${id.hex} is before any start',
          );
        }
        final decision =
            decodeDecision(kind, item.body) ??
            (throw LogbookNoRestartChanges(
              'cannot read the decision ${id.hex}',
            ));
        decided.take(id, decision);
        if (decision case DecidedAtEvent(:final event)) waiting.remove(event);
      case CaughtUp():
        caughtUp = true;
    }
    if (caughtUp && start != null) await decideWaiting(start);
  }
}

/// One module's translator, with the state it returned last, which it is
/// given with each event.
final class _TranslatorWithState<S> {
  _TranslatorWithState(this._translator) : _state = _translator.start;

  final TranslatesRelayedEvents<S> _translator;
  S _state;

  TranslatedEvent step(RelayedEvent event) {
    final (state, translated) = _translator.step(_state, event);
    _state = state;
    return translated;
  }
}
