// What the service's config file lets in, and the flight rules each mission
// it lets in starts under: which files it reads, which it refuses to start
// with, and what the list then takes in.
import 'dart:convert';

import 'package:docking_station_service/docking_station_service.dart';
import 'package:is_conversation_vocabulary/is_conversation_vocabulary.dart'
    show ConversationKind, SourceMessageId, UserSaid;
import 'package:is_docking_station_api/is_docking_station_api.dart';
import 'package:is_shapes/is_shapes.dart' show ActorId;
import 'package:test/test.dart';

const _channel = 'teams:19:channel@thread.tacv2';
const _chat = 'teams:19:chat@thread.v2';

/// What may leave this machine, allowing model calls as [signIns].
Map<String, Object?> _whatMayLeave(List<String> signIns) => {
  'modelSignInsCallsMayGoOutAs': signIns,
  'fetchesMayReach': <Object?>[],
  'webRequestsMayReach': <Object?>[],
  'programsNetwork': 'noNetworkOfTheirOwn',
};

/// Flight rules starting on [model] as [signIn], allowing only it, running
/// no programs and giving no tools.
Map<String, Object?> _flightRules(String signIn, String model) => {
  'whatMayLeaveThisMachine': _whatMayLeave([signIn]),
  'startingModel': {'signIn': signIn, 'model': model},
  'programsItMayRun': <Object?>[],
  'programsItNeeds': <Object?>[],
  'givenTools': <Object?>[],
};

final _claude = _flightRules('claude-team', 'claude-opus-5-5');
final _chatGpt = _flightRules('cam-chatgpt', 'gpt-6.2-sol');

/// A rules file: Claude by default, ChatGPT for [_chat].
final _rulesFile = {
  'default': _claude,
  'byMissionAddress': [
    {'address': _chat, 'rules': _chatGpt},
  ],
};

FlightRulesByMissionAddress _readRules(Object? json) =>
    FlightRulesByMissionAddress.parse(jsonEncode(json));

final _rules = _readRules(_rulesFile);

String _config(Object? addressesLetIn) =>
    jsonEncode({'addressesLetIn': addressesLetIn});

AddressesLetIn _parse(String config, {FlightRulesByMissionAddress? rules}) =>
    AddressesLetIn.parse(config, flightRules: rules ?? _rules);

/// Something said at [address], in [containing], [forTheAgent] or not.
MessageSaid _said(
  String address, {
  String? containing,
  WhetherForTheAgent forTheAgent =
      WhetherForTheAgent.everyMessageHereIsForTheAgent,
}) => MessageSaid(
  addressInExternalSystem: AddressInExternalSystem.parse(address)!,
  containingAddress: containing == null
      ? null
      : AddressInExternalSystem.parse(containing)!,
  addressedTo: null,
  replyEndpoint: null,
  conversationKind: ConversationKind.notKnown,
  forTheAgent: forTheAgent,
  key: EventKey.parse('message:1')!,
  node: UserSaid(
    author: ActorId.parse('teams:t/p')!,
    source: SourceMessageId.parse('$address|1')!,
    text: 'hello',
  ),
);

/// [json] as it would read back from the logbook.
Object? _asWritten(Object? json) => jsonDecode(jsonEncode(json));

