import 'package:flutter/material.dart';

import '../supabase_client.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;
  List<Map<String, dynamic>> _inbound = [];
  List<Map<String, dynamic>> _outbound = [];
  List<Map<String, dynamic>> _products = [];
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 3, vsync: this);
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final inbound = await GatewaySupabase.client
          .from('incoming_sms')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      final outbound = await GatewaySupabase.client
          .from('outbound_sms')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      final products = await GatewaySupabase.client
          .from('products')
          .select(
            'id,name,quantity_kg,price_per_kg,status,farmer_phone,created_at',
          )
          .order('created_at', ascending: false)
          .limit(100);
      if (!mounted) return;
      setState(() {
        _inbound = inbound.cast<Map<String, dynamic>>();
        _outbound = outbound.cast<Map<String, dynamic>>();
        _products = products.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages & Market'),
        bottom: TabBar(
          controller: _controller,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Inbound'),
            Tab(text: 'Outbound'),
            Tab(text: 'Market'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 36,
                    ),
                    const SizedBox(height: 8),
                    const Text('Could not load messages or market listings.'),
                    const SizedBox(height: 8),
                    Text(_error.toString(), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : TabBarView(
              controller: _controller,
              children: [
                _SmsList(
                  rows: _inbound,
                  table: 'incoming_sms',
                  outbound: false,
                  onRefresh: _refresh,
                ),
                _SmsList(
                  rows: _outbound,
                  table: 'outbound_sms',
                  outbound: true,
                  onRefresh: _refresh,
                ),
                _MarketList(rows: _products, onRefresh: _refresh),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _SmsList extends StatelessWidget {
  const _SmsList({
    required this.rows,
    required this.table,
    required this.outbound,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> rows;
  final String table;
  final bool outbound;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final row = rows[index];
          final id = row['id'].toString();
          final phone = outbound ? row['phone'] : row['sender'];
          final body = outbound ? row['message'] : row['body'];
          final status = outbound ? row['status']?.toString() : null;
          final sessionId = row['session_id']?.toString();
          final sessionSnippet = sessionId == null || sessionId.isEmpty
              ? ''
              : '\nSession: ${sessionId.length > 8 ? sessionId.substring(0, 8) : sessionId}';
          return Dismissible(
            key: ValueKey('$table-$id'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: Colors.red,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            onDismissed: (_) async {
              await GatewaySupabase.client.from(table).delete().eq('id', id);
              await onRefresh();
            },
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              title: Text(
                phone?.toString() ?? 'Unknown phone',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                '${body?.toString() ?? ''}\n'
                '${row['created_at'] ?? ''}'
                '${status == null ? '' : '\nStatus: $status'}$sessionSnippet',
              ),
              isThreeLine: true,
              trailing: outbound && (status == 'failed' || status == 'pending')
                  ? TextButton(
                      onPressed: () async {
                        await GatewaySupabase.client
                            .from('outbound_sms')
                            .update({
                              'status': 'pending',
                              'attempts': 0,
                              'last_error': null,
                              'claimed_at': null,
                            })
                            .eq('id', id);
                        await onRefresh();
                      },
                      child: const Text('Retry'),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }
}

class _MarketList extends StatelessWidget {
  const _MarketList({required this.rows, required this.onRefresh});

  final List<Map<String, dynamic>> rows;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final product = rows[index];
          final quantity = (product['quantity_kg'] as num?)?.toString() ?? '0';
          final price = (product['price_per_kg'] as num?)?.toString() ?? '0';
          final available = product['status'] == 'available';
          return Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListTile(
                leading: Icon(
                  Icons.grass,
                  color: available ? Colors.green : Colors.grey,
                  size: 32,
                ),
                title: Text(
                  product['name']?.toString() ?? 'Produce',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '$quantity KG available\n'
                    '$price UGX per KG\n'
                    'Farmer: ${product['farmer_phone'] ?? 'Unknown'}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                trailing: Text(
                  available ? 'Available' : 'Sold',
                  style: TextStyle(
                    color: available ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                isThreeLine: true,
              ),
            ),
          );
        },
      ),
    );
  }
}
