import '../supabase_client.dart';

class UssdEngine {
  static const String mainMenu =
      'Welcome to AgriMarket. Reply: 1. Buy Produce, 2. Sell Produce, 3. My Orders';

  Future<bool> hasActiveSession(String phone) async {
    final session = await GatewaySupabase.client
        .from('sessions')
        .select('phone')
        .eq('phone', phone)
        .maybeSingle();
    return session != null;
  }

  Future<String?> process(String phone, String message) async {
    final input = message.trim();
    if (input.toUpperCase() == 'SGW') {
      await GatewaySupabase.client
          .from('users')
          .upsert(
            {'phone': phone, 'role': 'buyer'},
            onConflict: 'phone',
            ignoreDuplicates: true,
          );
      await _saveSession(phone, 'MAIN_MENU', {});
      return mainMenu;
    }

    final session = await GatewaySupabase.client
        .from('sessions')
        .select('current_menu,context_data')
        .eq('phone', phone)
        .maybeSingle();
    if (session == null) return null;

    final menu = session['current_menu'] as String? ?? 'MAIN_MENU';
    final context = _context(session['context_data']);

    switch (menu) {
      case 'MAIN_MENU':
        return _mainMenuInput(phone, input);
      case 'SELL_NAME':
        return _sellName(phone, input, context);
      case 'SELL_QTY':
        return _sellQuantity(phone, input, context);
      case 'SELL_PRICE':
        return _sellPrice(phone, input, context);
      case 'BUY_SEARCH':
        return _buySearch(phone, input, context);
      case 'BUY_SELECT':
        return _buySelect(phone, input, context);
      case 'BUY_QTY':
        return _buyQuantity(phone, input, context);
      default:
        await _saveSession(phone, 'MAIN_MENU', {});
        return mainMenu;
    }
  }

  Future<String> _mainMenuInput(String phone, String input) async {
    switch (input) {
      case '1':
        await _setUserRole(phone, 'buyer');
        await _saveSession(phone, 'BUY_SEARCH', {});
        return 'What do you want to buy? (Reply: MAIZE, BEANS, RICE)';
      case '2':
        await _setUserRole(phone, 'farmer');
        await _saveSession(phone, 'SELL_NAME', {});
        return 'What are you selling? (Reply: MAIZE, BEANS, RICE)';
      case '3':
        return _myOrders(phone);
      default:
        return mainMenu;
    }
  }

  Future<String> _sellName(
    String phone,
    String input,
    Map<String, dynamic> context,
  ) async {
    if (input.isEmpty) {
      return 'What are you selling? (Reply: MAIZE, BEANS, RICE)';
    }
    final name = input.toUpperCase();
    await _saveSession(phone, 'SELL_QTY', {'name': name});
    return 'How many KGs of $name do you have?';
  }

  Future<String> _sellQuantity(
    String phone,
    String input,
    Map<String, dynamic> context,
  ) async {
    final quantity = _parsePositiveNumber(input);
    if (quantity == null) {
      return 'Please reply with a valid quantity in KGs.';
    }
    context['quantity_kg'] = quantity;
    await _saveSession(phone, 'SELL_PRICE', context);
    return 'What is your price per KG in UGX?';
  }

  Future<String> _sellPrice(
    String phone,
    String input,
    Map<String, dynamic> context,
  ) async {
    final price = _parsePositiveNumber(input);
    if (price == null) {
      return 'Please reply with a valid price per KG in UGX.';
    }
    final name = context['name'] as String?;
    final quantity = (context['quantity_kg'] as num?)?.toDouble();
    if (name == null || quantity == null) {
      await _clearSession(phone);
      return mainMenu;
    }

    await _setUserRole(phone, 'farmer');
    await GatewaySupabase.client.from('products').insert({
      'farmer_phone': phone,
      'name': name,
      'quantity_kg': quantity,
      'price_per_kg': price,
      'status': 'available',
    });
    await _clearSession(phone);
    return 'Success! Your ${_formatQuantity(quantity)}KG of $name is listed at ${_formatMoney(price)} UGX/KG. Reply SGW to go back.';
  }

