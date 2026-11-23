/// A decision as the logbook entry the docking station sends, and back: the
/// JSON its class docs give, read strictly, since it is our own wire.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:checked_json/checked_json.dart' show JsonObject;
import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId;
import 'package:is_logbook_format/is_logbook_format.dart' show Kind, ObjectId;
import 'package:is_shapes/is_shapes.dart'
    show DecidedBy, MissionId, TrajectoryId;
import 'package:is_web_address_vocabulary/is_web_address_vocabulary.dart'
    show AddressPrefix, decodeAddressPrefix, encodeAddressPrefix;

import 'decision.dart';
import 'translated_event.dart';
import 'translated_event_wire.dart';

/// [decision] as the entry the docking station sends: its kind, and its body.
(Kind, Uint8List) encodeDecision(AdmissionDecision decision) {
  final json = <String, Object?>{
    if (decision case DecidedAtEvent(:final event)) 'event': event.hex,
    'by': decision.by.name,
  };
  switch (decision) {
    case EventAdmittedToMission():
      json['translatedEvent'] = encodeTranslatedEvent(decision.translatedEvent);
      switch (decision.placement) {
        case OnTrajectory(:final trajectory):
          json['trajectory'] = trajectory.hex;
        case StartsTrajectory(:final mission):
          json['startsTrajectory'] = true;
          _mission(json, mission);
        case IntoMission(:final mission):
          _mission(json, mission);
      }
      if (decision.rules case final rules?) json['rules'] = rules;
      if (decision.replyEndpoint case final endpoint?) {
        json['replyEndpoint'] = encodeAddressPrefix(endpoint);
      }
      if (decision.startsTurn case final startsTurn?) {
        json['startsTurn'] = startsTurn;
      }
    case MissionEnded(:final mission):
      json['mission'] = mission.hex;
    case TrajectoryClosedBecausePersonAsked(
      :final translatedEvent,
      :final trajectory,
      :final mission,
    ):
      json
        ..['translatedEvent'] = encodeTranslatedEvent(translatedEvent)
        ..['trajectory'] = trajectory.hex
        ..['mission'] = mission.hex;
    case TrajectoryClosedByOperator(
      :final trajectory,
      :final mission,
      :final operator,
      :final reason,
    ):
      json
        ..['trajectory'] = trajectory.hex
        ..['mission'] = mission.hex
        ..['operator'] = operator.value
        ..['reason'] = reason;
    case EventNotAdmittedToMission():
      json['why'] = _why(decision);
      if (decision case NotAdmittedKeyedEvent(
        :final addressInExternalSystem,
        :final key,
      )) {
        json
          ..['addressInExternalSystem'] = addressInExternalSystem.value
          ..['key'] = key.value;
      }
      switch (decision) {
        case DuplicateEvent(:final of):
          json['of'] = of.hex;
        case ChangeToUnadmittedMessage(:final message):
          json['message'] = message.value;
        case _:
          break;
      }
  }
  final kind = switch (decision) {
    EventAdmittedToMission() => DecisionEntryKind.eventAdmittedToMission,
    EventNotAdmittedToMission() => DecisionEntryKind.eventNotAdmittedToMission,
    MissionEnded() => DecisionEntryKind.missionEnded,
    TrajectoryClosed() => DecisionEntryKind.trajectoryClosed,
  };
  return (kind, Uint8List.fromList(utf8.encode(jsonEncode(json))));
}

void _mission(Map<String, Object?> json, MissionPlacement mission) {
  switch (mission) {
    case InMission(:final mission):
      json['mission'] = mission.hex;
    case StartsMission():
      json['startsMission'] = true;
  }
}

String _why(EventNotAdmittedToMission declined) => switch (declined) {
  NoTranslatorForSource() => 'no-translator-for-source',
  TranslatorFoundNothing() => 'translator-found-nothing',
  DuplicateEvent() => 'duplicate-event',
  AddressNotAdmittedToMission() => 'address-not-admitted-to-mission',
  SaidStartsNoTurn() => 'said-starts-no-turn',
  JudgedMessageHasNoTrajectory() => 'judged-message-has-no-trajectory',
  CloseAskedAtAddressWithNoTrajectory() =>
    'close-asked-at-address-with-no-trajectory',
  ChangeToUnadmittedMessage() => 'change-to-unadmitted-message',
};

