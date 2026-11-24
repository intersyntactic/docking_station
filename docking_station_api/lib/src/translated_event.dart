/// The translation contract: what a module gives the docking station, and all
/// it gives.
///
/// A module takes part only by describing. The docking station hands its
/// [TranslatesRelayedEvents] every event from the module's relay, in the
/// logbook's order, and for each the translator says what it is in the
/// docking station's terms: a [TranslatedEvent]. The docking station never
/// reads a module's bytes itself, and the module never learns which
/// trajectory anything went to.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:is_annotation_shapes/is_annotation_shapes.dart'
    show VerdictOnShownMessage;
import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId, UserSaid, WhatChanged;
import 'package:is_content_id/is_content_id.dart' show ObjectId;
import 'package:is_logbook_format/is_logbook_format.dart' show Kind;
import 'package:is_shapes/is_shapes.dart' show ActorId, TrajectoryId;

import 'package:is_reply_vocabulary/is_reply_vocabulary.dart'
    show ReplyEndpoint;

/// Where relayed events come from, such as `teams`: a lowercase letter, then
/// lowercase letters, digits and `-`, as an address in an external system
/// starts.
///
/// Its relay records each event as an entry of [kind], `<source>-event`. The
/// logbook's sender table lets one user write each kind, so an event's
/// source is vouched for by who may write its kind, never by its body.
final class RelayedEventSource {
  const RelayedEventSource._(this.value);

  /// The source, as text.
  final String value;

  /// [s] as a source; null unless it is one.
  static RelayedEventSource? parse(String s) =>
      _name.hasMatch(s) ? RelayedEventSource._(s) : null;

  /// The source whose relay records entries of [kind]; null when [kind] is
  /// not a relayed event's.
  static RelayedEventSource? ofKind(Kind kind) {
    final name = kind.name;
    if (!name.endsWith(_suffix)) return null;
    return parse(name.substring(0, name.length - _suffix.length));
  }

  /// The kind its relay records each event as.
  Kind get kind => Kind.parse('$value$_suffix')!;

  static final _name = RegExp(r'^[a-z][a-z0-9-]*$');
  static const _suffix = '-event';

  @override
  bool operator ==(Object other) =>
      other is RelayedEventSource && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// One event, as the docking station gives it to a translator: its entry's
/// hash, its source, read from the entry's kind, and what its relay
/// recorded, `{"at", "bytes"}`.
///
/// Only [RelayedEvent.read] makes one, from the entry's kind and body as
/// recorded. A relay writes one with [encodeRelayedEvent].
final class RelayedEvent {
  const RelayedEvent._({
    required this.entry,
    required this.at,
    required this.source,
    required this.bytes,
  });

  /// The entry's hash: what an admission and the turn made from it name
  /// the event by.
  final ObjectId entry;

  /// When the relay took it in.
  final DateTime at;

  /// Where it came from, as its entry's kind says.
  final RelayedEventSource source;

  /// What the source's relay recorded of the event: the bytes as they came,
  /// or the fields its translator reads, where the rest can carry
  /// credentials. Only that source's translator knows which, and reads them.
  final Uint8List bytes;

  /// The event recorded at [entry], from its [kind] and [body] as the relay
  /// recorded them. Null for anything else: a kind that is no relayed
  /// event's, or a body that isn't exactly `{"at", "bytes"}`. It is our own
  /// wire, read strictly.
  static RelayedEvent? read(ObjectId entry, Kind kind, Uint8List body) {
    final source = RelayedEventSource.ofKind(kind);
    if (source == null) return null;
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(body));
    } on FormatException {
      return null;
    }
    if (json case {'at': final String at, 'bytes': final String bytes}
        when json.length == 2) {
      final when = DateTime.tryParse(at);
      final Uint8List raw;
      try {
        raw = base64Decode(bytes);
      } on FormatException {
        return null;
      }
      if (when == null) return null;
      return RelayedEvent._(entry: entry, at: when, source: source, bytes: raw);
    }
    return null;
  }
}

/// The entry a relay records for [bytes] from [source], taken in [at]: its
/// kind, `<source>-event`, and its body, `{"at", "bytes"}`, as
/// [RelayedEvent.read] reads them back.
(Kind, Uint8List) encodeRelayedEvent(
  RelayedEventSource source, {
  required DateTime at,
  required Uint8List bytes,
}) => (
  source.kind,
  utf8.encode(
    jsonEncode({
      'at': at.toUtc().toIso8601String(),
      'bytes': base64Encode(bytes),
    }),
  ),
);

