import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/templates.dart';
import '../admin/access_recoveries_screen.dart';
import '../trips/trip_detail_screen.dart';
import '../widgets/common.dart';

class NoticesScreen extends StatelessWidget {
  const NoticesScreen({super.key});

  Future<List<Notice>> _load(BuildContext context) async =>
      (await context.api.get('/notices', query: {'page[size]': 100})).resources.map(Notice.from).toList();

  Future<void> _read(BuildContext context, Notice notice) async {
    if (notice.readAt == null) {
      await context.api.patch('/notices/${notice.id}', {
        'data': {'type': 'notices', 'id': notice.id, 'attributes': {'readAt': DateTime.now().toUtc().toIso8601String()}},
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Avisos')),
      body: AsyncView<List<Notice>>(
        load: () => _load(context),
        builder: (context, notices, reload) => notices.isEmpty
            ? const EmptyView(icon: Icons.notifications_none, message: 'No tienes avisos.')
            : ListView(children: [
                for (final notice in notices)
                  ListTile(
                    leading: Icon(notice.readAt == null ? Icons.circle : Icons.circle_outlined, size: 12, color: Theme.of(context).colorScheme.primary),
                    title: Text(notice.title, style: TextStyle(fontWeight: notice.readAt == null ? FontWeight.bold : null)),
                    subtitle: Text(formatDateTime(notice.createdAt)),
                    onTap: () async {
                      await runAction(context, () => _read(context, notice));
                      if (notice.tripId != null && context.mounted) {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => TripDetailScreen(tripId: notice.tripId!)));
                      } else if (notice.accessRecoveryId != null && context.mounted) {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const AccessRecoveriesScreen()));
                      }
                      reload();
                    },
                  ),
              ]),
      ),
    );
  }
}
