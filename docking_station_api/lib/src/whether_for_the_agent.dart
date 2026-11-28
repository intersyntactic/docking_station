/// Whether a message said is for the agent, as the module that translated it
/// can tell from how it was delivered.
library;

/// Whether a message said is for the agent: what decides whether it starts
/// a turn.
enum WhetherForTheAgent {
  /// Every message delivered where it was said is for the agent: a
  /// one-to-one chat with it, or a place the external system delivers only
  /// what is for the agent, as Teams delivers only what @mentions a bot.
  everyMessageHereIsForTheAgent('every-message-here-is-for-the-agent'),

  /// Said where everyone's messages are delivered, and it mentions the agent.
  mentionsTheAgent('mentions-the-agent'),

  /// Said where everyone's messages are delivered, without mentioning the
  /// agent, as a reply to it: to a message of the agent's, or in a thread
  /// the agent has posted in.
  repliesToTheAgent('replies-to-the-agent'),

  /// Said where everyone's messages are delivered, and it neither mentions
  /// the agent nor replies to it.
  neitherMentionsNorRepliesToTheAgent(
    'neither-mentions-nor-replies-to-the-agent',
  ),

  /// The module can't tell which of the others it is.
  notKnown('not-known');

  const WhetherForTheAgent(this.wire);

  /// The value as its JSON writes it.
  final String wire;

  static final _byWire = {for (final w in values) w.wire: w};

  /// The value whose [wire] is [s]; null unless one is.
  static WhetherForTheAgent? parse(String s) => _byWire[s];
}