/// A module's translator of its relay's events into the docking station's
/// terms: one [TranslatedEvent] per event, carrying state from one event to
/// the next. The docking station starts from [start] and calls [step] with
/// each event from [source], in the logbook's order, keeping only the state
/// it returns.
///
/// [S] is the module's own, and the docking station never looks inside it. It
/// is there for what a translation needs from earlier events: a quote's
/// author, the message an edit or delete is of, who an earlier join brought
/// in. On every start the docking station steps again from the logbook's
/// beginning, already-admitted events included, so [step] must give the
/// same answer for the same events in the same order, and must not change
/// the state it is given.
abstract interface class TranslatesRelayedEvents<S> {
  /// The [RelayedEvent.source] whose events this translates.
  RelayedEventSource get source;

  /// The state before any event.
  S get start;

  /// [event] translated, after every earlier one from [source] has been.
  (S, TranslatedEvent) step(S state, RelayedEvent event);
}

/// What one event is: something said ([MessageSaid]), a change to an
/// earlier message ([MessageChanged]), an address joined
/// ([ActorsJoinedAddress]), a person's verdict on something the agent showed
/// ([ShownMessageJudged]), a person asking to close a trajectory
/// ([PersonAskedToCloseTrajectory]), or nothing to admit ([NothingToAdmit]).
sealed class TranslatedEvent {
  const TranslatedEvent();
}

/// Nothing to admit: a typing indicator, a reaction the module does not
/// carry, an activity it cannot read.
final class NothingToAdmit extends TranslatedEvent {
  const NothingToAdmit();
}

/// An event at an address, under a key: what the docking station decides
/// once. Either an [AdmissibleEvent], which goes under a trajectory, or a
/// [PersonAskedToCloseTrajectory], which closes one and is admitted under
/// none.
sealed class AddressedEvent extends TranslatedEvent {
  const AddressedEvent({
    required this.addressInExternalSystem,
    required this.containingAddress,
    required this.addressedTo,
    required this.replyEndpoint,
    required this.key,
  });

  /// The address in an external system it belongs to.
  final AddressInExternalSystem addressInExternalSystem;

  /// The address [addressInExternalSystem] sits inside, such as the channel a
  /// thread is in. Null when it sits inside none, as a chat or a channel
  /// itself does.
  ///
  /// It is what the outside groups its addresses by: a channel is a
  /// mission and each of its threads a trajectory. The translator names it so
  /// the docking station never reads a module's ids to find it.
  final AddressInExternalSystem? containingAddress;

  /// The bot the event was sent to, as the external system verified it, such
  /// as the audience of the token Teams signed it with. Null when the module
  /// can't verify who it was sent to. A fact of the event, not which pool or
  /// sign-in the bot is: those belong to whoever keeps the pools.
  final ActorId? addressedTo;

  /// Where replies to it go, such as a Teams conversation's activities on the
  /// Bot Connector that sent it, or null when the module can't name one. The
  /// module vouches for it, as the external system verified the event; the
  /// airlock grants a trajectory's replies to the one its start entry names.
  final ReplyEndpoint? replyEndpoint;

  /// Who it comes from, or null for no one the module can name.
  ActorId? get from;

  /// What "not decided twice" compares, within [addressInExternalSystem]: the
  /// same for two events that record one thing, as a redelivery does, and
  /// different for two things, including two changes to one message.
  final EventKey key;
}

/// An event the docking station may admit, and what it needs to decide
/// whether to.
sealed class AdmissibleEvent extends AddressedEvent {
  const AdmissibleEvent({
    required super.addressInExternalSystem,
    required super.containingAddress,
    required super.addressedTo,
    required super.replyEndpoint,
    required super.key,
  });
}

/// Something said, as [node], the node the trajectory's crux appends.
/// Whether it starts a turn is the docking station's decision, under the
/// trajectory's rules.
///
/// The translator builds [node] because only its state holds what that
/// takes, such as who wrote a message it quotes. Someone the module can't
/// name has said nothing it can admit, since a [UserSaid] always has an
/// author.
final class MessageSaid extends AdmissibleEvent {
  const MessageSaid({
    required super.addressInExternalSystem,
    required super.containingAddress,
    required super.addressedTo,
    required super.replyEndpoint,
    required super.key,
    required this.node,
  });

  /// What was said.
  final UserSaid node;

  @override
  ActorId get from => node.author;

  /// The message, as [node] names it.
  SourceMessageId get message => node.source;
}

/// A change to [message], said earlier: an edit, a delete or a restore, as
/// [change] says. It is matched to the event that said [message].
///
/// It is admitted whoever made it. Whether it counts is for whatever reads
/// it: a change counts only when [from] is who said [message], the rule
/// `Withdrawal` keeps.
final class MessageChanged extends AdmissibleEvent {
  const MessageChanged({
    required super.addressInExternalSystem,
    required super.containingAddress,
    required super.addressedTo,
    required super.replyEndpoint,
    required this.from,
    required super.key,
    required this.message,
    required this.change,
  });

  @override
  final ActorId? from;

  /// The message changed.
  final SourceMessageId message;

  /// What [message] became: what it says now, or that it was deleted or
  /// restored, in message terms, before anything maps it to a turn.
  final WhatChanged change;
}

