# is_admission_vocabulary

What other parts of intersyntactic import to speak with the docking station,
and nothing of how it decides.

The docking station reads events from the record in order and decides, for
each, whether it comes into a mission and on which trajectory. Two sides
need its words without needing its engine:

- **A module**, such as the Teams module, describes each event its relay
  recorded. It implements `ModuleReading`, a fold over `RelayedEvent`s, and
  gives an `EventReading` for each.
- **A reader of the record**, such as loop_launcher, agent_loop or the
  airlock, reads the decisions the docking station recorded.

So this package holds exactly those words and their encoding in the logbook.
How the docking station decides (`decide`, what it has decided so far, its
rules, and the loop that runs it) lives in the docking station service,
which nothing else imports.

## Readings in

For each event a module's reading names the address it belongs to, what that
address sits within (the channel a thread is in, or nothing), who it comes
from, the bot it was sent to as the external system verified it
(`addressedTo`), its event key (what "never decided twice" compares), and
what it is:

| Case | What it is |
|---|---|
| `MessageSaid` | Something said, with the `UserSaid` node the trajectory appends |
| `MessageChanged` | An edit, delete or restore of an earlier message |
| `ActorsJoinedAddress` | People or the agent joined an address |
| `ShownMessageJudged` | A person's verdict on something the agent showed them |
| `PersonAskedToCloseTrajectory` | A person asked to close the trajectory at an address |
| `NothingToAdmit` | Anything the module doesn't carry |

`encodeReading` and `decodeReading` write and read a reading as the decision
entries carry it, strictly.

## Decisions out

The docking station records one entry per event, each of a kind in
`DecisionEntryKind`:

| Entry kind | Decision |
|---|---|
| `event-admitted-to-mission` | `EventAdmittedToMission`: on a trajectory, starting one, or into a mission |
| `event-not-admitted-to-mission` | One of `EventNotAdmittedToMission`'s cases; `why` says which |
| `trajectory-closed` | `TrajectoryClosed`: a person closed a trajectory |
| `mission-ended` | `MissionEnded`: a mission is over |

`decodeDecision` reads any of them back, strictly: an entry it doesn't
recognise, an extra field included, is null.

## For the airlock: `path_start.dart`

`package:is_admission_vocabulary/path_start.dart` reads an
`event-admitted-to-mission` entry only for the trajectory it starts and that
trajectory's rules. It never decodes the reading, which is what strangers
sent, and a test walks its import graph to hold that.

## Versions

Each release is tagged `admission_vocabulary-vX.Y.Z` on the commit it is
published from; see `CHANGELOG.md`.
