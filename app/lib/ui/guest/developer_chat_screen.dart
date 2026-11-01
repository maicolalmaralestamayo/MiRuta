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
      floatingActionButton: FloatingActionButton.extended(onPressed: _new, icon: const Icon(Icons.edit), label: const Text('Escribir mensaje')),
      body: AsyncView<List<Conversation>>(
        key: _view,
        load: _load,
        builder: (context, conversations, reload) => conversations.isEmpty
            ? const EmptyView(
                icon: Icons.support_agent,
                message: 'Escriba al desarrollador si tiene dudas, ideas o problemas, aunque todavía no tenga cuenta. Le responderá aquí mismo.',
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
  final _phone = TextEditingController(text: phonePrefix);
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
          const Text('El desarrollador le responderá dentro de la app, en este teléfono. Su teléfono solo lo ve él, por si necesita llamarle.'),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nombre y apellidos', hintText: 'p. ej. Ana Pérez García'),
            textCapitalization: TextCapitalization.words,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (v) => v == null || v.trim().isEmpty ? 'Escriba su nombre y apellidos' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Teléfono', hintText: 'p. ej. +53 5 123 4567'),
            keyboardType: TextInputType.phone,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (v) => RegExp(r'^\+?[0-9 ()\-]{7,20}$').hasMatch(v?.trim() ?? '') ? null : 'Escriba un teléfono válido, con el código del país (p. ej. +53 5 123 4567)',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _topicId,
            decoration: const InputDecoration(labelText: 'Motivo'),
            items: [for (final topic in _topics) DropdownMenuItem(value: topic.id, child: Text(topic.name))],
            onChanged: (value) => setState(() => _topicId = value),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (v) => v == null ? 'Elija el motivo' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _body,
            decoration: const InputDecoration(labelText: 'Mensaje', hintText: 'p. ej. No encuentro mi Entidad al registrarme'),
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (v) => v == null || v.trim().isEmpty ? 'Escriba el mensaje' : null,
          ),
          const SizedBox(height: 20),
          BusyButton(onPressed: _send, icon: const Icon(Icons.send), child: const Text('Enviar mensaje')),
        ]),
      ),
    );
  }
}
