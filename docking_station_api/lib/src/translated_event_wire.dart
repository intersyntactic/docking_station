/// A translated event as the `event-admitted-to-mission` entry carries it, and
/// back, read strictly, since it is our own wire.
///
/// The nodes inside travel in their own packages' map form,
/// `{"shape": <class name>, ...its fields}`, each under a field of its own,
/// so this reads each with its own package's decoder and never looks at a
/// node's fields itself.
library;

import 'package:checked_json/checked_json.dart';
import 'package:is_annotation_shapes/is_annotation_shapes.dart'
    show VerdictOnShownMessage;
import 'package:is_conversation_vocabulary/is_conversation_vocabulary.dart'
    show
        ConversationKind,
        SourceMessageId,
        UserSaid,
        WhatChanged,
        decodeReplyEndpoint,
        encodeReplyEndpoint;
import 'package:is_shapes/is_shapes.dart' show ActorId, TrajectoryId;

import 'translated_event.dart';
import 'translated_event_case.dart';

/// Every node shape a translated event can carry, by the field it travels in,
/// as each node's package names them. A `shape` is one namespace across every
/// package whose nodes travel in map form, so no two of these may share a
/// name, and the docking station checks that none do.
const translatedEventNodeShapes = <String, Set<String>>{
  'node': {UserSaid.shapeName},
  'change': WhatChanged.shapeNames,
  'verdict': VerdictOnShownMessage.shapeNames,
};

/// [event] as JSON:
///
///     {"case": <case>, "addressInExternalSystem": <id>,
///      "containingAddress": <id>?, "addressedTo": <actor>?,
///      "replyEndpoint": <reply endpoint>?, "key": <key>,
///      ...the case's own fields}
///
/// `<reply endpoint>` is as `encodeReplyEndpoint` writes it.
///
/// `<case>` and its fields are `message-said`, with `"node"`, a
/// [UserSaid]; `message-changed`, with `"from"?`, `"message"` and
/// `"change"`, a [WhatChanged]; `actors-joined-address`, with `"from"?` and
/// `"joiners"`; `shown-message-judged`, with `"from"`, `"to"` and
/// `"verdict"`, a [VerdictOnShownMessage]; `person-asked-to-close-trajectory`,
/// with `"from"`, `"message"` and `"trajectory"`.
JsonObject encodeTranslatedEvent(AddressedEvent event) => JsonObject.of({
  'case': _case(event),
  'addressInExternalSystem': event.addressInExternalSystem.value,
  'containingAddress': ?event.containingAddress?.value,
  'addressedTo': ?event.addressedTo?.value,
  if (event.replyEndpoint case final endpoint?)
    'replyEndpoint': encodeReplyEndpoint(endpoint),
  'key': event.key.value,
  ...switch (event) {
    MessageSaid(:final node, :final conversationKind) => {
      'node': node.toJson(),
      'conversationKind': conversationKind.wire,
    },
    MessageChanged(:final from, :final message, :final change) => {
      'from': ?from?.value,
      'message': message.value,
      'change': change.toJson(),
    },
    ActorsJoinedAddress(:final from, :final joiners) => {
      'from': ?from?.value,
      'joiners': [for (final joiner in joiners) joiner.value],
    },
    ShownMessageJudged(:final from, :final to, :final verdict) => {
      'from': from.value,
      'to': to.value,
      'verdict': verdict.toJson(),
    },
    PersonAskedToCloseTrajectory(
      :final from,
      :final message,
      :final trajectory,
    ) =>
      {
        'from': from.value,
        'message': message.value,
        'trajectory': trajectory.hex,
      },
  },
});

String _case(AddressedEvent event) => switch (event) {
  MessageSaid() => TranslatedEventCase.messageSaid,
  MessageChanged() => TranslatedEventCase.messageChanged,
  ActorsJoinedAddress() => TranslatedEventCase.actorsJoinedAddress,
  ShownMessageJudged() => TranslatedEventCase.shownMessageJudged,
  PersonAskedToCloseTrajectory() =>
    TranslatedEventCase.personAskedToCloseTrajectory,
}.wire;

