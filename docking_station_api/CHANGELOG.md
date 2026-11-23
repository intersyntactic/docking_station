Each version is tagged `docking_station_api-vX.Y.Z` on the commit it is
published from. Versions up to 0.3.0 were published as
`is_admission_vocabulary` and tagged `admission_vocabulary-vX.Y.Z`.

## 0.4.0

Breaking, in code and in the logbook. Published only into a fresh logbook:
a reader on 0.4.0 refuses 0.3.0's entries, and a reader on 0.3.0 refuses
0.4.0's.

- A module's "reading" is its translator, since it turns each of its
  relay's events into the docking station's terms, carrying state from one
  event to the next:
  - `ModuleReading<S>` is `TranslatesRelayedEvents<S>`.
  - `EventReading` is `TranslatedEvent`.
  - `encodeReading` and `decodeReading` are `encodeTranslatedEvent` and
    `decodeTranslatedEvent`; `readingNodeShapes` is
    `translatedEventNodeShapes`.
  - `NoReadingForSource` is `NoTranslatorForSource`, and
    `ReadingFoundNothing` is `TranslatorFoundNothing`.
  - `EventAdmittedToMission.reading` and
    `TrajectoryClosedBecausePersonAsked.reading` are `.translatedEvent`.
- In the entries: the `reading` field of `event-admitted-to-mission` and
  `trajectory-closed` is `translatedEvent`, and the `why`s
  `no-reading-for-source` and `reading-found-nothing` are
  `no-translator-for-source` and `translator-found-nothing`.

## 0.3.0

- Published as `is_docking_station_api`, the same code as
  `is_admission_vocabulary` 0.3.0. Imports become
  `package:is_docking_station_api/is_docking_station_api.dart` and
  `package:is_docking_station_api/path_start.dart`.

- A trajectory can be closed by an operator, from outside its
  conversation: `TrajectoryClosedByOperator`, with the operator's
  `OperatorName` and a reason, decided by a person and at no event. Its entry
  is a `trajectory-closed`, so the logbook closes the trajectory's chains as
  for any close:
  `{"by": "person", "trajectory", "mission", "operator", "reason"}`.
- `TrajectoryClosed` is sealed, holding `trajectory` and `mission`; a close a
  person asked for at the address is `TrajectoryClosedBecausePersonAsked`,
  whose entry is unchanged. A reader matching `TrajectoryClosed(:trajectory)`
  takes both cases with no change.
- Breaking: `event` moved off `AdmissionDecision` to the new sealed
  `DecidedAtEvent`, which every decision but the operator's close is. Read
  it with `if (d case DecidedAtEvent(:final event))`. A reader on 0.2.x reads
  an operator's close as no decision at all, so move to 0.3.0 before one is
  written.

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
