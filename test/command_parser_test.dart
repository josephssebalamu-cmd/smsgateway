import 'package:flutter_test/flutter_test.dart';
import 'package:gateway/utils/command_parser.dart';

void main() {
  test('parses ADD fields and case-insensitive command keywords', () {
    final result = CommandParser.parse('SGW add Green tea | 8 pcs | 2.50');

    expect(result, isA<ParsedCommand>());
    final command = result as ParsedCommand;
    expect(command.verb, 'ADD');
    expect(command.argument, 'Green tea');
    expect(command.price, '2.50');
    expect(command.quantity, '8 pcs');
  });

  test('rejects malformed ADD commands and missing search query', () {
    expect(
      (CommandParser.parse('SGW ADD tea | 2.50') as CommandError).text,
      contains('Use ADD'),
    );
    expect(
      (CommandParser.parse('SGW SEARCH') as CommandError).text,
      contains('SEARCH needs text'),
    );
  });
}
