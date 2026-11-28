Each version is tagged `docking_station_api-vX.Y.Z` on the commit it is
published from. Versions up to 0.3.0 were published as
`is_admission_vocabulary` and tagged `admission_vocabulary-vX.Y.Z`.

## 0.9.0

Breaking in code only. The logbook's JSON is unchanged.

- Depends on is_conversation_vocabulary ^0.1.1 in place of both
  is_conversation_shapes and is_conversation_reply_vocabulary, which it
  merges. `UserSaid`, `WhatChanged`, `SourceMessageId` and `ReplyEndpoint`
  now come from it, as different Dart types from the old packages' ones, so
  a program that builds a `TranslatedEvent` moves to is_conversation_vocabulary
  in the same change.
- On checked_json ^0.3.0. Every entry is decoded refusing an object that
  names a field twice, where `jsonDecode` kept the last value without a
  word. Such an entry now reads as one this package does not write.
- On is_annotation_shapes ^0.4.0, its release on checked_json ^0.3.0.
  `VerdictOnShownMessage` is unchanged.
- `path_start.dart`, which the airlock imports, takes `ReplyEndpoint` from
  is_conversation_vocabulary's `reply_endpoint.dart` alone, and a test holds
  that it reaches none of that package's stranger-facing files (`UserSaid`,
  `Quote`, `WhatChanged`).
- `RelayedEventSource`, `encodeRelayedEvent`, `RelayedEvent` and the
  relayed entry's `{"at","bytes"}` are unchanged.

## 0.8.0

Breaking in code only. The logbook's JSON is unchanged.

- Depends on is_conversation_reply_vocabulary ^0.1.0, is_reply_vocabulary's
  new name, instead of the old name. `ReplyEndpoint` and the other reply
  types now come from the new package. Dart treats them as different
  types from is_reply_vocabulary's, so a program that still reaches
  is_reply_vocabulary, directly or through another package, must move
  to is_conversation_reply_vocabulary as well.
- No longer re-exports the reply types. `ReplyEndpoint`,
  `RepliesUnderWebAddress`, `RepliesInSlackConversation`, `SlackChannelId`,
  `SlackMessageTimestamp`, `encodeReplyEndpoint` and `decodeReplyEndpoint`
  are imported from is_conversation_reply_vocabulary, which a consumer
  depends on directly.

## 0.7.0

Breaking in code only. The logbook's JSON is unchanged.

- On is_reply_vocabulary ^0.2.0, so the re-exported `encodeReplyEndpoint`
  returns a checked_json `JsonObject` instead of a `Map`.
- path_start may reach checked_json, which is trusted: it reads fields of
  a value already decoded as JSON and decodes nothing a stranger shaped.

## 0.6.0

Breaking in code only. The logbook's JSON is unchanged, so 0.5.0 and
0.6.0 read each other's entries.

- `ReplyEndpoint`, its cases, `SlackChannelId` and
  `encodeReplyEndpoint` / `decodeReplyEndpoint` are now declared in
  [is_reply_vocabulary](https://pub.dev/packages/is_reply_vocabulary)
  and re-exported from both libraries here, so drivers and the airlock
  share one type without depending on this package. A package that also
  imports is_reply_vocabulary needs this version: 0.5.0 declares its own
  copy, which is a different type.
- `SlackThreadTimestamp` is now `SlackMessageTimestamp`, since a Slack
  timestamp names any message. The field is still `thread`.
- `RelayedEvent.bytes` is what the source's relay recorded: the bytes as
  they came, or only the fields its translator reads, where the rest can
  carry credentials.

## 0.5.0

Breaking, in code and in the logbook: a start entry's reply endpoint
changes shape, so 0.5.0 goes live only while the logbook holds no start
entries.

- Where replies go is `ReplyEndpoint`, sealed, one case for each way an
  external system takes replies:
  - `RepliesUnderWebAddress(prefix)`: replies go under a web address that
    names the conversation, as Teams' Bot Connector takes them. This is
    0.4.0's `AddressPrefix`, wrapped.
  - `RepliesInSlackConversation(origin, channel, thread?)`: Slack takes
    every reply at one address and names the conversation in the
    request's body, so the reply is confined by `channel` and `thread`, and
    `origin` is what a trajectory's rules allow it to reply through.
    `SlackChannelId` and `SlackThreadTimestamp` parse Slack's forms.
- `AddressedEvent.replyEndpoint`, `EventAdmittedToMission.replyEndpoint`
  and path_start's `EntryStartsTrajectory.replyEndpoint` are
  `ReplyEndpoint?`. path_start exports the type.
- In the entries it is
  `{"case": "under-web-address", "addressPrefix": {...}}` or
  `{"case": "in-slack-conversation", "origin", "channel", "thread"?}`,
  read strictly by `decodeReplyEndpoint`.

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
- A relayed event's source is its entry's kind, never its body, so the
  logbook's sender table vouches for it: each relay records its events as
  `<source>-event` (`teams-event`), and only that relay's user may write
  the kind. `RelayedEventSource` is the source, with its `kind` and
  `ofKind`. `RelayedEvent.read` takes the entry's kind, and the body is
  `{"at", "bytes"}` alone; a body that names a source is refused.
  `encodeRelayedEvent` writes one, for a relay. The kinds `event` and
  `arrived` are gone. `TranslatesRelayedEvents.source` is a
  `RelayedEventSource`.
- A close names the trajectory it closes:
  `PersonAskedToCloseTrajectory.trajectory`, the one the pressed reply was
  sent in, as the reply carries it (`"trajectory"` on the wire). So a close
  on an old reply closes that reply's trajectory, never whichever is open
  at the address now. It closes only the trajectory open at its address;
  any other is `CloseAskedForTrajectoryNotOpenAtAddress`
  (`close-asked-for-trajectory-not-open-at-address`), which replaces
  `CloseAskedAtAddressWithNoTrajectory`.
- Every translated event names where replies to it go:
  `AddressedEvent.replyEndpoint`, an `AddressPrefix` from
  is_web_address_vocabulary ^0.1.1, null when the module can't name one. It
  travels inside `translatedEvent` as `replyEndpoint`, written by
  `encodeAddressPrefix`. An admission that starts a mission or a trajectory
  copies it to the entry's top level beside `rules`
  (`EventAdmittedToMission.replyEndpoint`), and path_start reads it there
  (`EntryStartsTrajectory.replyEndpoint`), so the airlock has it without
  decoding the translated event. A copy that differs from the translated
  event's, or one on an entry that starts nothing, makes the entry
  unreadable.
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
