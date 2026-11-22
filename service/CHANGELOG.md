Each version is tagged `service-vX.Y.Z` on the commit it is built from, and a
deploy names the tag.

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