/// [json] read back as the translated event [encodeTranslatedEvent] wrote. A
/// [FormatException] for anything it doesn't write: an unknown case, a
/// field missing, extra or malformed, a node its package won't read.
AddressedEvent decodeTranslatedEvent(JsonObject json) {
  final addressInExternalSystem = _parse(
    json,
    'addressInExternalSystem',
    AddressInExternalSystem.parse,
  );
  final containingAddress = json.has('containingAddress')
      ? _parse(json, 'containingAddress', AddressInExternalSystem.parse)
      : null;
  final addressedTo = json.has('addressedTo')
      ? _parse(json, 'addressedTo', ActorId.parse)
      : null;
  final replyEndpoint = json.has('replyEndpoint')
      ? decodeReplyEndpoint(json.raw('replyEndpoint'), 'replyEndpoint')
      : null;
  final key = _parse(json, 'key', EventKey.parse);
  ActorId? from() =>
      json.has('from') ? _parse(json, 'from', ActorId.parse) : null;

  final name = json.string('case');
  final eventCase =
      TranslatedEventCase.parse(name) ??
      (throw FormatException('`case` is not a translated event: $name'));
  final (event, fields) = switch (eventCase) {
    TranslatedEventCase.messageSaid => (
      MessageSaid(
        addressInExternalSystem: addressInExternalSystem,
        containingAddress: containingAddress,
        addressedTo: addressedTo,
        replyEndpoint: replyEndpoint,
        key: key,
        node: UserSaid.fromJson(json.object('node')),
        conversationKind: _conversationKind(json),
      ),
      const {'node', 'conversationKind'},
    ),
    TranslatedEventCase.messageChanged => (
      MessageChanged(
        addressInExternalSystem: addressInExternalSystem,
        containingAddress: containingAddress,
        addressedTo: addressedTo,
        replyEndpoint: replyEndpoint,
        from: from(),
        key: key,
        message: _parse(json, 'message', SourceMessageId.parse),
        change: WhatChanged.fromJson(json.object('change')),
      ),
      const {'from', 'message', 'change'},
    ),
    TranslatedEventCase.actorsJoinedAddress => (
      ActorsJoinedAddress.of(
            addressInExternalSystem: addressInExternalSystem,
            containingAddress: containingAddress,
            addressedTo: addressedTo,
            replyEndpoint: replyEndpoint,
            from: from(),
            key: key,
            joiners: [
              for (final joiner in json.strings('joiners'))
                ActorId.parse(joiner) ??
                    (throw JsonFieldException('joiners', 'actor ids')),
            ],
          ) ??
          (throw JsonFieldException('joiners', 'a list of one or more')),
      const {'from', 'joiners'},
    ),
    TranslatedEventCase.shownMessageJudged => (
      ShownMessageJudged(
        addressInExternalSystem: addressInExternalSystem,
        containingAddress: containingAddress,
        addressedTo: addressedTo,
        replyEndpoint: replyEndpoint,
        from: _parse(json, 'from', ActorId.parse),
        key: key,
        to: _parse(json, 'to', SourceMessageId.parse),
        verdict: VerdictOnShownMessage.fromJson(json.object('verdict')),
      ),
      const {'from', 'to', 'verdict'},
    ),
    TranslatedEventCase.personAskedToCloseTrajectory => (
      PersonAskedToCloseTrajectory(
        addressInExternalSystem: addressInExternalSystem,
        containingAddress: containingAddress,
        addressedTo: addressedTo,
        replyEndpoint: replyEndpoint,
        from: _parse(json, 'from', ActorId.parse),
        key: key,
        message: _parse(json, 'message', SourceMessageId.parse),
        trajectory: _parse(json, 'trajectory', TrajectoryId.parse),
      ),
      const {'from', 'message', 'trajectory'},
    ),
  };
  for (final field in json.keys) {
    if (!{
      'case',
      'addressInExternalSystem',
      'containingAddress',
      'addressedTo',
      'replyEndpoint',
      'key',
      ...fields,
    }.contains(field)) {
      throw FormatException('`$field` is not a field of a translated event');
    }
  }
  return event;
}

/// [json]'s [field], a string, parsed by [parse]; a [JsonFieldException]
/// when it is absent, not a string, or [parse] refuses it.
T _parse<T extends Object>(
  JsonObject json,
  String field,
  T? Function(String) parse,
) =>
    parse(json.string(field)) ??
    (throw JsonFieldException(field, 'a well-formed ${T.toString()}'));

/// The `conversationKind` of something said. An entry written before the
/// field existed has none, and reads as [ConversationKind.notKnown]: the
/// module never said, and such an entry is only ever history, never decided
/// again. Every entry written now carries it.
ConversationKind _conversationKind(JsonObject json) {
  if (!json.has('conversationKind')) return ConversationKind.notKnown;
  return ConversationKind.parse(json.string('conversationKind')) ??
      (throw JsonFieldException('conversationKind', 'a conversation kind'));
}
