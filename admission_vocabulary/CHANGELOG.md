Each version is tagged `admission_vocabulary-vX.Y.Z` on the commit it is
published from.

## 0.2.0

- Depends on the logbook's formats alone: `Kind` from is_logbook_format
  ^0.1.0 and `ObjectId` from is_content_id ^0.2.0. It no longer depends on
  is_logbook or is_logbook_client, so nothing that imports it carries the
  logbook's writer or its socket client. `path_start.dart` now reaches no
  logbook package at all, and its import-graph test holds that.
- `DecisionEntryKind.trajectoryClosed` is the logbook's own
  `Kind.trajectoryClosed`.
- Breaking only in that `Kind` is now is_logbook_format's class: move to
  is_logbook_client ^0.3.0 (or is_logbook ^0.3.1), which share it.

## 0.1.1

- Docs only: the logbook is called the logbook throughout, never "the
  record", and `PersonAskedToCloseTrajectory` names both ways a close is
  asked: the "Close trajectory" action on any message, and the Close button
  on the agent's card. Comments say what the code does, with no dated
  rulings or attributions. One test is renamed to "the logbook words are
  the ones promised to their readers". No type, name or wire change.

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
