/// A reading as the `event-admitted-to-mission` entry carries it, and back,
/// read strictly, since it is our own wire.
///
/// The nodes inside travel in their own packages' map form,
/// `{"shape": <class name>, ...its fields}`, each under a field of its own,
/// so this reads each with its own package's decoder and never looks at a
/// node's fields itself.
library;

import 'package:checked_json/checked_json.dart';
import 'package:is_annotation_shapes/is_annotation_shapes.dart'
    show VerdictOnShownMessage;
import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId, UserSaid, WhatChanged;
import 'package:is_shapes/is_shapes.dart' show ActorId;

import 'reading.dart';

/// Every node shape a reading can carry, by the field it travels in, as
/// each node's package names them. A `shape` is one namespace across every
/// package whose nodes travel in map form, so no two of these may share a
/// name (Nick, 16 Nov: the docking station checks names).
const readingNodeShapes = <String, Set<String>>{
  'node': {UserSaid.shapeName},
  'change': WhatChanged.shapeNames,
  'verdict': VerdictOnShownMessage.shapeNames,
};

/// [reading] as JSON:
///
///     {"case": <case>, "addressInExternalSystem": <id>,
///      "containingAddress": <id>?, "addressedTo": <actor>?, "key": <key>,
///      ...the case's own fields}
///
/// `<case>` and its fields are `message-said`, with `"node"`, a
/// [UserSaid]; `message-changed`, with `"from"?`, `"message"` and
/// `"change"`, a [WhatChanged]; `actors-joined-address`, with `"from"?` and
/// `"joiners"`; `shown-message-judged`, with `"from"`, `"to"` and
/// `"verdict"`, a [VerdictOnShownMessage]; `person-asked-to-close-trajectory`,
/// with `"from"` and `"message"`.
JsonObject encodeReading(AddressedEvent reading) => JsonObject.of({
  'case': _case(reading),
  'addressInExternalSystem': reading.addressInExternalSystem.value,
  'containingAddress': ?reading.containingAddress?.value,
  'addressedTo': ?reading.addressedTo?.value,
  'key': reading.key.value,
  ...switch (reading) {
    MessageSaid(:final node) => {'node': node.toJson()},
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
    PersonAskedToCloseTrajectory(:final from, :final message) => {
      'from': from.value,
      'message': message.value,
    },
  },
});

String _case(AddressedEvent reading) => switch (reading) {
  MessageSaid() => 'message-said',
  MessageChanged() => 'message-changed',
  ActorsJoinedAddress() => 'actors-joined-address',
  ShownMessageJudged() => 'shown-message-judged',
  PersonAskedToCloseTrajectory() => 'person-asked-to-close-trajectory',
};

/// [json] read back as the reading [encodeReading] wrote. A
/// [FormatException] for anything it doesn't write: an unknown case, a
/// field missing, extra or malformed, a node its package won't read.
AddressedEvent decodeReading(JsonObject json) {
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
  final key = _parse(json, 'key', EventKey.parse);
  ActorId? from() =>
      json.has('from') ? _parse(json, 'from', ActorId.parse) : null;

  final (reading, fields) = switch (json.string('case')) {
    'message-said' => (
      MessageSaid(
        addressInExternalSystem: addressInExternalSystem,
        containingAddress: containingAddress,
        addressedTo: addressedTo,
        key: key,
        node: UserSaid.fromJson(json.object('node')),
      ),
      const {'node'},
    ),
    'message-changed' => (
      MessageChanged(
        addressInExternalSystem: addressInExternalSystem,
        containingAddress: containingAddress,
        addressedTo: addressedTo,
        from: from(),
        key: key,
        message: _parse(json, 'message', SourceMessageId.parse),
        change: WhatChanged.fromJson(json.object('change')),
      ),
      const {'from', 'message', 'change'},
    ),
    'actors-joined-address' => (
      ActorsJoinedAddress.of(
            addressInExternalSystem: addressInExternalSystem,
            containingAddress: containingAddress,
            addressedTo: addressedTo,
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
    'shown-message-judged' => (
      ShownMessageJudged(
        addressInExternalSystem: addressInExternalSystem,
        containingAddress: containingAddress,
        addressedTo: addressedTo,
        from: _parse(json, 'from', ActorId.parse),
        key: key,
        to: _parse(json, 'to', SourceMessageId.parse),
        verdict: VerdictOnShownMessage.fromJson(json.object('verdict')),
      ),
      const {'from', 'to', 'verdict'},
    ),
    'person-asked-to-close-trajectory' => (
      PersonAskedToCloseTrajectory(
        addressInExternalSystem: addressInExternalSystem,
        containingAddress: containingAddress,
        addressedTo: addressedTo,
        from: _parse(json, 'from', ActorId.parse),
        key: key,
        message: _parse(json, 'message', SourceMessageId.parse),
      ),
      const {'from', 'message'},
    ),
    final other => throw FormatException('`case` is not a reading: $other'),
  };
  for (final field in json.keys) {
    if (!{
      'case',
      'addressInExternalSystem',
      'containingAddress',
      'addressedTo',
      'key',
      ...fields,
    }.contains(field)) {
      throw FormatException('`$field` is not a field of a reading');
    }
  }
  return reading;
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
