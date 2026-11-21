import 'package:flutter_test/flutter_test.dart';
import 'package:gateway/utils/command_parser.dart';

void main() {
  test('parses ADD fields and case-insensitive command keywords', () {
    final result = CommandParser.parse('add Green tea | 2.50 | 8');

    expect(result, isA<ParsedCommand>());
    final command = result as ParsedCommand;
    expect(command.verb, 'ADD');
    expect(command.argument, 'Green tea');
    expect(command.price, '2.50');
    expect(command.quantity, 8);
  });

  test('rejects invalid quantities and missing search query', () {
    expect(
      (CommandParser.parse('ADD tea | 2.50 | many') as CommandError).text,
      contains('Invalid quantity'),
    );
    expect(
      (CommandParser.parse('SEARCH') as CommandError).text,
      contains('SEARCH needs text'),
    );
  });
}
