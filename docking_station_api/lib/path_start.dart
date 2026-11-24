/// Reading the entry that starts a trajectory, for its rules, without
/// decoding what strangers sent: for the airlock.
library;

export 'package:is_reply_vocabulary/is_reply_vocabulary.dart'
    show
        ReplyEndpoint,
        RepliesInSlackConversation,
        RepliesUnderWebAddress,
        SlackChannelId,
        SlackMessageTimestamp,
        decodeReplyEndpoint,
        encodeReplyEndpoint;

export 'src/path_start.dart';
