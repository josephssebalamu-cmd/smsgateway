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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 2, vsync: this);
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
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
    if (!mounted) return;
    setState(() {
      _inbound = inbound.cast<Map<String, dynamic>>();
      _outbound = outbound.cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        bottom: TabBar(
          controller: _controller,
          tabs: const [
            Tab(text: 'Inbound'),
            Tab(text: 'Outbound'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _controller,
              children: [
                _MessageList(
                  rows: _inbound,
                  outbound: false,
                  onRefresh: _refresh,
                ),
                _MessageList(
                  rows: _outbound,
                  outbound: true,
                  onRefresh: _refresh,
                ),
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

class _MessageList extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final bool outbound;
  final Future<void> Function() onRefresh;

  const _MessageList({
    required this.rows,
    required this.outbound,
    required this.onRefresh,
  });

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
          final title = outbound
              ? row['phone']?.toString() ?? ''
              : row['sender']?.toString() ?? '';
          final body = outbound
              ? row['message']?.toString() ?? ''
              : row['body']?.toString() ?? '';
          final time = outbound
              ? row['created_at']?.toString() ?? ''
              : row['created_at']?.toString() ?? '';
          final status = outbound ? row['status']?.toString() : null;
          return ListTile(
            title: Text(title),
            subtitle: Text(
              '$body\n$time${status == null ? '' : '\nStatus: $status'}',
            ),
            isThreeLine: true,
          );
        },
      ),
    );
  }
}
