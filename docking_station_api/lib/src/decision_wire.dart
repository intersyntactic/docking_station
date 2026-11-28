/// A decision as the logbook entry the docking station sends, and back: the
/// JSON its class docs give, read strictly, since it is our own wire.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:checked_json/checked_json.dart' show JsonObject;
import 'package:is_conversation_vocabulary/is_conversation_vocabulary.dart'
    show
        ReplyEndpoint,
        SourceMessageId,
        decodeReplyEndpoint,
        encodeReplyEndpoint;
import 'package:is_logbook_format/is_logbook_format.dart' show Kind, ObjectId;
import 'package:is_shapes/is_shapes.dart'
    show DecidedBy, MissionId, TrajectoryId;

import 'decision.dart';
import 'decision_format.dart';

import 'translated_event.dart';
import 'translated_event_wire.dart';

/// [decision] as the entry the docking station sends: its kind, and its body.
(Kind, Uint8List) encodeDecision(AdmissionDecision decision) {
  final json = <String, Object?>{
    decisionFormatField: decisionFormatWritten,
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
        json['replyEndpoint'] = encodeReplyEndpoint(endpoint);
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
        case NoTranslatorForSource() ||
            TranslatorFoundNothing() ||
            AddressNotAdmittedToMission() ||
            SaidStartsNoTurn() ||
            JudgedMessageHasNoTrajectory() ||
            CloseAskedForTrajectoryNotOpenAtAddress():
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

String _why(EventNotAdmittedToMission declined) =>
    _NotAdmittedWhy.of(declined).wire;

/// Why an event was not admitted, as the `why` field writes it.
enum _NotAdmittedWhy {
  noTranslatorForSource('no-translator-for-source'),
  translatorFoundNothing('translator-found-nothing'),
  duplicateEvent('duplicate-event'),
  addressNotAdmittedToMission('address-not-admitted-to-mission'),
  saidStartsNoTurn('said-starts-no-turn'),
  judgedMessageHasNoTrajectory('judged-message-has-no-trajectory'),
  closeAskedForTrajectoryNotOpenAtAddress(
    'close-asked-for-trajectory-not-open-at-address',
  ),
  changeToUnadmittedMessage('change-to-unadmitted-message');

  const _NotAdmittedWhy(this.wire);

  final String wire;

  static final _byWire = {for (final why in values) why.wire: why};

  /// The reason [wire] names; null for any other string.
  static _NotAdmittedWhy? parse(String wire) => _byWire[wire];

  static _NotAdmittedWhy of(EventNotAdmittedToMission declined) =>
      switch (declined) {
        NoTranslatorForSource() => noTranslatorForSource,
        TranslatorFoundNothing() => translatorFoundNothing,
        DuplicateEvent() => duplicateEvent,
        AddressNotAdmittedToMission() => addressNotAdmittedToMission,
        SaidStartsNoTurn() => saidStartsNoTurn,
        JudgedMessageHasNoTrajectory() => judgedMessageHasNoTrajectory,
        CloseAskedForTrajectoryNotOpenAtAddress() =>
          closeAskedForTrajectoryNotOpenAtAddress,
        ChangeToUnadmittedMessage() => changeToUnadmittedMessage,
      };
}

/// The entry of [kind] with [body], read back as the decision it holds.
/// Null for anything [encodeDecision] doesn't write, an extra field
/// included: it is our own wire, read strictly.
AdmissionDecision? decodeDecision(Kind kind, Uint8List body) {
  final JsonObject? json;
  try {
    json = withoutKnownDecisionFormat(JsonObject.decode(utf8.decode(body)));
  } on FormatException {
    return null;
  }
  if (json == null) return null;
  final by = _read(json.raw('by'), _decidedBy);
  if (by == null) return null;
  // A close by an operator is the one decision at no event.
  if (kind == DecisionEntryKind.trajectoryClosed && !json.has('event')) {
    return _closedByOperator(by, json);
  }
  final event = _read(json.raw('event'), ObjectId.parse);
  if (event == null) return null;
  if (kind == DecisionEntryKind.eventAdmittedToMission) {
    return _admitted(event, by, json);
  }
  if (kind == DecisionEntryKind.eventNotAdmittedToMission) {
    return _notAdmitted(event, by, json);
  }
  if (kind == DecisionEntryKind.missionEnded) {
    final mission = _read(json.raw('mission'), MissionId.parse);
    if (mission == null || json.keys.length != 3) return null;
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
  JsonObject json,
) {
  final translatedEvent = _translatedEvent(json);
  final trajectory = _read(json.raw('trajectory'), TrajectoryId.parse);
  final mission = _read(json.raw('mission'), MissionId.parse);
  if (translatedEvent is! PersonAskedToCloseTrajectory ||
      trajectory == null ||
      mission == null ||
      json.keys.length != 5) {
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

TrajectoryClosedByOperator? _closedByOperator(DecidedBy by, JsonObject json) {
  final trajectory = _read(json.raw('trajectory'), TrajectoryId.parse);
  final mission = _read(json.raw('mission'), MissionId.parse);
  final operator = _read(json.raw('operator'), OperatorName.parse);
  final reason = json.raw('reason');
  if (by != DecidedBy.person ||
      trajectory == null ||
      mission == null ||
      operator == null ||
      reason is! String ||
      reason.trim().isEmpty ||
      json.keys.length != 5) {
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
AddressedEvent? _translatedEvent(JsonObject json) {
  try {
    return decodeTranslatedEvent(
      JsonObject.parse(json.raw('translatedEvent')) ??
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
  JsonObject json,
) {
  final AdmissibleEvent translatedEvent;
  if (_translatedEvent(json) case final AdmissibleEvent admissible) {
    translatedEvent = admissible;
  } else {
    return null;
  }
  final fields = {'event', 'by', 'translatedEvent'};

  final AdmittedPlacement placement;
  if (json.has('trajectory')) {
    final trajectory = _read(json.raw('trajectory'), TrajectoryId.parse);
    if (trajectory == null) return null;
    fields.add('trajectory');
    placement = OnTrajectory(trajectory);
  } else {
    final mission = _readMission(json, fields);
    if (mission == null) return null;
    if (json.has('startsTrajectory')) {
      if (json.raw('startsTrajectory') != true) return null;
      fields.add('startsTrajectory');
      placement = StartsTrajectory(mission);
    } else {
      placement = IntoMission(mission);
    }
  }
  JsonObject? rules;
  if (json.has('rules')) {
    rules = JsonObject.parse(json.raw('rules'));
    if (rules == null) return null;
    fields.add('rules');
  }
  ReplyEndpoint? replyEndpoint;
  if (json.has('replyEndpoint')) {
    try {
      replyEndpoint = decodeReplyEndpoint(
        json.raw('replyEndpoint'),
        'replyEndpoint',
      );
    } on FormatException {
      return null;
    }
    fields.add('replyEndpoint');
  }
  bool? startsTurn;
  if (json.has('startsTurn')) {
    if (json.raw('startsTurn') case final bool value) {
      startsTurn = value;
    } else {
      return null;
    }
    fields.add('startsTurn');
  }
  if (json.keys.length != fields.length) return null;
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

MissionPlacement? _readMission(JsonObject json, Set<String> fields) {
  final inMission = json.has('mission');
  final starts = json.has('startsMission');
  if (inMission == starts) return null;
  if (inMission) {
    final mission = _read(json.raw('mission'), MissionId.parse);
    if (mission == null) return null;
    fields.add('mission');
    return InMission(mission);
  }
  if (json.raw('startsMission') != true) return null;
  fields.add('startsMission');
  return const StartsMission();
}

EventNotAdmittedToMission? _notAdmitted(
  ObjectId event,
  DecidedBy by,
  JsonObject json,
) {
  final why = _read(json.raw('why'), _NotAdmittedWhy.parse);
  if (why == null) return null;
  // The two reasons with no address: the event never became one.
  if (why
      case _NotAdmittedWhy.noTranslatorForSource ||
          _NotAdmittedWhy.translatorFoundNothing) {
    if (json.keys.length != 3) return null;
    return why == _NotAdmittedWhy.noTranslatorForSource
        ? NoTranslatorForSource(event, by: by)
        : TranslatorFoundNothing(event, by: by);
  }
  final addressInExternalSystem = _read(
    json.raw('addressInExternalSystem'),
    AddressInExternalSystem.parse,
  );
  final key = _read(json.raw('key'), EventKey.parse);
  if (addressInExternalSystem == null || key == null) return null;
  switch (why) {
    case _NotAdmittedWhy.noTranslatorForSource ||
        _NotAdmittedWhy.translatorFoundNothing:
      return null;
    case _NotAdmittedWhy.duplicateEvent:
      final of = _read(json.raw('of'), ObjectId.parse);
      if (of == null || json.keys.length != 6) return null;
      return DuplicateEvent(
        event,
        by: by,
        addressInExternalSystem: addressInExternalSystem,
        key: key,
        of: of,
      );
    case _NotAdmittedWhy.changeToUnadmittedMessage:
      final message = _read(json.raw('message'), SourceMessageId.parse);
      if (message == null || json.keys.length != 6) return null;
      return ChangeToUnadmittedMessage(
        event,
        by: by,
        addressInExternalSystem: addressInExternalSystem,
        key: key,
        message: message,
      );
    case _NotAdmittedWhy.addressNotAdmittedToMission:
      if (json.keys.length != 5) return null;
      return AddressNotAdmittedToMission(
        event,
        by: by,
        addressInExternalSystem: addressInExternalSystem,
        key: key,
      );
    case _NotAdmittedWhy.saidStartsNoTurn:
      if (json.keys.length != 5) return null;
      return SaidStartsNoTurn(
        event,
        by: by,
        addressInExternalSystem: addressInExternalSystem,
        key: key,
      );
    case _NotAdmittedWhy.judgedMessageHasNoTrajectory:
      if (json.keys.length != 5) return null;
      return JudgedMessageHasNoTrajectory(
        event,
        by: by,
        addressInExternalSystem: addressInExternalSystem,
        key: key,
      );
    case _NotAdmittedWhy.closeAskedForTrajectoryNotOpenAtAddress:
      if (json.keys.length != 5) return null;
      return CloseAskedForTrajectoryNotOpenAtAddress(
        event,
        by: by,
        addressInExternalSystem: addressInExternalSystem,
        key: key,
      );
  }
}

/// [value] parsed by [parse] when it is a string; null otherwise.
T? _read<T>(Object? value, T? Function(String) parse) =>
    value is String ? parse(value) : null;
