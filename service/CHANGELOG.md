Each version is tagged `service-vX.Y.Z` on the commit it is built from, and a
deploy names the tag.

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