  Future<String> _buySearch(
    String phone,
    String input,
    Map<String, dynamic> context,
  ) async {
    if (input.isEmpty) {
      return 'What do you want to buy? (Reply: MAIZE, BEANS, RICE)';
    }
    final rows = await GatewaySupabase.client
        .from('products')
        .select('id,name,quantity_kg,price_per_kg')
        .eq('status', 'available')
        .ilike('name', '%${input.replaceAll('%', r'\%')}%')
        .order('created_at', ascending: true)
        .limit(5);
    final products = rows.cast<Map<String, dynamic>>();
    if (products.isEmpty) {
      return 'No available produce found. Reply with another produce name.';
    }

    context['products'] = products;
    await _saveSession(phone, 'BUY_SELECT', context);
    final choices = products.indexed
        .map((entry) {
          final (index, product) = entry;
          final quantity = (product['quantity_kg'] as num).toDouble();
          final price = (product['price_per_kg'] as num).toDouble();
          return '${index + 1}. ${_formatQuantity(quantity)}KG ${product['name']} @ ${_formatMoney(price)} UGX';
        })
        .join('\n');
    return 'Found: $choices\nReply with the number to buy.';
  }

  Future<String> _buySelect(
    String phone,
    String input,
    Map<String, dynamic> context,
  ) async {
    final selection = int.tryParse(input);
    final products = (context['products'] as List<dynamic>?) ?? const [];
    if (selection == null || selection < 1 || selection > products.length) {
      return 'Please reply with a number from the produce list.';
    }
    final selected = Map<String, dynamic>.from(products[selection - 1] as Map);
    context['product'] = selected;
    await _saveSession(phone, 'BUY_QTY', context);
    return 'How many KGs do you want?';
  }

  Future<String> _buyQuantity(
    String phone,
    String input,
    Map<String, dynamic> context,
  ) async {
    final quantity = _parsePositiveNumber(input);
    final product = context['product'];
    if (quantity == null || product is! Map) {
      return 'Please reply with a valid quantity in KGs.';
    }
    final selected = Map<String, dynamic>.from(product);
    final available = (selected['quantity_kg'] as num).toDouble();
    if (quantity > available) {
      return 'Only ${_formatQuantity(available)}KG is available. Reply with a smaller quantity.';
    }

    await _setUserRole(phone, 'buyer');
    final total = await GatewaySupabase.client.rpc(
      'place_market_order',
      params: {
        'p_buyer_phone': phone,
        'p_product_id': selected['id'],
        'p_quantity_kg': quantity,
      },
    );
    final totalPrice = (total as num).toDouble();
    await _clearSession(phone);
    return 'Order placed for ${_formatQuantity(quantity)}KG. Total: ${_formatMoney(totalPrice)} UGX. The farmer will contact you shortly.';
  }

  Future<String> _myOrders(String phone) async {
    final rows = await GatewaySupabase.client
        .from('orders')
        .select('quantity_kg,total_price,status,products(name)')
        .eq('buyer_phone', phone)
        .order('created_at', ascending: false)
        .limit(5);
    final orders = rows.cast<Map<String, dynamic>>();
    if (orders.isEmpty) return 'You have no orders yet. Reply SGW to go back.';

    final summary = orders
        .map((order) {
          final product = order['products'] as Map<String, dynamic>?;
          final name = product?['name']?.toString() ?? 'Produce';
          final quantity = (order['quantity_kg'] as num).toDouble();
          final total = (order['total_price'] as num).toDouble();
          return '$name ${_formatQuantity(quantity)}KG - ${_formatMoney(total)} UGX (${order['status']})';
        })
        .join('\n');
    return 'Your recent orders:\n$summary\nReply SGW to go back.';
  }

  Future<void> _setUserRole(String phone, String role) async {
    await GatewaySupabase.client.from('users').upsert({
      'phone': phone,
      'role': role,
    }, onConflict: 'phone');
  }

  Future<void> _saveSession(
    String phone,
    String menu,
    Map<String, dynamic> context,
  ) async {
    await GatewaySupabase.client.from('sessions').upsert({
      'phone': phone,
      'current_menu': menu,
      'context_data': context,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'phone');
  }

  Future<void> _clearSession(String phone) async {
    await GatewaySupabase.client.from('sessions').delete().eq('phone', phone);
  }

  Map<String, dynamic> _context(dynamic value) {
    if (value is Map<String, dynamic>) return Map.of(value);
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }

  double? _parsePositiveNumber(String input) {
    final normalized = input.replaceAll(',', '').trim();
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(normalized)) return null;
    final value = double.tryParse(normalized);
    return value != null && value > 0 ? value : null;
  }

  String _formatQuantity(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  String _formatMoney(double value) {
    final raw = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
    final parts = raw.split('.');
    final whole = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return parts.length == 1 ? whole : '$whole.${parts.last}';
  }
}
