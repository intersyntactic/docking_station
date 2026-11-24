// Where replies go is read back exactly as written, and strictly: the
// airlock grants a trajectory's replies to it, so nothing about it may be
// guessed.
import 'package:is_docking_station_api/is_docking_station_api.dart';
import 'package:is_web_address_vocabulary/is_web_address_vocabulary.dart'
    show AddressPrefix, Origin, PathPrefix;
import 'package:test/test.dart';

final _slack = Origin.parse('https://slack.com')!;

void main() {
  test('each case reads back as itself', () {
    for (final endpoint in <ReplyEndpoint>[
      RepliesUnderWebAddress(
        AddressPrefix.of(
          Origin.parse('https://smba.trafficmanager.net')!,
          PathPrefix.parse('/amer/v3/conversations/19:x/activities/')!,
        ),
      ),
      RepliesInSlackConversation(
        origin: _slack,
        channel: SlackChannelId.parse('C0123ABC')!,
        thread: SlackThreadTimestamp.parse('1700000000.000100'),
      ),
      RepliesInSlackConversation(
        origin: _slack,
        channel: SlackChannelId.parse('D0456DEF')!,
      ),
    ]) {
      final json = encodeReplyEndpoint(endpoint);
      expect(decodeReplyEndpoint(json, 'replyEndpoint'), endpoint);
    }
  });

  test('a Slack conversation is written as its origin, channel and thread', () {
    expect(
      encodeReplyEndpoint(
        RepliesInSlackConversation(
          origin: _slack,
          channel: SlackChannelId.parse('C0123ABC')!,
          thread: SlackThreadTimestamp.parse('1700000000.000100'),
        ),
      ),
      {
        'case': 'in-slack-conversation',
        'origin': 'https://slack.com',
        'channel': 'C0123ABC',
        'thread': '1700000000.000100',
      },
    );
  });

  test('anything else is refused, naming the field', () {
    final slack = {
      'case': 'in-slack-conversation',
      'origin': 'https://slack.com',
      'channel': 'C0123ABC',
    };
    for (final json in <Object?>[
      'https://slack.com',
      {...slack, 'case': 'somewhere-else'},
      {...slack}..remove('case'),
      {...slack}..remove('origin'),
      {...slack}..remove('channel'),
      {...slack, 'channel': 'general'},
      {...slack, 'thread': 'yesterday'},
      {...slack, 'thread': null},
      {...slack, 'extra': 1},
      {'case': 'under-web-address'},
      {
        'case': 'under-web-address',
        'addressPrefix': {'origin': 'https://x.example', 'pathPrefix': '/'},
        'channel': 'C0123ABC',
      },
    ]) {
      expect(
        () => decodeReplyEndpoint(json, 'replyEndpoint'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            startsWith('replyEndpoint'),
          ),
        ),
        reason: '$json',
      );
    }
  });

  test('a Slack id or thread timestamp parses only in Slack\'s form', () {
    for (final s in ['C0123ABC', 'D0456DEF', 'G0789GHI']) {
      expect(SlackChannelId.parse(s)?.value, s);
    }
    for (final s in ['', 'c0123abc', 'U0123ABC', '#general', 'C']) {
      expect(SlackChannelId.parse(s), isNull, reason: s);
    }
    expect(
      SlackThreadTimestamp.parse('1700000000.000100')?.value,
      '1700000000.000100',
    );
    for (final s in ['', '1700000000', '.5', '17.x', '1700000000.000100 ']) {
      expect(SlackThreadTimestamp.parse(s), isNull, reason: s);
    }
  });
}
