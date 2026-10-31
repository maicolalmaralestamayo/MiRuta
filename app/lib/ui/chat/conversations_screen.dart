import 'package:flutter/material.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/templates.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

/// Conversaciones con los Jefes de itinerario, los Jefes de Transporte o el
/// desarrollador. Se abren eligiendo un motivo.
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  final _view = GlobalKey<AsyncViewState<List<Conversation>>>();

  Future<List<Conversation>> _load() async {
    final resources = await context.api.getAll('/conversations', query: {'include': 'topic,openedBy', 'sort': '-lastMessageAt'});
    return resources.map(Conversation.from).toList();
  }

  Future<void> _new() async {
    final recipient = await pickFrom<String>(context, '¿A quién quieres escribir?', ['itinerary_chiefs', 'transport_chiefs', 'developer'], Conversation.recipientLabel);
    if (recipient == null || !mounted) return;
    final topics = (await context.api.getAll('/conversation-topics', query: {'filter[recipient]': recipient})).map(Named.from).toList();
    if (!mounted) return;
    final topic = await pickFrom<Named>(context, 'Motivo', topics, (t) => t.name);
    if (topic == null || !mounted) return;
    try {
      final conversation = Conversation.from((await context.api.post('/conversations', resourceData('conversations', relationships: {
        'topic': ResourceId('conversation-topics', topic.id),
      }))).resource);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen.conversation(conversation: Conversation(
            id: conversation.id, recipient: recipient, createdAt: conversation.createdAt, topicName: topic.name))));
      _view.currentState?.reload();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meId = context.me.userId;
    return Scaffold(
      appBar: AppBar(title: const Text('Mensajes')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _new, icon: const Icon(Icons.edit), label: const Text('Escribir')),
      body: AsyncView<List<Conversation>>(
        key: _view,
        load: _load,
        builder: (context, conversations, reload) => conversations.isEmpty
            ? const EmptyView(icon: Icons.forum_outlined, message: 'No tienes conversaciones.\nLas conversaciones se borran pasado un tiempo sin mensajes.')
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final c = conversations[index];
                  final incoming = c.guest || (c.openedById != null && c.openedById != meId);
                  return ListTile(
                    leading: Icon(const {'itinerary_chiefs': Icons.groups, 'transport_chiefs': Icons.directions_bus, 'developer': Icons.code}[c.recipient] ?? Icons.forum),
                    title: Text(c.topicName ?? 'Conversación'),
                    subtitle: Text([
                      Conversation.recipientLabel(c.recipient),
                      if (incoming) 'de ${c.guest ? '${c.guestName ?? ''} (sin cuenta)' : c.openedByName ?? ''}',
                      '${c.messageCount} mensaje(s)',
                      if (c.lastMessageAt != null) formatDateTime(c.lastMessageAt!),
                    ].join(' · ')),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen.conversation(conversation: c)));
                      reload();
                    },
                  );
                },
              ),
      ),
    );
  }
}
