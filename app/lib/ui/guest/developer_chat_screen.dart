import 'package:flutter/material.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../chat/chat_screen.dart';
import '../../services/templates.dart';
import '../widgets/common.dart';

/// Hablar con el desarrollador sin cuenta (docs/08-version-2.md §8.7): desde
/// el inicio de sesión, la creación de la cuenta o la unión a la Entidad.
/// El desarrollador responde dentro de la app, en este mismo teléfono.
class GuestConversationsScreen extends StatefulWidget {
  const GuestConversationsScreen({super.key});

  @override
  State<GuestConversationsScreen> createState() => _GuestConversationsScreenState();
}

class _GuestConversationsScreenState extends State<GuestConversationsScreen> {
  final _view = GlobalKey<AsyncViewState<List<Conversation>>>();

  Future<List<Conversation>> _load() async {
    final document = await context.api.get('/guest/conversations', query: {'include': 'topic', 'page[size]': 100}, guest: true);
    return document.resources.map(Conversation.from).toList();
  }

  Future<void> _new() async {
    final created = await Navigator.push<Conversation>(context, MaterialPageRoute(builder: (_) => const NewGuestConversationScreen()));
    if (created == null || !mounted) return;
    _view.currentState?.reload();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen.guest(conversation: created)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hablar con el desarrollador')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _new, icon: const Icon(Icons.edit), label: const Text('Escribir')),
      body: AsyncView<List<Conversation>>(
        key: _view,
        load: _load,
        builder: (context, conversations, reload) => conversations.isEmpty
            ? const EmptyView(
                icon: Icons.support_agent,
                message: 'Escribe al desarrollador si tienes dudas, ideas o problemas, aunque todavía no tengas cuenta. Te responderá aquí mismo.',
              )
            : ListView(children: [
                for (final conversation in conversations)
                  ListTile(
                    leading: const Icon(Icons.forum_outlined),
                    title: Text(conversation.topicName ?? 'Conversación'),
                    subtitle: Text(conversation.closed ? 'Cerrada' : 'Último mensaje: ${conversation.lastMessageAt == null ? '—' : formatDateTime(conversation.lastMessageAt!)}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen.guest(conversation: conversation))),
                  ),
              ]),
      ),
    );
  }
}

class NewGuestConversationScreen extends StatefulWidget {
  const NewGuestConversationScreen({super.key});

  @override
  State<NewGuestConversationScreen> createState() => _NewGuestConversationScreenState();
}

class _NewGuestConversationScreenState extends State<NewGuestConversationScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _body = TextEditingController();
  List<Named> _topics = [];
  String? _topicId;

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  Future<void> _loadTopics() async {
    try {
      final document = await context.api.get('/conversation-topics', query: {'page[size]': 100}, guest: true);
      final topics = document.resources.where((r) => r.string('recipient') == 'developer').map(Named.from).toList();
      if (mounted) setState(() => _topics = topics);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    final document = await context.api.post(
      '/guest/conversations',
      resourceData('conversations', attributes: {
        'guestName': _name.text.trim(),
        'guestPhone': _phone.text.trim(),
        'body': _body.text.trim(),
      }, relationships: {'topic': ResourceId('conversation-topics', _topicId!)}),
      guest: true,
    );
    if (mounted) Navigator.pop(context, Conversation.from(document.resource));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escribir al desarrollador')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('El desarrollador te responderá dentro de la app, en este teléfono. Tu teléfono solo lo ve él, por si necesita llamarte.'),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Tu nombre'),
            textCapitalization: TextCapitalization.words,
            validator: (v) => v == null || v.trim().isEmpty ? 'Escribe tu nombre' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Teléfono', helperText: 'Con el código del país, p. ej. +53 5 123 4567'),
            keyboardType: TextInputType.phone,
            validator: (v) => RegExp(r'^\+?[0-9 ()\-]{7,20}$').hasMatch(v?.trim() ?? '') ? null : 'Escribe un teléfono válido',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _topicId,
            decoration: const InputDecoration(labelText: 'Motivo'),
            items: [for (final topic in _topics) DropdownMenuItem(value: topic.id, child: Text(topic.name))],
            onChanged: (value) => setState(() => _topicId = value),
            validator: (v) => v == null ? 'Elige el motivo' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _body,
            decoration: const InputDecoration(labelText: 'Mensaje'),
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            validator: (v) => v == null || v.trim().isEmpty ? 'Escribe el mensaje' : null,
          ),
          const SizedBox(height: 20),
          BusyButton(onPressed: _send, icon: const Icon(Icons.send), child: const Text('Enviar')),
        ]),
      ),
    );
  }
}

/// Acción "Hablar con el desarrollador" para las barras de las pantallas sin sesión.
class DeveloperChatAction extends StatelessWidget {
  const DeveloperChatAction({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Hablar con el desarrollador',
        icon: const Icon(Icons.support_agent),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GuestConversationsScreen())),
      );
}
