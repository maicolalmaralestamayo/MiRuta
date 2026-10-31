import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/sync.dart';
import '../../services/templates.dart';
import '../widgets/common.dart';

/// Chat de solo texto: el del viaje, el de una conversación con motivo o,
/// sin cuenta, el de una conversación con el desarrollador.
class ChatScreen extends StatefulWidget {
  final String title;
  final String listPath;
  final String postType;
  final String relationship;
  final String relationshipType;
  final String parentId;
  final String pollSetting;
  final String? conversationId;
  final String? tripId;

  /// Sin cuenta: identifica la instalación en lugar de la sesión.
  final bool guest;
  final bool closed;

  /// Nombre de quien abrió sin cuenta (para mostrarlo en sus mensajes).
  final String? guestName;

  const ChatScreen._({
    required this.title,
    required this.listPath,
    required this.postType,
    required this.relationship,
    required this.relationshipType,
    required this.parentId,
    required this.pollSetting,
    this.conversationId,
    this.tripId,
    this.guest = false,
    this.closed = false,
    this.guestName,
  });

  factory ChatScreen.trip({required String tripId, required String title}) => ChatScreen._(
        title: 'Chat · $title',
        listPath: '/trips/$tripId/messages',
        postType: 'trip-messages',
        relationship: 'trip',
        relationshipType: 'trips',
        parentId: tripId,
        pollSetting: 'trip_chat_poll_foreground_seconds',
        tripId: tripId,
      );

  factory ChatScreen.conversation({required Conversation conversation}) => ChatScreen._(
        title: conversation.topicName ?? 'Conversación',
        listPath: '/conversations/${conversation.id}/messages',
        postType: 'conversation-messages',
        relationship: 'conversation',
        relationshipType: 'conversations',
        parentId: conversation.id,
        pollSetting: 'conversations_poll_foreground_seconds',
        conversationId: conversation.id,
        closed: conversation.closed,
        guestName: conversation.guest ? conversation.guestName : null,
      );

  /// Conversación con el desarrollador sin cuenta (desde esta instalación).
  factory ChatScreen.guest({required Conversation conversation}) => ChatScreen._(
        title: conversation.topicName ?? 'Desarrollador',
        listPath: '/guest/conversations/${conversation.id}/messages',
        postType: 'conversation-messages',
        relationship: 'conversation',
        relationshipType: 'conversations',
        parentId: conversation.id,
        pollSetting: '',
        guest: true,
        closed: conversation.closed,
      );

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messages = <Message>[];
  final _text = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
    final seconds = widget.guest ? 15 : context.session.settings.integer(widget.pollSetting, 10);
    _timer = Timer.periodic(Duration(seconds: seconds), (_) => _load());
  }

  Future<void> _load() async {
    try {
      final since = _messages.isEmpty ? null : _messages.last.createdAt.toUtc().toIso8601String();
      final query = {'include': 'author', 'filter[since]': ?since, 'page[size]': 100};
      final resources = widget.guest
          ? (await context.api.get(widget.listPath, query: query, guest: true)).resources
          : await context.api.getAll(widget.listPath, query: query);
      final fresh = resources.map(Message.from).where((m) => !_messages.any((old) => old.id == m.id)).toList();
      if (!mounted) return;
      setState(() {
        _messages.addAll(fresh);
        _error = null;
      });
      if (fresh.isNotEmpty) {
        _scrollDown();
        if (widget.conversationId != null) await SyncService.markConversationSeen(widget.conversationId!, _messages.last.createdAt);
        if (widget.tripId != null) await SyncService.markTripChatSeen(widget.tripId!, _messages.last.createdAt);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    final ok = await runAction(
        context,
        () => widget.guest
            ? context.api.post(widget.listPath, resourceData(widget.postType, attributes: {'body': body}), guest: true)
            : context.api.post('/${widget.postType}', resourceData(widget.postType, attributes: {'body': body}, relationships: {
                  widget.relationship: ResourceId(widget.relationshipType, widget.parentId),
                })));
    if (ok) {
      _text.clear();
      await _load();
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meId = widget.guest ? null : context.me.userId;
    final closed = widget.closed;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        if (_error != null) MaterialBanner(content: Text(_error!), actions: [TextButton(onPressed: _load, child: const Text('Reintentar'))]),
        Expanded(
          child: _messages.isEmpty
              ? const Center(child: Text('Todavía no hay mensajes.'))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(8),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    // Sin cuenta, los propios son los que no tienen autor.
                    final mine = widget.guest ? message.authorId == null : message.authorId == meId;
                    final author = message.authorName ?? (message.authorId == null ? widget.guestName : null);
                    final colors = Theme.of(context).colorScheme;
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: mine ? colors.primaryContainer : colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (!mine && author != null) Text(author, style: TextStyle(fontWeight: FontWeight.bold, color: colors.primary, fontSize: 12)),
                          Text(message.body),
                          Text(formatDateTime(message.createdAt), style: Theme.of(context).textTheme.bodySmall),
                        ]),
                      ),
                    );
                  },
                ),
        ),
        if (closed)
          const SafeArea(top: false, child: Padding(padding: EdgeInsets.all(16), child: Text('La conversación está cerrada.')))
        else
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Escribe un mensaje'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: _sending ? null : _send, icon: _sending ? const BusyIndicator() : const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}
