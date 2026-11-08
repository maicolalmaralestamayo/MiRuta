import 'package:flutter/foundation.dart';

/// Tarjetas marcadas (docs/11 §11.23 y §11.26): se marca un solo tipo a la
/// vez; al marcar una de otro tipo se desmarcan las anteriores.
class Marks extends ChangeNotifier {
  String? _type;
  final Set<String> _keys = {};

  String? get type => _type;

  Set<String> get keys => Set.unmodifiable(_keys);

  int get count => _keys.length;

  bool get active => _keys.isNotEmpty;

  bool get one => _keys.length == 1;

  bool isMarked(String type, String key) => _type == type && _keys.contains(key);

  bool isType(String type) => _type == type && _keys.isNotEmpty;

  void toggle(String type, String key) {
    if (_type != type) {
      _keys.clear();
      _type = type;
    }
    if (!_keys.remove(key)) _keys.add(key);
    if (_keys.isEmpty) _type = null;
    notifyListeners();
  }

  void markAll(Iterable<String> keys) {
    _keys.addAll(keys);
    notifyListeners();
  }

  void invert(Iterable<String> all) {
    final next = all.toSet().difference(_keys);
    _keys
      ..clear()
      ..addAll(next);
    if (_keys.isEmpty) _type = null;
    notifyListeners();
  }

  void clear() {
    if (_keys.isEmpty && _type == null) return;
    _keys.clear();
    _type = null;
    notifyListeners();
  }

  /// Quita las marcas que ya no existen (tras recargar).
  void retain(String type, Iterable<String> existing) {
    if (_type != type) return;
    final before = _keys.length;
    _keys.retainAll(existing.toSet());
    if (_keys.isEmpty) _type = null;
    if (before != _keys.length) notifyListeners();
  }

  /// Los elementos marcados de [items].
  List<T> of<T>(String type, Iterable<T> items, String Function(T) keyOf) =>
      _type != type ? <T>[] : items.where((i) => _keys.contains(keyOf(i))).toList();
}
