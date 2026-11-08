import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formats.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/data_view.dart';
import 'conversation_screen.dart';

/// Conversaciones con el desarrollador (docs/11 §11.46): solo texto y con
/// motivo. El Administrador ve todas y las responde.
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  final _view = GlobalKey<DataViewState<List<Conversation>>>();

  Future<List<Conversation>> _load() async =>
      (await context.read<Session>().api.getAll('/conversations', query: {'include': 'topic,user'})).map(Conversation.from).toList();

  Future<void> _open(Conversation c) async {
    await push(context, ConversationScreen(conversationId: c.id, topic: c.topic, person: context.read<Session>().me!.isAdmin ? c.userName : null));
    _view.currentState?.reload();
  }

  Future<void> _new() async {
    final api = context.read<Session>().api;
    final topics = (await api.getAll('/conversation-topics', query: {'filter[active]': 'true'})).map(NomenclatorItem.from).toList();
    if (!mounted) return;
    final topic = await pickOne<NomenclatorItem>(context, 'Motivo', topics, (t) => t.name, subtitle: (t) => t.description ?? '');
    if (topic == null || !mounted) return;
    final body = await promptText(context, 'Mensaje al desarrollador', label: 'Mensaje', required: true, maxLines: 5, accept: 'Enviar', icon: Icons.send);
    if (body == null || !mounted) return;
    final created = (await api.post('/conversations', resourceData('conversations', attributes: {'body': body}, relationships: {'topic': ResourceId('conversation-topics', topic.id)}))).resource;
    if (!mounted) return;
    await push(context, ConversationScreen(conversationId: created.id, topic: topic.name));
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.read<Session>().me!.isAdmin;
    return AppScaffold(
      title: 'Conversaciones',
      tab: MainTab.more,
      actions: () => [ActionItem(Icons.add_comment_outlined, 'Escribir al desarrollador', _new)],
      body: DataView<List<Conversation>>(
        key: _view,
        kinds: const {'conversations'},
        load: _load,
        builder: (context, list, reload) => ListView(padding: const EdgeInsets.only(bottom: 96), physics: const AlwaysScrollableScrollPhysics(), children: [
          FoldSection<Conversation>(
            storageKey: 'conversaciones',
            title: 'Conversaciones',
            items: list,
            emptyText: 'Aún no ha escrito al desarrollador. Use Acciones → Escribir al desarrollador.',
            builder: (c) => InfoCard(
              images: const [CardImage(icon: Icons.forum_outlined)],
              title: admin ? (c.userName ?? 'Persona') : (c.topic ?? 'Conversación'),
              lines: [if (admin && c.topic != null) 'Motivo: ${c.topic}', c.lastMessage ?? '', formatDateTime(c.updatedAt)],
              chip: c.unread ? const Chip2('Nuevo', amber) : null,
              onTap: () => _open(c),
            ),
          ),
        ]),
      ),
    );
  }
}
