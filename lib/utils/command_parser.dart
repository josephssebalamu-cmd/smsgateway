sealed class CommandResult {}

class ParsedCommand extends CommandResult {
  final String verb;
  final String argument;
  final String? price;
  final String? quantity;

  ParsedCommand({
    required this.verb,
    required this.argument,
    this.price,
    this.quantity,
  });
}

class CommandError extends CommandResult {
  final String text;
  CommandError(this.text);
}

class CommandParser {
  static CommandResult? parse(String raw) {
    final text = raw.trim();
    if (!RegExp(r'^SGW\s+', caseSensitive: false).hasMatch(text)) {
      return null;
    }

    final command = text
        .replaceFirst(RegExp(r'^SGW\s+', caseSensitive: false), '')
        .trim();
    if (command.isEmpty) {
      return CommandError('ERR Empty command. Send HELP.');
    }

    final parts = command.split(RegExp(r'\s+'));
    final keyword = parts.first.toUpperCase();

    switch (keyword) {
      case 'LIST':
        return ParsedCommand(verb: 'LIST', argument: '');
      case 'HELP':
        return ParsedCommand(verb: 'HELP', argument: '');
      case 'SEARCH':
        final query = command.substring(keyword.length).trim();
        if (query.isEmpty) {
          return CommandError('ERR SEARCH needs text.');
        }
        return ParsedCommand(verb: 'SEARCH', argument: query);
      case 'DELETE':
        final prefix = command.substring(keyword.length).trim();
        if (prefix.isEmpty) {
          return CommandError('ERR DELETE needs a product UUID prefix.');
        }
        return ParsedCommand(verb: 'DELETE', argument: prefix);
      case 'ADD':
        final body = command.substring(keyword.length).trim();
        if (body.isEmpty) {
          return CommandError('ERR ADD needs product details.');
        }

        if (body.contains('|')) {
          final fields = body.split('|').map((value) => value.trim()).toList();
          if (fields.length != 3 || fields.any((value) => value.isEmpty)) {
            return CommandError('ERR Use ADD name | 5 pcs | 15000');
          }
          final price = double.tryParse(fields[2].replaceAll(',', ''));
          if (price == null || price < 0) {
            return CommandError('ERR Invalid price.');
          }
          return ParsedCommand(
            verb: 'ADD',
            argument: fields[0],
            price: price.toStringAsFixed(2),
            quantity: fields[1],
          );
        }

        final words = body.split(RegExp(r'\s+'));
        if (words.length < 4) {
          return CommandError('ERR Use ADD MAIZE 1 KG 2000');
        }
        final price = double.tryParse(words.last.replaceAll(',', ''));
        if (price == null || price < 0) {
          return CommandError('ERR Invalid price.');
        }
        return ParsedCommand(
          verb: 'ADD',
          argument: words.take(words.length - 3).join(' '),
          quantity: '${words[words.length - 3]} ${words[words.length - 2]}',
          price: price.toStringAsFixed(2),
        );
      default:
        return CommandError(
          'ERR Unknown command. Use ADD, SEARCH, LIST, DELETE, or HELP.',
        );
    }
  }
}