/// The entry of [kind] with [body], read back as the decision it holds.
/// Null for anything [encodeDecision] doesn't write, an extra field
/// included: it is our own wire, read strictly.
AdmissionDecision? decodeDecision(Kind kind, Uint8List body) {
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(body));
  } on FormatException {
    return null;
  }
  if (json is! Map<String, Object?>) return null;
  final by = _read(json['by'], _decidedBy);
  if (by == null) return null;
  // A close by an operator is the one decision at no event.
  if (kind == DecisionEntryKind.trajectoryClosed &&
      !json.containsKey('event')) {
    return _closedByOperator(by, json);
  }
  final event = _read(json['event'], ObjectId.parse);
  if (event == null) return null;
  if (kind == DecisionEntryKind.eventAdmittedToMission) {
    return _admitted(event, by, json);
  }
  if (kind == DecisionEntryKind.eventNotAdmittedToMission) {
    return _notAdmitted(event, by, json);
  }
  if (kind == DecisionEntryKind.missionEnded) {
    final mission = _read(json['mission'], MissionId.parse);
    if (mission == null || json.length != 3) return null;
    return MissionEnded(event, by: by, mission: mission);
  }
  if (kind == DecisionEntryKind.trajectoryClosed) {
    return _closed(event, by, json);
  }
  return null;
}

TrajectoryClosedBecausePersonAsked? _closed(
  ObjectId event,
  DecidedBy by,
  Map<String, Object?> json,
) {
  final translatedEvent = _translatedEvent(json);
  final trajectory = _read(json['trajectory'], TrajectoryId.parse);
  final mission = _read(json['mission'], MissionId.parse);
  if (translatedEvent is! PersonAskedToCloseTrajectory ||
      trajectory == null ||
      mission == null ||
      json.length != 5) {
    return null;
  }
  return TrajectoryClosedBecausePersonAsked(
    event,
    by: by,
    translatedEvent: translatedEvent,
    trajectory: trajectory,
    mission: mission,
  );
}

TrajectoryClosedByOperator? _closedByOperator(
  DecidedBy by,
  Map<String, Object?> json,
) {
  final trajectory = _read(json['trajectory'], TrajectoryId.parse);
  final mission = _read(json['mission'], MissionId.parse);
  final operator = _read(json['operator'], OperatorName.parse);
  final reason = json['reason'];
  if (by != DecidedBy.person ||
      trajectory == null ||
      mission == null ||
      operator == null ||
      reason is! String ||
      reason.trim().isEmpty ||
      json.length != 5) {
    return null;
  }
  return TrajectoryClosedByOperator(
    trajectory: trajectory,
    mission: mission,
    operator: operator,
    reason: reason,
  );
}

/// The `translatedEvent` field read back; null when it isn't one
/// [encodeTranslatedEvent] writes.
AddressedEvent? _translatedEvent(Map<String, Object?> json) {
  try {
    return decodeTranslatedEvent(
      JsonObject.parse(json['translatedEvent']) ??
          (throw const FormatException('`translatedEvent` is not an object')),
    );
  } on FormatException {
    return null;
  }
}

/// The [DecidedBy] named [name]; null for any other name.
DecidedBy? _decidedBy(String name) => DecidedBy.values.asNameMap()[name];

