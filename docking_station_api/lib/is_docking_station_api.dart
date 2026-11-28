/// The docking station's contract: what other parts of intersyntactic import
/// to speak with the docking station, and nothing of how it decides.
///
/// Events in: [TranslatesRelayedEvents], which a module implements, and the
/// [TranslatedEvent] it gives for each [RelayedEvent]. Decisions out:
/// [AdmissionDecision] and its cases, which the docking station records one
/// entry each. And the logbook encoding of both: [encodeTranslatedEvent] and
/// [decodeTranslatedEvent], [encodeDecision] and [decodeDecision], with the
/// entry kinds in [DecisionEntryKind].
///
/// A reader that only needs a trajectory's start and rules imports
/// `path_start.dart` instead, which never decodes what strangers sent.
library;

export 'src/decision.dart';
export 'src/decision_wire.dart';
export 'src/translated_event.dart';
export 'src/translated_event_wire.dart';
export 'src/whether_for_the_agent.dart';
