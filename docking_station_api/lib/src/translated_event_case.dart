/// The `case` field of a translated event on the wire. It imports nothing,
/// so path_start.dart can read a case without reaching what decodes one.
library;

/// Which translated event an entry's `translatedEvent` is, as its `case`
/// field writes it.
enum TranslatedEventCase {
  messageSaid('message-said'),
  messageChanged('message-changed'),
  actorsJoinedAddress('actors-joined-address'),
  shownMessageJudged('shown-message-judged'),
  personAskedToCloseTrajectory('person-asked-to-close-trajectory');

  const TranslatedEventCase(this.wire);

  final String wire;

  static final _byWire = {for (final c in values) c.wire: c};

  /// The case [wire] names; null for any other string.
  static TranslatedEventCase? parse(String wire) => _byWire[wire];
}
