Each version is tagged `service-vX.Y.Z` on the commit it is built from, and a
deploy names the tag.

## 0.11.0

The 0.10 set: is_docking_station_api ^0.10.0, is_conversation_vocabulary
^0.2.0 (in place of is_conversation_shapes), checked_json ^0.4.0,
is_flight_rules ^0.11.0 and teams_module v0.0.18 (commit 7f478bf, pinned by sha because the tag is annotated), which bring is_relay
0.7.0, is_effects 0.19.0 and is_airlock_api 0.25.0. The checked_json 0.3
step is skipped (agreed with infra, 28 Nov).

**Deploys with every reader of admissions on api 0.10, or after them,
never before.** Admissions this service writes now carry a
`conversationKind` on every message said, and a Slack reply endpoint is
written `with-pinned-body-fields`. A reader on api 0.8 or 0.9 refuses both.
The readers are agent_loop, loop_launcher (is_loop_launcher-v0.7.0) and
the airlock. A 0.10 reader also reads every entry already written, so the
readers can go first.

Teams messages say their kind of conversation: one-to-one, group chat, or
not known (a channel, which a bot activity can't tell apart). Nothing acts
on the kind yet.

**The config file and the flight-rules file are now read refusing an
object that names a key twice.** Before, the last value won without a
word. A file with a repeated key now stops the service at startup, naming
the file. syd's live files and infra main's copies were checked on
28 Nov and have none.

## 0.10.0

On teams_module v0.0.16 (commit de3f348, pinned by sha because the tag is
annotated), up from v0.0.13. That brings is_relay 0.5.1, which writes with
is_logbook_client ^0.4.0, the same client this service reads with. v0.0.15
couldn't be used: its is_relay 0.5.0 locks client 0.3.0.

**Deploys together with the Teams relay on v0.0.16.** From v0.0.15 on, a
`teams-event` entry holds a projection (`"projection": 1` and only the
fields the module reads), and this service reads it strictly. An entry the
older relay wrote, a raw Teams activity, now reads as nothing to admit,
including on a replay from the start of the logbook. A relay left on
v0.0.13 against this service would have every Teams event decided
`translator-found-nothing`, with no error raised.

Also from v0.0.14: a reply footer counts the turn and the step. The api
stays on ^0.8.0 and checked_json on 0.2.x, since teams_module hasn't moved
to api 0.9 yet. The is_lint_rules plugin is loaded, with no findings.

## 0.9.0

On is_logbook_client ^0.4.0, which reads is_logbook 0.5.0's entry lines,
now with a trajectory word on each. 0.8.0's client 0.3.0 refuses every
entry from a 0.5.0 logbook, and this one reads only 0.5.0's, so it deploys
together with the logbook's move to 0.5.0.

Also off is_reply_vocabulary, onto its new name
is_conversation_reply_vocabulary: is_docking_station_api ^0.8.0, which no
longer re-exports the reply types, is_flight_rules ^0.9.0 with is_effects
0.17.0, and teams_module v0.0.13.

## 0.8.0

The ReplyEndpoint window's build, on the set frozen at 25 Nov 16:51 AEDT
so all five builds in it lock the same versions: is_docking_station_api
^0.7.0 with is_reply_vocabulary 0.2.0 (JSON unchanged), is_flight_rules
^0.7.0 (JSON unchanged apart from refusing a badly formed tool name) with
is_effects 0.15.0, and teams_module v0.0.11. Goes live under the same
condition as 0.6.0, which never deployed; 0.7.0 was never released.

## 0.6.0

On is_docking_station_api ^0.5.0 and teams_module v0.0.9, for the
ReplyEndpoint window. A start entry's reply endpoint is the sealed
`ReplyEndpoint` (`{"case": "under-web-address", ...}`), which 0.5.x's
readers can't read and 0.5.x wrote in a form this can't read, so it goes
live only while the logbook holds no start entries, alongside the airlock,
agent_loop and loop_launcher releases that read the same form.

## 0.5.1

- On teams_module v0.0.8, the commit the flight_rules 0.6.0 window deploys,
  so every build in it locks one teams_module.

## 0.5.0

On is_flight_rules ^0.6.0, and is_effects 0.14.3 through it. The rules
config must be in 0.6.0's shape: each mission's rules carry `givenTools`
(an empty list is valid), and a query option is
`{"name", "presence", "wordsFrom"}` under `queryOptions`. The service reads
the config with `FlightRules.fromJson` and refuses to start on a file it
can't read, and 0.6.0 reads no 0.5.0 rules, so it starts only where no
trajectory was started under 0.5.0 rules.

## 0.4.1

- On teams_module v0.0.7, the commit the fresh-logbook window deploys, so
  every build in it locks one teams_module. Its translator reads events as
  v0.0.5's did: the "Close trajectory" message action it drops already
  admitted nothing.

## 0.4.0

Starts only on a fresh logbook: its entries are is_docking_station_api
0.4.0's and its rules are is_flight_rules 0.5.0's, neither of which reads
the earlier versions'.

- On is_docking_station_api ^0.4.0: a module gives a translator
  (`TranslatesRelayedEvents`), and `runDockingStation` takes `translators:`
  where it took `readings:`. The decisions it writes carry
  `translatedEvent`, and `no-translator-for-source` and
  `translator-found-nothing`.
- It subscribes to the events of its translators' sources alone, each the
  entries of `<source>-event`, so only the relay the sender table lets
  write that kind can give it an event. An event from a source it has no
  translator for is never received, so never decided. A translator added
  later is given its source's events from the start entry on. A body that
  names its own source is `no-translator-for-source`.
- An admission that starts a mission or a trajectory writes its translated
  event's reply endpoint beside its rules, as the contract's
  `EventAdmittedToMission` does.
- On is_flight_rules ^0.5.0: the rules config must be in its shape, since
  the service reads each mission's rules with `FlightRules.fromJson` and
  refuses to start on a file it can't read.
- On the teams_module whose `TeamsEventTranslator` implements the new
  interface, and on is_effects ^0.14.0 through it. The dependency override
  for teams_module's vocabulary is gone.

## 0.3.0

- `bin/close_trajectory.dart`: an operator closes one trajectory from
  outside its conversation, as a `TrajectoryClosedByOperator` on the docking
  station's own chain. It takes the mission from the docking station's
  decisions, refuses a trajectory that isn't open, and reads the chain again
  when the running docking station decided first. Exits 0 closed, 1 not
  open, 64 bad arguments, 65 not sent, 75 may or may not be in.
- The docking station takes an operator's close back like any decision: it
  forgets the trajectory, so the next message at its address starts a new
  one in the same mission.
- On is_admission_vocabulary ^0.3.0 and is_logbook_client ^0.3.0. teams_module
  stays pinned at v0.0.2 under a dependency override, since it declares
  ^0.1.0 but builds against 0.3.0 unchanged.
- Must be deployed before any operator's close is written: 0.2.0 reads one
  as a decision it can't read, and exits 65.

## 0.2.0

- The engine lives here: `decide`, `DecidedSoFar`, the rules and
  `runDockingStation` moved in from is_docking_station, which is retired.
- The rule for whether an address starts a mission is
  `DecidesWhichAddressStartsAMission`, formerly `JourneyRule`.
- Takes the readings and decisions from is_admission_vocabulary 0.1.0 on
  pub.dev, like every other reader, with no path override. Pins teams_module
  v0.0.2, which imports the same.
- The logbook is called the logbook throughout: `RecordNoRestartChanges` is
  `LogbookNoRestartChanges`, and the stop message says "the logbook's
  subscription ended". The start entry's writer is infra's `logbook-setup`.
- No change to what it decides or writes.

## 0.1.0

- The first versioned release of the docking station service.
- Flight rules are chosen by mission address: `--flight-rules` reads
  `{"default", "byMissionAddress"}`, each an is_flight_rules 0.3.0
  `FlightRules` with a required starting model.
- On is_docking_station 0.3.0. Pins teams_module v0.0.1, where every reading
  names the bot it was sent to (`addressedTo`) and a "Close trajectory"
  action on any message closes the trajectory at its address.
- A test builds the program with every module it pins.
