import 'package:flutter/material.dart';

import '../utils/app_logger.dart';

class LogScreen extends StatelessWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Logs')),
      body: ValueListenableBuilder<List<LogEntry>>(
        valueListenable: AppLogger.instance.logs,
        builder: (context, logs, _) {
          if (logs.isEmpty) {
            return const Center(child: Text('No log entries'));
          }
          return ListView.separated(
            itemCount: logs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = logs[index];
              final color = switch (entry.level) {
                LogLevel.success => Colors.green,
                LogLevel.error => Colors.red,
                LogLevel.info => Colors.blue,
              };
              return ListTile(
                leading: Icon(switch (entry.level) {
                  LogLevel.success => Icons.check_circle,
                  LogLevel.error => Icons.error,
                  LogLevel.info => Icons.info,
                }, color: color),
                title: Text(entry.message),
                subtitle: Text(entry.timestamp.toLocal().toIso8601String()),
              );
            },
          );
        },
      ),
    );
  }
}
