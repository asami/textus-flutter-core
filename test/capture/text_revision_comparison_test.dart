import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  final scenarios = <String, (String, String, String, String, String, String)>{
    'identical Japanese text': ('同じ😀\n', '同じ😀\n', '同じ😀\n', '', '', ''),
    'both empty': ('', '', '', '', '', ''),
    'insertion into empty text': ('', '新しい文', '', '', '新しい文', ''),
    'removal of all text': ('原文', '', '', '原文', '', ''),
    'whole replacement': ('abc', 'XYZ', '', 'abc', 'XYZ', ''),
    'multiple edits stay in one window': ('前A中B後', '前X中Y後', '前', 'A中B', 'X中Y', '後'),
    'Japanese correction': ('本日は晴れです。', '本日は雨です。', '本日は', '晴れ', '雨', 'です。'),
    'astral scalars with shared UTF16 high surrogate': ('前😀後', '前😃後', '前', '😀', '😃', '後'),
    'combining sequence is not normalized': ('cafe\u0301!', 'café!', 'caf', 'e\u0301', 'é', '!'),
    'combining mark scalar can be the replacement': ('e\u0301', 'e\u0300', 'e', '\u0301', '\u0300', ''),
    'whitespace and CRLF stay exact': (' \t原文\r\n', ' \t修正\n', ' \t', '原文\r', '修正', '\n'),
    'repeated scalars never overlap prefix and suffix': ('aaa', 'aa', 'aa', 'a', '', ''),
    'suffix can consume the shorter text': ('a尾', '尾', '', 'a', '', '尾'),
    'insertion after full prefix': ('abc', 'abcd', 'abc', '', 'd', ''),
    'insertion before full suffix': ('尾', '前尾', '', '', '前', '尾'),
  };
  for (final entry in scenarios.entries) {
    test(entry.key, () {
      // Given these exact selected strings and their expected scalar replacement window.
      final (original, proposed, prefix, removed, inserted, suffix) = entry.value;
      // When the pure public comparison is constructed.
      final comparison = TextRevisionComparison.between(
        original: original,
        proposed: proposed,
      );
      // Then the longest prefix and nonoverlapping suffix preserve both exact strings.
      expect(comparison.original, original);
      expect(comparison.proposed, proposed);
      expect(comparison.unchangedPrefix, prefix);
      expect(comparison.removedText, removed);
      expect(comparison.insertedText, inserted);
      expect(comparison.unchangedSuffix, suffix);
      expect(comparison.hasChanges, original != proposed);
      expect(comparison.unchangedPrefix + comparison.removedText + comparison.unchangedSuffix, original);
      expect(comparison.unchangedPrefix + comparison.insertedText + comparison.unchangedSuffix, proposed);
    });
  }
}
