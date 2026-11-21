Each version is tagged `admission_vocabulary-vX.Y.Z` on the commit it is
published from.

## 0.1.0

- The vocabulary other repos import to speak with the docking station, split
  out of is_docking_station 0.3.0 with no change to any type or to the wire:
  readings (`ModuleReading`, `EventReading` and its cases, `RelayedEvent`),
  decisions (`AdmissionDecision` and its cases), their logbook encoding
  (`encodeReading`, `decodeReading`, `encodeDecision`, `decodeDecision`,
  `DecisionEntryKind`), and `path_start.dart` for the airlock.
- How the docking station decides (`decide`, `DecidedSoFar`, its rules and
  `runDockingStation`) is not here: it lives in the docking station service,
  which nothing else imports.
