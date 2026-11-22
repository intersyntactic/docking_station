# docking_station

The docking station is the core piece that lets the outside world into
trajectories. Something outside, such as Teams, sends bytes unasked. Its
relay keeps them in the record exactly as they came, as an *event*. The
docking station reads events from the record in order and decides, for each
one, whether it comes in and where it goes.

It is the airlock's opposite. The airlock decides what leaves a trajectory
for the world. The docking station decides what comes into one. On the way
back, it only says which address an answer goes to: sending the answer is an
effect, so the airlock decides that.

## Two packages

| Folder | Package | What it is | Tags |
|---|---|---|---|
| `admission_vocabulary/` | `is_admission_vocabulary`, on pub.dev | What other repos import: the readings a module gives, the decisions recorded, and their logbook encoding | `admission_vocabulary-vX.Y.Z` |
| `service/` | `docking_station_service`, never published | The docking station itself: how it decides, the rules it runs under, and the program | `service-vX.Y.Z` |

A package other repos import never contains a service. So the service
takes the vocabulary from pub.dev like every other reader, and nothing
imports the service. A deploy names a `service-vX.Y.Z` tag.

## How a module takes part: it describes, and decides nothing

A module, such as the Teams module, takes part only by giving the docking
station a *reading* (`ModuleReading`). The docking station hands the reading
every event from the module's relay, in the record's order. For each one,
the reading says what it is. The docking station never reads a module's
bytes itself, and the module never learns where anything went. The cases a
reading names are in `admission_vocabulary/README.md`.

A reading is a fold. It keeps state of its own, which the docking station
never looks inside, because some events can only be read with what came
before. A quoted message's author is known from earlier events, and an edit
has to be matched to the message it edits. On every start the docking
station folds again from the record's beginning, so a reading must give the
same answer for the same events in the same order.

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
| `trajectory-closed` | A person closed a trajectory; the logbook closes its chains |
| `mission-ended` | A mission is over; the logbook closes its chains |

The start entry, `docking-station-set-up`, is written once at setup by
infra's `record-setup` user, never by the docking station.

## What a module never does

A module never composes trajectories, never keeps which address is under
which trajectory, and never runs an agent loop. Working with many
trajectories is the core's job, so every module that brings addresses in
uses the same one.