EventAdmittedToMission? _admitted(
  ObjectId event,
  DecidedBy by,
  Map<String, Object?> json,
) {
  final AdmissibleEvent translatedEvent;
  if (_translatedEvent(json) case final AdmissibleEvent admissible) {
    translatedEvent = admissible;
  } else {
    return null;
  }
  final fields = {'event', 'by', 'translatedEvent'};

  final AdmittedPlacement placement;
  if (json.containsKey('trajectory')) {
    final trajectory = _read(json['trajectory'], TrajectoryId.parse);
    if (trajectory == null) return null;
    fields.add('trajectory');
    placement = OnTrajectory(trajectory);
  } else {
    final mission = _readMission(json, fields);
    if (mission == null) return null;
    if (json.containsKey('startsTrajectory')) {
      if (json['startsTrajectory'] != true) return null;
      fields.add('startsTrajectory');
      placement = StartsTrajectory(mission);
    } else {
      placement = IntoMission(mission);
    }
  }
  JsonObject? rules;
  if (json.containsKey('rules')) {
    rules = JsonObject.parse(json['rules']);
    if (rules == null) return null;
    fields.add('rules');
  }
  AddressPrefix? replyEndpoint;
  if (json.containsKey('replyEndpoint')) {
    try {
      replyEndpoint = decodeAddressPrefix(
        json['replyEndpoint'],
        'replyEndpoint',
      );
    } on FormatException {
      return null;
    }
    fields.add('replyEndpoint');
  }
  bool? startsTurn;
  if (json.containsKey('startsTurn')) {
    if (json['startsTurn'] case final bool value) {
      startsTurn = value;
    } else {
      return null;
    }
    fields.add('startsTurn');
  }
  if (json.length != fields.length) return null;
  if ((rules != null) != EventAdmittedToMission.starts(placement)) return null;
  if ((startsTurn != null) != (translatedEvent is MessageSaid)) return null;
  if (placement is StartsTrajectory && startsTurn == false) return null;
  final decision = EventAdmittedToMission(
    event,
    by: by,
    translatedEvent: translatedEvent,
    placement: placement,
    rules: rules,
    startsTurn: startsTurn,
  );
  // The copy is exactly the translated event's endpoint on an entry that
  // starts something, and absent otherwise.
  if (replyEndpoint != decision.replyEndpoint) return null;
  return decision;
}

MissionPlacement? _readMission(Map<String, Object?> json, Set<String> fields) {
  final inMission = json.containsKey('mission');
  final starts = json.containsKey('startsMission');
  if (inMission == starts) return null;
  if (inMission) {
    final mission = _read(json['mission'], MissionId.parse);
    if (mission == null) return null;
    fields.add('mission');
    return InMission(mission);
  }
  if (json['startsMission'] != true) return null;
  fields.add('startsMission');
  return const StartsMission();
}

EventNotAdmittedToMission? _notAdmitted(
  ObjectId event,
  DecidedBy by,
  Map<String, Object?> json,
) {
  final why = json['why'];
  if (why is! String) return null;
  if (why == 'no-translator-for-source' || why == 'translator-found-nothing') {
    if (json.length != 3) return null;
    return why == 'no-translator-for-source'
        ? NoTranslatorForSource(event, by: by)
        : TranslatorFoundNothing(event, by: by);
  }
  final addressInExternalSystem = _read(
    json['addressInExternalSystem'],
    AddressInExternalSystem.parse,
  );
  final key = _read(json['key'], EventKey.parse);
  if (addressInExternalSystem == null || key == null) return null;
  switch (why) {
    case 'duplicate-event':
      final of = _read(json['of'], ObjectId.parse);
      if (of == null || json.length != 6) return null;
      return DuplicateEvent(
        event,
        by: by,
        addressInExternalSystem: addressInExternalSystem,
        key: key,
        of: of,
      );
    case 'change-to-unadmitted-message':
      final message = _read(json['message'], SourceMessageId.parse);
      if (message == null || json.length != 6) return null;
      return ChangeToUnadmittedMessage(
        event,
        by: by,
        addressInExternalSystem: addressInExternalSystem,
        key: key,
        message: message,
      );
    case 'address-not-admitted-to-mission' ||
        'said-starts-no-turn' ||
        'judged-message-has-no-trajectory' ||
        'close-asked-at-address-with-no-trajectory':
      if (json.length != 5) return null;
      return switch (why) {
        'address-not-admitted-to-mission' => AddressNotAdmittedToMission(
          event,
          by: by,
          addressInExternalSystem: addressInExternalSystem,
          key: key,
        ),
        'said-starts-no-turn' => SaidStartsNoTurn(
          event,
          by: by,
          addressInExternalSystem: addressInExternalSystem,
          key: key,
        ),
        'judged-message-has-no-trajectory' => JudgedMessageHasNoTrajectory(
          event,
          by: by,
          addressInExternalSystem: addressInExternalSystem,
          key: key,
        ),
        _ => CloseAskedAtAddressWithNoTrajectory(
          event,
          by: by,
          addressInExternalSystem: addressInExternalSystem,
          key: key,
        ),
      };
    default:
      return null;
  }
}

/// [value] parsed by [parse] when it is a string; null otherwise.
T? _read<T>(Object? value, T? Function(String) parse) =>
    value is String ? parse(value) : null;
