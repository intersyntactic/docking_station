/// What other parts of intersyntactic import to speak with the docking
/// station, and nothing of how it decides.
///
/// Readings in: [ModuleReading], which a module implements, and the
/// [EventReading] it gives for each [RelayedEvent]. Decisions out:
/// [AdmissionDecision] and its cases, which the docking station records one
/// entry each. And the logbook encoding of both: [encodeReading] and
/// [decodeReading], [encodeDecision] and [decodeDecision], with the entry
/// kinds in [DecisionEntryKind].
///
/// A reader that only needs a trajectory's start and rules imports
/// `path_start.dart` instead, which never decodes what strangers sent.
library;

export 'src/decision.dart';
export 'src/decision_wire.dart';
export 'src/reading.dart';
export 'src/reading_wire.dart';
