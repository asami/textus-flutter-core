/// Exact selected text represented as one inspectable replacement window.
///
/// Prefix and nonoverlapping suffix use Unicode scalar values, without text
/// normalization. This is not a minimal diff or a set of selectable hunks:
/// consumers adopt the whole selected text through their own explicit action.
final class TextRevisionComparison {
  const TextRevisionComparison._({
    required this.original,
    required this.proposed,
    required this.unchangedPrefix,
    required this.removedText,
    required this.insertedText,
    required this.unchangedSuffix,
  });

  factory TextRevisionComparison.between({
    required String original,
    required String proposed,
  }) {
    final before = original.runes.toList();
    final after = proposed.runes.toList();
    var prefixLength = 0;
    while (prefixLength < before.length &&
        prefixLength < after.length &&
        before[prefixLength] == after[prefixLength]) {
      prefixLength++;
    }
    var suffixLength = 0;
    while (suffixLength < before.length - prefixLength &&
        suffixLength < after.length - prefixLength &&
        before[before.length - suffixLength - 1] ==
            after[after.length - suffixLength - 1]) {
      suffixLength++;
    }
    return TextRevisionComparison._(
      original: original,
      proposed: proposed,
      unchangedPrefix: String.fromCharCodes(before.take(prefixLength)),
      removedText: String.fromCharCodes(
        before.sublist(prefixLength, before.length - suffixLength),
      ),
      insertedText: String.fromCharCodes(
        after.sublist(prefixLength, after.length - suffixLength),
      ),
      unchangedSuffix: String.fromCharCodes(
        before.skip(before.length - suffixLength),
      ),
    );
  }

  final String original;
  final String proposed;
  final String unchangedPrefix;
  final String removedText;
  final String insertedText;
  final String unchangedSuffix;
  bool get hasChanges => original != proposed;
}
