The changelog of `is_docking_station`, tagged `vX.Y.Z`. Its last version is
0.3.0: after it, the readings and decisions went on as
`is_admission_vocabulary`, now `is_docking_station_api`
(`docking_station_api/CHANGELOG.md`), and the
engine moved into the service (`service/CHANGELOG.md`).

## 0.3.0

- Every reading names the bot the event was sent to, `addressedTo`, an
  `ActorId` the external system verified (such as the audience of the token
  Teams signed it with), or null when the module can't verify one. On the
  wire it is `"addressedTo"` in the reading, left out when null. A reader on
  0.2.0 refuses a reading that has it, so move every reader to 0.3.0 before
  deploying a module that fills it.

## 0.2.0

- A person can close a trajectory. The reading `PersonAskedToCloseTrajectory`
  (who asked, and the message they picked it on) is decided as
  `TrajectoryClosed`, an entry of the logbook's kind `trajectory-closed`
  naming the trajectory and its mission, or declined as
  `close-asked-at-address-with-no-trajectory`. The trajectory is found by its
  address, so a close picked on the agent's own reply or card counts. The
  address's next message starts a new trajectory in the same mission.
- Breaking: `AddressedEvent` now sits between `EventReading` and
  `AdmissibleEvent`, holding the address, key and sender, and has the new
  reading as its second case. `encodeReading` and `decodeReading` take and
  give an `AddressedEvent`. `AdmissionDecision` and `EventNotAdmittedToMission`
  each gain a case, so exhaustive switches over them need one more arm.

## 0.1.0

- First release on pub.dev. Reads events from the logbook in order and writes
  one decision for each: admitted to a mission (starting a trajectory, on one,
  or into a mission), not admitted, or the mission ended.
- `readTrajectoryStart` in `path_start.dart`, the airlock's narrow reader of a
  trajectory's start entry.
- On is_shapes ^0.6.0, is_conversation_shapes ^0.8.3, is_annotation_shapes
  ^0.3.2, is_logbook ^0.2.1 and is_logbook_client ^0.2.0.
