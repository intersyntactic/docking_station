# docking_station

The docking station is the core piece that lets the outside world into
trajectories. Something outside, such as Teams, sends bytes unasked. Its
relay keeps them in the logbook exactly as they came, as an *event*. The
docking station reads events from the logbook in order and decides, for each
one, whether it comes in and where it goes.

It is the airlock's opposite. The airlock decides what leaves a trajectory
for the world. The docking station decides what comes into one. On the way
back, it only says which address an answer goes to: sending the answer is an
effect, so the airlock decides that.

## Two packages

| Folder | Package | What it is | Tags |
|---|---|---|---|
| `docking_station_api/` | `is_docking_station_api`, on pub.dev (formerly `is_admission_vocabulary`) | The docking station's contract, what other repos import: the events a module translates, the decisions recorded, and their logbook encoding | `docking_station_api-vX.Y.Z` |
| `service/` | `docking_station_service`, never published | The docking station itself: how it decides, the rules it runs under, and the program | `service-vX.Y.Z` |

A package other repos import never contains a service. So the service
takes the contract from pub.dev like every other reader, and nothing
imports the service. A deploy names a `service-vX.Y.Z` tag.

The service still takes it as `is_admission_vocabulary`, because the Teams
module it builds with does: a class from one package is a different type
from the same-named class in the other, so both move together.

## How a module takes part: it describes, and decides nothing

A module, such as the Teams module, takes part only by giving the docking
station a *translator* (`TranslatesRelayedEvents`). The docking station hands
the translator every event from the module's relay, in the logbook's order.
For each one, the translator says what it is in the docking station's terms.
The docking station never reads a module's bytes itself, and the module never
learns where anything went. The cases a translated event names are in
`docking_station_api/README.md`.

A translator gives one answer per event and carries state from one event to
the next, which the docking station never looks inside, because some events
can only be translated with what came before. A quoted message's author is
known from earlier events, and an edit has to be matched to the message it
edits. On every start the docking station steps it again from the logbook's
beginning, so a translator must give the same answer for the same events in
the same order.

## Missions and trajectories

An address in an external system that holds threads, such as a Teams
channel, is a *mission*, and each of its threads is one of that mission's
*trajectories*. An address with no threads, such as a chat, is a mission
with one trajectory. A mission holds the people working in it and its
trajectories, and a trajectory is one agent's line of turns.

Whether an address with no mission yet starts one is the docking station's
first rule, `DecidesWhichAddressStartsAMission`. It is asked about the
outermost address, a channel or a chat, on its first event, and its answer
(the mission's rules, or none) is recorded. Every thread within then joins
the mission without asking. Whether something said starts a turn is the
second, `TurnRule`. Each rule is asked at most once per event, and what it
answered is kept in the decision, so a rule can change between restarts
without changing anything already decided.

Every event is decided exactly once and recorded as one entry, on one chain:

| Entry kind | When |
|---|---|
| `event-admitted-to-mission` | The event comes in, on a trajectory or into a mission |
| `event-not-admitted-to-mission` | It stays out; `why` says which case |
| `trajectory-closed` | A person at the address asked to close a trajectory, or an operator closed it; the logbook closes its chains |
| `mission-ended` | A mission is over; the logbook closes its chains |

The start entry, `docking-station-set-up`, is written once at setup by
infra's `logbook-setup` user, never by the docking station.

An operator closes a trajectory from outside its conversation with
`service/bin/close_trajectory.dart`, a command that runs once on the
docking station's machine. It reads the docking station's decisions, takes
the trajectory's mission from them, and adds the close to the same chain,
naming no event. It runs as its own user, which the logbook's sender table
lets send `trajectory-closed` and nothing else, so no request into the
running docking station can close anything. The running docking station
need not stop: whichever of the two sends second is told it is not the
chain's tip, reads the other's entry, and goes on.

## What a module never does

A module never composes trajectories, never keeps which address is under
which trajectory, and never runs an agent loop. Working with many
trajectories is the core's job, so every module that brings addresses in
uses the same one.
