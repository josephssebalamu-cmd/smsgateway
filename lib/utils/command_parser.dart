sealed class CommandResult {}

class ParsedCommand extends CommandResult {
  final String verb;
  final String argument;
  final String? price;
  final int? quantity;

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
  static CommandResult parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return CommandError('ERR Empty command. Send HELP.');
    }

    final parts = text.split(RegExp(r'\s+'));
    final keyword = parts.first.toUpperCase();

    switch (keyword) {
      case 'LIST':
        return ParsedCommand(verb: 'LIST', argument: '');
      case 'HELP':
        return ParsedCommand(verb: 'HELP', argument: '');
      case 'SEARCH':
        final query = text.substring(keyword.length).trim();
        if (query.isEmpty) {
          return CommandError('ERR SEARCH needs text.');
        }
        return ParsedCommand(verb: 'SEARCH', argument: query);
      case 'DELETE':
        final prefix = text.substring(keyword.length).trim();
        if (prefix.isEmpty) {
          return CommandError('ERR DELETE needs a product UUID prefix.');
        }
        return ParsedCommand(verb: 'DELETE', argument: prefix);
      case 'ADD':
        final body = text.substring(keyword.length).trim();
        final fields = body.split('|').map((value) => value.trim()).toList();
        if (fields.length != 3 || fields.any((value) => value.isEmpty)) {
          return CommandError('ERR Use ADD name | price | qty');
        }
        final price = double.tryParse(fields[1]);
        final quantity = int.tryParse(fields[2]);
        if (price == null || price < 0) {
          return CommandError('ERR Invalid price.');
        }
        if (quantity == null || quantity < 0) {
          return CommandError('ERR Invalid quantity.');
        }
        return ParsedCommand(
          verb: 'ADD',
          argument: fields[0],
          price: price.toStringAsFixed(2),
          quantity: quantity,
        );
      default:
        return CommandError(
          'ERR Unknown command. Use ADD, SEARCH, LIST, DELETE, or HELP.',
        );
    }
  }
}
