import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formats.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../navigation.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';

/// Conversación con el desarrollador, estilo WhatsApp (docs/11 §11.50,
/// maqueta G18 n.º 16): burbujas propias a la derecha y ajenas a la
/// izquierda, hora en cada mensaje y campo de texto abajo. Se consulta cada
/// «Frecuencia chat» mientras está abierta.
class ConversationScreen extends StatefulWidget {
  final String conversationId;
  final String? topic;
  final String? person;

  const ConversationScreen({super.key, required this.conversationId, this.topic, this.person});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _messages = <Message>[];
  final _text = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  bool _sending = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _poll();
    final every = context.read<Session>().settings.duration('frecuencia_chat');
    _timer = Timer.periodic(every < const Duration(seconds: 2) ? const Duration(seconds: 2) : every, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final after = _messages.isEmpty ? null : _messages.last.id;
      final list = (await context.read<Session>().api.getAll('/conversations/${widget.conversationId}/messages', query: {'filter[after]': ?after})).map(Message.from).toList();
      if (!mounted) return;
      final known = _messages.map((m) => m.id).toSet();
      final fresh = list.where((m) => !known.contains(m.id)).toList();
      setState(() {
        _messages.addAll(fresh);
        _loaded = true;
      });
      if (fresh.isNotEmpty) _toBottom();
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    final ok = await runAction(context, () async {
      final m = Message.from((await context.read<Session>().api.post('/conversations/${widget.conversationId}/messages', resourceData('conversation-messages', attributes: {'body': body}))).resource);
      if (!_messages.any((x) => x.id == m.id)) _messages.add(m);
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      _text.clear();
      _toBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxLength = context.read<Session>().settings.integer('longitud_mensaje');
    final items = <Widget>[];
    DateTime? day;
    for (final m in _messages) {
      final d = DateTime(m.createdAt.year, m.createdAt.month, m.createdAt.day);
      if (day != d) {
        day = d;
        items.add(Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: const Color(0xFFE1F0FA), borderRadius: BorderRadius.circular(8)),
            child: Text(formatDate(m.createdAt), style: const TextStyle(fontSize: 12)),
          ),
        ));
      }
      items.add(_Bubble(message: m));
    }
    return AppScaffold(
      title: widget.person ?? 'Desarrollador',
      subtitle: widget.topic == null ? null : 'Motivo: ${widget.topic}',
      tab: MainTab.more,
      background: const Color(0xFFECE5DD),
      bottom: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _text,
                minLines: 1,
                maxLines: 5,
                maxLength: maxLength > 0 ? maxLength : null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Mensaje',
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              tooltip: 'Enviar',
              onPressed: _sending ? null : _send,
              icon: _sending ? const BusyIndicator(size: 18, color: Colors.white) : const Icon(Icons.send),
            ),
          ]),
        ),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(controller: _scroll, padding: const EdgeInsets.all(8), children: items),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Message message;

  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final mine = message.mine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
        decoration: BoxDecoration(color: mine ? const Color(0xFFFFE0B2) : Colors.white, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!mine && message.fromDeveloper) const Text('Desarrollador', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF000080))),
          Text(message.body, style: const TextStyle(fontSize: 15)),
          Align(alignment: Alignment.centerRight, child: Text(formatTime(message.createdAt), style: const TextStyle(fontSize: 11, color: grey))),
        ]),
      ),
    );
  }
}
