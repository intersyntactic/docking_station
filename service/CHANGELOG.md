Each version is tagged `service-vX.Y.Z` on the commit it is built from, and a
deploy names the tag.

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
