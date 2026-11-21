import 'package:flutter/material.dart';

import '../supabase_client.dart';
import '../utils/app_logger.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _metrics;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

  Future<void> _loadMetrics() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await GatewaySupabase.client.rpc('marketplace_metrics');
      final rows = result as List<dynamic>;
      if (rows.isEmpty) {
        throw StateError('The marketplace metrics query returned no result.');
      }
      if (!mounted) return;
      setState(() {
        _metrics = Map<String, dynamic>.from(rows.first as Map);
        _loading = false;
      });
    } catch (error) {
      AppLogger.instance.error('Could not load dashboard metrics: $error');
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
      appBar: AppBar(title: const Text('AgriMarket Dashboard')),
      body: RefreshIndicator(
        onRefresh: _loadMetrics,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Marketplace overview',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline, color: Colors.red),
                  title: const Text('Metrics unavailable'),
                  subtitle: Text(_error.toString()),
                  trailing: IconButton(
                    onPressed: _loadMetrics,
                    icon: const Icon(Icons.refresh),
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = (constraints.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _MetricCard(
                        width: cardWidth,
                        title: 'Registered users',
                        value: _value('total_users'),
                        icon: Icons.people_outline,
                      ),
                      _MetricCard(
                        width: cardWidth,
                        title: 'Products listed',
                        value: _value('total_products'),
                        icon: Icons.grass_outlined,
                      ),
                      _MetricCard(
                        width: cardWidth,
                        title: 'Orders placed',
                        value: _value('total_orders'),
                        icon: Icons.shopping_bag_outlined,
                      ),
                      _MetricCard(
                        width: cardWidth,
                        title: 'Transaction value',
                        value: '${_formatMoney(_number('total_value'))} UGX',
                        icon: Icons.payments_outlined,
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  String _value(String key) => _number(key).toInt().toString();

  double _number(String key) => (_metrics?[key] as num?)?.toDouble() ?? 0;

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

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.title,
    required this.value,
    required this.icon,
  });

  final double width;
  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 28,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 6),
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
