/// Which format a decision entry is written in, so a field can be added
/// reader first: every reader learns a new format, and only then does the
/// docking station write it.
library;

import 'package:checked_json/checked_json.dart' show JsonObject;

/// The field a decision entry names its format in.
const decisionFormatField = 'decisionFormat';

/// The format the docking station writes.
const decisionFormatWritten = 1;

/// [json] without its [decisionFormatField], when it names a format this
/// reads: 1, or none, as every entry written before the field existed. Null
/// for any other format, so the fields of a format it doesn't know are never
/// read as one it does.
JsonObject? withoutKnownDecisionFormat(JsonObject json) {
  if (!json.has(decisionFormatField)) return json;
  return switch (json.raw(decisionFormatField)) {
    decisionFormatWritten => json.without(const {decisionFormatField}),
    _ => null,
  };
}
