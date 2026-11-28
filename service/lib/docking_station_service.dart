/// The docking station: how it decides each event ([decide], under the rules
/// passed in, [DecidesWhichAddressStartsAMission] and [TurnRule];
/// [DecidedSoFar], what its decisions add up to when read back;
/// [runDockingStation], which reads the logbook and sends each decision to
/// it), and the rules it runs under for now: a list of the addresses in
/// external systems let in, the flight rules each mission they start is
/// admitted under, and every message said starting a turn.
///
/// The list and the turn rule stand in for calls still open, where a new
/// chat or channel comes in by a rule rather than by a person's yes. Which
/// flight rules a mission gets is chosen by the address it is: a channel or
/// a chat.
///
/// Nothing outside this service imports it. What other repos share with the
/// docking station is in is_docking_station_api.
library;

import 'package:checked_json/checked_json.dart'
    show JsonFieldException, JsonObject;
import 'package:is_docking_station_api/is_docking_station_api.dart';
import 'package:is_flight_rules/is_flight_rules.dart';

import 'src/rules.dart';

export 'src/close_by_operator.dart';
export 'src/decide.dart';
export 'src/decided.dart';
export 'src/rules.dart';
export 'src/run.dart';

/// The addresses in external systems whose missions come in, each under the
/// flight rules [flightRules] gives its address. A channel on the list lets
/// in each of its threads, as the mission they sit in; a chat on the list
/// lets itself in. Anything else is not taken in.
///
/// The list is read from the service's config file, a JSON object:
///
///     {"addressesLetIn": ["teams:19:abc@thread.tacv2", ...]}
///
/// Read strictly: an unknown key, an address that isn't one, an address
/// named twice, or an empty list refuses the whole file, since a service
/// that started with half a list would turn away missions nobody meant to.
final class AddressesLetIn implements DecidesWhichAddressStartsAMission {
  AddressesLetIn._(this.addresses, this.flightRules)
    : _rulesByAddress = {
        for (final address in addresses)
          address: flightRules.forMission(address).toJson(),
      };

  /// The list in [config], the config file's contents, with [flightRules]
  /// for the missions it lets in. Throws a [FormatException] naming what is
  /// wrong, including flight rules given for an address not on the list,
  /// which no mission could ever start under.
  factory AddressesLetIn.parse(
    String config, {
    required FlightRulesByMissionAddress flightRules,
  }) {
    final json = _object(config, 'the config');
    _onlyKeys(json, const {'addressesLetIn'}, 'the config');
    final addresses = <AddressInExternalSystem>{};
    for (final text in json.strings('addressesLetIn')) {
      final address =
          AddressInExternalSystem.parse(text) ??
          (throw JsonFieldException(
            'addressesLetIn',
            'addresses: a system, a colon and its id, such as '
                'teams:19:abc@thread.v2',
          ));
      if (!addresses.add(address)) {
        throw FormatException('$address is named twice');
      }
    }
    if (addresses.isEmpty) {
      throw const FormatException('addressesLetIn names no address');
    }
    for (final address in flightRules.byMissionAddress.keys) {
      if (!addresses.contains(address)) {
        throw FormatException(
          'the rules file gives flight rules for $address, which '
          'addressesLetIn does not let in',
        );
      }
    }
    return AddressesLetIn._(Set.unmodifiable(addresses), flightRules);
  }

  /// The addresses on the list.
  final Set<AddressInExternalSystem> addresses;

  /// The flight rules each mission the list takes in is admitted under.
  final FlightRulesByMissionAddress flightRules;

  final Map<AddressInExternalSystem, JsonObject> _rulesByAddress;

  @override
  JsonObject? takeIn(AdmissibleEvent first) =>
      _rulesByAddress[first.containingAddress ?? first.addressInExternalSystem];
}

/// The rules file: the flight rules a mission is admitted under, by the
/// address it is, and the ones every other mission gets.
///
///     {"default": <flight rules>,
///      "byMissionAddress": [{"address": "teams:...", "rules": <flight rules>}]}
///
/// `<flight rules>` is what [FlightRules.fromJson] reads. Read strictly: an
/// unknown key at any level, a missing default, or an address that isn't one
/// or is named twice throws a [FormatException] naming the part, so a typo
/// stops the service before any mission starts under it.
final class FlightRulesByMissionAddress {
  FlightRulesByMissionAddress._(this.defaultRules, this.byMissionAddress);

  /// The rules file's contents, [text], read strictly.
  factory FlightRulesByMissionAddress.parse(String text) {
    final json = _object(text, 'the rules file');
    _onlyKeys(json, const {'default', 'byMissionAddress'}, 'the rules file');
    final defaultRules = FlightRules.fromJson(
      json.object('default'),
      'default',
    );
    final byMissionAddress = <AddressInExternalSystem, FlightRules>{};
    for (final (i, entry) in json.objects('byMissionAddress').indexed) {
      final field = 'byMissionAddress[$i]';
      _onlyKeys(entry, const {'address', 'rules'}, field);
      final address =
          AddressInExternalSystem.parse(entry.string('address')) ??
          (throw JsonFieldException(
            '$field.address',
            'an address: a system, a colon and its id',
          ));
      if (byMissionAddress.containsKey(address)) {
        throw FormatException('$address is given flight rules twice');
      }
      byMissionAddress[address] = FlightRules.fromJson(
        entry.object('rules'),
        '$field.rules',
      );
    }
    return FlightRulesByMissionAddress._(
      defaultRules,
      Map.unmodifiable(byMissionAddress),
    );
  }

  /// The flight rules for a mission the file names no address for.
  final FlightRules defaultRules;

  /// The flight rules for each mission address the file names.
  final Map<AddressInExternalSystem, FlightRules> byMissionAddress;

  /// The flight rules the mission [address] is admitted under.
  FlightRules forMission(AddressInExternalSystem address) =>
      byMissionAddress[address] ?? defaultRules;
}

/// A message starts a turn when its module says it is for the agent: said
/// where every message is, mentioning the agent, or replying to it. One
/// that does none of these, or whose module can't tell, is admitted and
/// read but starts no turn.
final class StartsATurnWhenForTheAgent implements TurnRule {
  const StartsATurnWhenForTheAgent();

  @override
  bool startsTurn(MessageSaid said, AdmittedPlacement placement) =>
      switch (said.forTheAgent) {
        WhetherForTheAgent.everyMessageHereIsForTheAgent ||
        WhetherForTheAgent.mentionsTheAgent ||
        WhetherForTheAgent.repliesToTheAgent => true,
        WhetherForTheAgent.neitherMentionsNorRepliesToTheAgent ||
        WhetherForTheAgent.notKnown => false,
      };
}

/// [text] as a JSON object, refusing one that names a key twice.
JsonObject _object(String text, String what) {
  try {
    return JsonObject.decode(text);
  } on FormatException catch (e) {
    throw FormatException('$what: ${e.message}');
  }
}

void _onlyKeys(JsonObject json, Set<String> allowed, String what) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('$what has a key it does not take: $key');
    }
  }
}
