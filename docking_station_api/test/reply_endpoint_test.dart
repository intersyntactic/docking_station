// Where replies go is declared by is_conversation_reply_vocabulary alone. This package
// re-exports it, so a package that imports both sees one type, and a
// pattern on one package's case matches a value made by the other's.
import 'package:is_docking_station_api/is_docking_station_api.dart' as api;
import 'package:is_docking_station_api/path_start.dart' as path_start;
import 'package:is_conversation_reply_vocabulary/is_conversation_reply_vocabulary.dart'
    as vocabulary;
import 'package:test/test.dart';

void main() {
  test('each reply type is the vocabulary\'s own, from either library', () {
    final pairs = <(Type, Type, Type)>[
      (api.ReplyEndpoint, path_start.ReplyEndpoint, vocabulary.ReplyEndpoint),
      (
        api.RepliesUnderWebAddress,
        path_start.RepliesUnderWebAddress,
        vocabulary.RepliesUnderWebAddress,
      ),
      (
        api.RepliesInSlackConversation,
        path_start.RepliesInSlackConversation,
        vocabulary.RepliesInSlackConversation,
      ),
      (
        api.SlackChannelId,
        path_start.SlackChannelId,
        vocabulary.SlackChannelId,
      ),
      (
        api.SlackMessageTimestamp,
        path_start.SlackMessageTimestamp,
        vocabulary.SlackMessageTimestamp,
      ),
    ];
    for (final (fromApi, fromPathStart, own) in pairs) {
      expect(fromApi, own);
      expect(fromPathStart, own);
    }
    expect(api.encodeReplyEndpoint, same(vocabulary.encodeReplyEndpoint));
    expect(api.decodeReplyEndpoint, same(vocabulary.decodeReplyEndpoint));
  });
}