void main() {
  final list = _parse(_config([_channel, _chat]));

  group('takes in, under the flight rules for its mission address', () {
    test('a thread of a channel the rules file names no address for, under '
        'the default', () {
      expect(
        _asWritten(
          list.takeIn(_said('$_channel;messageid=1', containing: _channel)),
        ),
        _claude,
      );
    });

    test('a chat the rules file names, under its own', () {
      expect(_asWritten(list.takeIn(_said(_chat))), _chatGpt);
    });

    test(
      'a thread of a channel the rules file names, under the channel\'s',
      () {
        final byChannel = _parse(
          _config([_channel]),
          rules: _readRules({
            'default': _claude,
            'byMissionAddress': [
              {'address': _channel, 'rules': _chatGpt},
            ],
          }),
        );
        expect(
          _asWritten(
            byChannel.takeIn(
              _said('$_channel;messageid=1', containing: _channel),
            ),
          ),
          _chatGpt,
        );
      },
    );

    test('nothing off the list: another chat, or a thread of another '
        'channel', () {
      expect(list.takeIn(_said('teams:19:other@thread.v2')), isNull);
      expect(
        list.takeIn(
          _said(
            'teams:19:other@thread.tacv2;messageid=1',
            containing: 'teams:19:other@thread.tacv2',
          ),
        ),
        isNull,
      );
    });

    test('a thread by its own address alone, when its channel is not on '
        'the list', () {
      // Only the address a thread sits in is asked about.
      final threadOnly = _parse(
        _config(['$_channel;messageid=1']),
        rules: _readRules({
          'default': _claude,
          'byMissionAddress': <Object?>[],
        }),
      );
      expect(
        threadOnly.takeIn(_said('$_channel;messageid=1', containing: _channel)),
        isNull,
      );
    });
  });

  group('refuses a config with', () {
    void refuses(String text) =>
        expect(() => _parse(text), throwsA(isA<FormatException>()));

    test('a key it does not take', () {
      refuses(
        jsonEncode({
          'addressesLetIn': [_chat],
          'extra': true,
        }),
      );
    });

    test('an address that is not one', () {
      for (final address in ['19:chat@thread.v2', 'Teams:x', 'teams:', '']) {
        refuses(_config([address]));
      }
      refuses(
        _config([
          {'addressInExternalSystem': _chat},
        ]),
      );
    });

    test('an address named twice', () {
      refuses(_config([_chat, _chat]));
    });

    test('a key named twice, even with the same value both times', () {
      final list = jsonEncode([_chat]);
      refuses('{"addressesLetIn": $list, "addressesLetIn": $list}');
    });

    test('no address at all', () {
      refuses(_config([]));
      refuses(jsonEncode(<String, Object?>{}));
    });

    test('something that is not a JSON object', () {
      refuses('[]');
      refuses('not json');
    });

    test('flight rules for an address it does not let in', () {
      // The rules file names _chat; this list lets in only the channel.
      refuses(_config([_channel]));
    });
  });

  group('refuses a rules file with', () {
    void refuses(Object? json) =>
        expect(() => _readRules(json), throwsA(isA<FormatException>()));

    test('a key it does not know, at the top, in an entry, or inside the '
        'flight rules', () {
      refuses({..._rulesFile, 'note': 'x'});
      refuses({
        'default': _claude,
        'byMissionAddress': [
          {'address': _chat, 'rules': _chatGpt, 'note': 'x'},
        ],
      });
      refuses({
        'default': {..._claude, 'note': 'x'},
        'byMissionAddress': <Object?>[],
      });
      refuses({
        'default': {
          ..._claude,
          'startingModel': {
            'signIn': 'claude-team',
            'model': 'claude-opus-5-5',
            'effort': 'high',
          },
        },
        'byMissionAddress': <Object?>[],
      });
    });

    test('no default', () {
      refuses({..._rulesFile}..remove('default'));
    });

    test('no starting model', () {
      refuses({
        'default': {..._claude}..remove('startingModel'),
        'byMissionAddress': <Object?>[],
      });
    });

    test('a starting model whose sign-in model calls may not go out as', () {
      refuses({
        'default': {
          'whatMayLeaveThisMachine': _whatMayLeave(['claude-team']),
          'startingModel': {'signIn': 'cam-chatgpt', 'model': 'gpt-6.2-sol'},
        },
        'byMissionAddress': <Object?>[],
      });
    });

    test('an address that is not one, or one named twice', () {
      refuses({
        'default': _claude,
        'byMissionAddress': [
          {'address': '19:chat@thread.v2', 'rules': _chatGpt},
        ],
      });
      refuses({
        'default': _claude,
        'byMissionAddress': [
          {'address': _chat, 'rules': _chatGpt},
          {'address': _chat, 'rules': _claude},
        ],
      });
    });

    test('something that is not a JSON object', () {
      refuses([_rulesFile]);
    });

    test('a key named twice, even with the same value both times', () {
      final fields = jsonEncode(_rulesFile);
      final inner = fields.substring(1, fields.length - 1);
      final rules = jsonEncode(_claude);
      expect(
        () => FlightRulesByMissionAddress.parse('{$inner, "default": $rules}'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test('a message starts a turn when its module says it is for the agent, '
      'and no other', () {
    final startsTurn = {
      for (final forTheAgent in WhetherForTheAgent.values)
        forTheAgent: const StartsATurnWhenForTheAgent().startsTurn(
          _said(_chat, forTheAgent: forTheAgent),
          const StartsTrajectory(StartsMission()),
        ),
    };
    expect(startsTurn, {
      WhetherForTheAgent.everyMessageHereIsForTheAgent: true,
      WhetherForTheAgent.mentionsTheAgent: true,
      WhetherForTheAgent.repliesToTheAgent: true,
      WhetherForTheAgent.neitherMentionsNorRepliesToTheAgent: false,
      WhetherForTheAgent.notKnown: false,
    });
  });
}
