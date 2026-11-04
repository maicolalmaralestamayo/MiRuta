import 'package:flutter/material.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/templates.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
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

  /// A quién va un motivo: el rol al que va dirigido o el desarrollador.
  static String _recipientOf(Named topic) => topic.extra['recipient'] == 'developer' ? 'Desarrollador' : '${topic.extra['roleName'] ?? 'Rol'}';

  Future<void> _new() async {
    // Motivos dirigidos a un rol (Jefe de itinerario, Jefe de Transporte…) o al desarrollador.
    final topics = (await context.api.getAll('/conversation-topics', query: {'sort': 'name'})).map(Named.from).toList();
    if (!mounted) return;
    final topic = await pickFrom<Named>(context, '¿Sobre qué desea escribir?', topics, (t) => t.name, subtitle: _recipientOf);
    if (topic == null || !mounted) return;
    final entityId = context.session.selectedEntityId;
    try {
      final conversation = Conversation.from((await context.api.post('/conversations', resourceData('conversations', relationships: {
        'topic': ResourceId('conversation-topics', topic.id),
        // Si pertenece a varias Entidades, a la elegida.
        if (topic.extra['recipient'] != 'developer' && entityId != null) 'entity': ResourceId('entities', entityId),
      }))).resource);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen.conversation(conversation: Conversation(
            id: conversation.id, recipient: '${topic.extra['recipient']}', createdAt: conversation.createdAt, topicName: topic.name, roleName: topic.extra['roleName'] as String?))));
      _view.currentState?.reload();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meId = context.me.userId;
    return AppScaffold(
      title: 'Mensajes',
      tab: MainTab.messages,
      actions: [ActionItem(icon: Icons.edit, label: 'Escribir mensaje', onPressed: _new)],
      body: AsyncView<List<Conversation>>(
        key: _view,
        load: _load,
        builder: (context, conversations, reload) => conversations.isEmpty
            ? const EmptyView(icon: Icons.forum_outlined, message: 'No tiene conversaciones.\nLas conversaciones se borran pasado un tiempo sin mensajes.')
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final c = conversations[index];
                  final incoming = c.guest || (c.openedById != null && c.openedById != meId);
                  return ListTile(
                    leading: Icon(c.recipient == 'developer' ? Icons.code : Icons.groups),
                    title: Text(c.topicName ?? 'Conversación'),
                    subtitle: Text([
                      c.recipientLabel,
                      if (incoming) 'de ${c.guest ? '${c.guestName ?? ''} (sin cuenta)' : c.openedByName ?? ''}',
                      plural(c.messageCount, 'mensaje', 'mensajes'),
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