/// [joiners] joined [addressInExternalSystem]. One event may bring in several.
final class ActorsJoinedAddress extends AdmissibleEvent {
  const ActorsJoinedAddress._({
    required super.addressInExternalSystem,
    required super.containingAddress,
    required super.addressedTo,
    required super.replyEndpoint,
    required this.from,
    required super.key,
    required this.joiners,
  });

  @override
  final ActorId? from;

  /// Who joined; never empty.
  final List<ActorId> joiners;

  /// A join of [joiners]; null when there are none, which is
  /// [NothingToAdmit].
  static ActorsJoinedAddress? of({
    required AddressInExternalSystem addressInExternalSystem,
    required AddressInExternalSystem? containingAddress,
    required ActorId? addressedTo,
    required ReplyEndpoint? replyEndpoint,
    required ActorId? from,
    required EventKey key,
    required Iterable<ActorId> joiners,
  }) {
    final list = List<ActorId>.unmodifiable(joiners);
    if (list.isEmpty) return null;
    return ActorsJoinedAddress._(
      addressInExternalSystem: addressInExternalSystem,
      containingAddress: containingAddress,
      addressedTo: addressedTo,
      replyEndpoint: replyEndpoint,
      from: from,
      key: key,
      joiners: list,
    );
  }
}

/// A person's [verdict] on [to], something the agent showed them, such as
/// Approve, Not yet or a proposed correction on a card. Named for what the
/// person said, not for the button, so a Slack button reads the same.
///
/// It names the message, never a turn: the trajectory's crux builds the
/// annotation, a `NodeApproval`, a `NodeSeenMark` or a `NodeCorrection`,
/// once it knows which turn [to] showed. A verdict always names who gave
/// it, since a verdict from no one approves nothing.
final class ShownMessageJudged extends AdmissibleEvent {
  const ShownMessageJudged({
    required super.addressInExternalSystem,
    required super.containingAddress,
    required super.addressedTo,
    required super.replyEndpoint,
    required this.from,
    required super.key,
    required this.to,
    required this.verdict,
  });

  @override
  final ActorId from;

  /// The message judged, such as the card, as it was sent.
  final SourceMessageId to;

  final VerdictOnShownMessage verdict;
}

/// [from] asked to close [trajectory], on [message], a reply the agent sent
/// in it, such as the Close in a Teams reply card's menu. Anyone at the
/// address may ask, and nothing of it goes to the agent.
///
/// [trajectory] is the one [message] was sent in, as the reply itself
/// carries it, so a close on an old reply closes that reply's trajectory,
/// never whichever is open at the address now. The person's client sends it
/// back, so it is not vouched for: the docking station closes it only when
/// it is the trajectory open at [addressInExternalSystem], which anyone
/// there may close anyway. [message] is kept to say where the person asked.
/// A close always names who asked, since one asked by no one closes
/// nothing.
final class PersonAskedToCloseTrajectory extends AddressedEvent {
  const PersonAskedToCloseTrajectory({
    required super.addressInExternalSystem,
    required super.containingAddress,
    required super.addressedTo,
    required super.replyEndpoint,
    required this.from,
    required super.key,
    required this.message,
    required this.trajectory,
  });

  @override
  final ActorId from;

  /// The message the person picked the close on, as it was sent.
  final SourceMessageId message;

  /// The trajectory [message] was sent in, as the reply carries it.
  final TrajectoryId trajectory;
}

/// An address in an external system: a Teams chat, channel or channel thread, a
/// Slack channel. The docking station keeps each one under a trajectory,
/// and one that others sit inside, such as a channel, as a mission.
///
/// Written like an [ActorId], a source, a colon and the rest, such as
/// `teams:19:abc@thread.v2`, so two modules never name two addresses
/// alike.
final class AddressInExternalSystem {
  const AddressInExternalSystem._(this.value);

  /// The id, as text.
  final String value;

  /// [s] as an address; null unless it is a source, a colon, and the
  /// rest, with the rest printable ASCII and no spaces.
  static AddressInExternalSystem? parse(String s) =>
      _id.hasMatch(s) ? AddressInExternalSystem._(s) : null;

  static final _id = RegExp(r'^[a-z][a-z0-9-]*:[\x21-\x7e]+$');

  @override
  bool operator ==(Object other) =>
      other is AddressInExternalSystem && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// One event's key within its address, in the module's own terms. Not
/// a message's id: an edit is a second event about the same message.
final class EventKey {
  const EventKey._(this.value);

  /// The key, as text.
  final String value;

  /// [s] as an event key; null when empty or with whitespace.
  static EventKey? parse(String s) =>
      s.isNotEmpty && !s.contains(RegExp(r'\s')) ? EventKey._(s) : null;

  @override
  bool operator ==(Object other) => other is EventKey && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
