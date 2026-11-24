/// Where replies to an event go, as its module vouches for it, and its form
/// in the logbook. One case for each way an external system takes replies,
/// since a reply's target is a web address for some and a field of the
/// request's body for others.
///
/// It imports no package that decodes what strangers sent, so path_start
/// may read it.
library;

import 'package:is_web_address_vocabulary/is_web_address_vocabulary.dart'
    show
        AddressPrefix,
        Origin,
        decodeAddressPrefix,
        decodeOrigin,
        encodeAddressPrefix,
        encodeOrigin;

/// Where replies to an event go: [RepliesUnderWebAddress] or
/// [RepliesInSlackConversation].
sealed class ReplyEndpoint {
  const ReplyEndpoint();
}

/// Replies go under [prefix], a web address that names the conversation, as
/// Teams' Bot Connector takes them: a reply's request is confined to its
/// conversation by where it is sent.
final class RepliesUnderWebAddress extends ReplyEndpoint {
  const RepliesUnderWebAddress(this.prefix);

  final AddressPrefix prefix;

  @override
  bool operator ==(Object other) =>
      other is RepliesUnderWebAddress && other.prefix == prefix;

  @override
  int get hashCode => prefix.hashCode;

  @override
  String toString() => 'RepliesUnderWebAddress($prefix)';
}

/// Replies go to Slack's [channel], in [thread], through [origin]. Slack takes every reply at one web address and
/// names its conversation in the request's body, so a reply is confined to
/// its conversation by [channel] and [thread], never by where it is sent;
/// [origin] is what the trajectory's rules say it may reply through at all.
final class RepliesInSlackConversation extends ReplyEndpoint {
  const RepliesInSlackConversation({
    required this.origin,
    required this.channel,
    this.thread,
  });

  /// The site the reply is sent to, the same for every Slack reply.
  final Origin origin;

  final SlackChannelId channel;

  /// The thread the reply goes in, by its root message. A post at a
  /// channel's or a group message's top level is a thread's root, so a
  /// reply to it names that post's own timestamp. Null only for a direct
  /// message between one person and the bot, which Slack doesn't thread.
  final SlackThreadTimestamp? thread;

  @override
  bool operator ==(Object other) =>
      other is RepliesInSlackConversation &&
      other.origin == origin &&
      other.channel == channel &&
      other.thread == thread;

  @override
  int get hashCode => Object.hash(origin, channel, thread);

  @override
  String toString() => 'RepliesInSlackConversation($origin, $channel, $thread)';
}

/// A Slack conversation's id: a public or private channel (`C…`), a direct
/// message (`D…`) or a group message (`G…`).
final class SlackChannelId {
  const SlackChannelId._(this.value);

  /// The id, as Slack writes it.
  final String value;

  /// [s] as a channel id; null unless it is one.
  static SlackChannelId? parse(String s) =>
      _id.hasMatch(s) ? SlackChannelId._(s) : null;

  static final _id = RegExp(r'^[CDG][A-Z0-9]+$');

  @override
  bool operator ==(Object other) =>
      other is SlackChannelId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// The timestamp Slack names a thread's parent message by, such as
/// `1700000000.000100`.
final class SlackThreadTimestamp {
  const SlackThreadTimestamp._(this.value);

  /// The timestamp, as Slack writes it.
  final String value;

  /// [s] as a thread timestamp; null unless it is one.
  static SlackThreadTimestamp? parse(String s) =>
      _ts.hasMatch(s) ? SlackThreadTimestamp._(s) : null;

  static final _ts = RegExp(r'^\d+\.\d+$');

  @override
  bool operator ==(Object other) =>
      other is SlackThreadTimestamp && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// [endpoint] as JSON:
///
///     {"case": "under-web-address", "addressPrefix": <address prefix>}
///     {"case": "in-slack-conversation", "origin": <origin>,
///      "channel": <id>, "thread": <ts>?}
///
/// `<address prefix>` and `<origin>` are as is_web_address_vocabulary's
/// `encodeAddressPrefix` and `encodeOrigin` write them.
Map<String, Object?> encodeReplyEndpoint(
  ReplyEndpoint endpoint,
) => switch (endpoint) {
  RepliesUnderWebAddress(:final prefix) => {
    'case': 'under-web-address',
    'addressPrefix': encodeAddressPrefix(prefix),
  },
  RepliesInSlackConversation(:final origin, :final channel, :final thread) => {
    'case': 'in-slack-conversation',
    'origin': encodeOrigin(origin),
    'channel': channel.value,
    'thread': ?thread?.value,
  },
};

/// [json] read back as the endpoint [encodeReplyEndpoint] wrote. A
/// [FormatException] naming [field] for anything it doesn't write: an
/// unknown case, a field missing, extra or malformed.
ReplyEndpoint decodeReplyEndpoint(Object? json, String field) {
  if (json is! Map<String, Object?>) {
    throw FormatException('$field: not an object');
  }
  Never bad(String why) => throw FormatException('$field: $why');
  void only(Set<String> keys) {
    for (final key in json.keys) {
      if (!keys.contains(key)) bad('`$key` is not expected here');
    }
  }

  switch (json['case']) {
    case 'under-web-address':
      only(const {'case', 'addressPrefix'});
      return RepliesUnderWebAddress(
        decodeAddressPrefix(json['addressPrefix'], '$field.addressPrefix'),
      );
    case 'in-slack-conversation':
      only(const {'case', 'origin', 'channel', 'thread'});
      final origin = decodeOrigin(json['origin'], '$field.origin');
      final channel = switch (json['channel']) {
        final String s => SlackChannelId.parse(s),
        _ => null,
      };
      if (channel == null) bad('`channel` is not a Slack channel id');
      final SlackThreadTimestamp? thread;
      if (json.containsKey('thread')) {
        thread = switch (json['thread']) {
          final String s => SlackThreadTimestamp.parse(s),
          _ => null,
        };
        if (thread == null) bad('`thread` is not a Slack thread timestamp');
      } else {
        thread = null;
      }
      return RepliesInSlackConversation(
        origin: origin,
        channel: channel,
        thread: thread,
      );
    default:
      bad('`case` is not a reply endpoint: ${json['case']}');
  }
}
