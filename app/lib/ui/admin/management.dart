import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/models.dart';
import '../../services/session.dart';
import '../theme.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';

/// Piezas comunes de las pantallas de Gestión (docs/11 §11.18): la Entidad
/// con la que se trabaja (selector como el de Inicio, la tarjeta de la
/// Entidad con ↕), la imagen de Entidades, itinerarios y paradas, y copiar o
/// compartir un dato.

/// Entidades en las que se puede hacer una operación de Gestión.
abstract final class ManagementEntity {
  /// La Entidad con la que empezar: la última elegida en Gestión, la elegida
  /// en Inicio o la primera suya en la que pueda hacerla. null si no se sabe
  /// sin preguntar al servidor (p. ej. el Administrador sin Entidades propias).
  static Entity? initial(BuildContext context, String operation) {
    final session = context.read<Session>();
    final me = session.me!;
    final remembered = session.adminEntity;
    if (remembered != null && me.canInEntity(operation, remembered.id)) return remembered;
    final selected = session.selectedMembership;
    if (selected != null && me.canInEntity(operation, selected.entityId)) return selected.entity;
    for (final m in me.memberships) {
      if (me.canInEntity(operation, m.entityId)) return m.entity;
    }
    return null;
  }

  /// Todas las Entidades en las que puede hacerla (con ámbito «Todas», las de la app).
  static Future<List<Entity>> options(BuildContext context, String operation) async {
    final me = context.read<Session>().me!;
    if (me.permissions.entitiesFor(operation) == null) {
      return (await context.api.getAll('/entities', query: {'sort': 'abbreviation'})).map(Entity.from).toList();
    }
    return [for (final m in me.memberships) if (me.canInEntity(operation, m.entityId)) m.entity];
  }

  /// La recuerda para las demás pantallas de Gestión.
  static void remember(BuildContext context, Entity entity) => context.read<Session>().adminEntity = entity;
}

/// Estado de una pantalla de Gestión que depende de la Entidad: la resuelve
/// al empezar ([initEntity] en initState) y da el selector ([entitySelector]).
mixin ManagementEntityState<T extends StatefulWidget> on State<T> {
  /// Operación que decide en qué Entidades se puede trabajar.
  String get entityOperation;

  Entity? entity;

  /// Ya se sabe la Entidad (o que no hay ninguna).
  bool entityResolved = false;

  /// Se llama cuando cambia la Entidad (recargar la lista).
  void onEntityChanged();

  void initEntity() {
    entity = ManagementEntity.initial(context, entityOperation);
    entityResolved = entity != null;
    if (!entityResolved) _resolve();
  }

  Future<void> _resolve() async {
    List<Entity> options = const [];
    try {
      options = await ManagementEntity.options(context, entityOperation);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      entity = options.firstOrNull;
      entityResolved = true;
    });
    if (entity != null) onEntityChanged();
  }

  Widget entitySelector() => ManagementEntitySelector(
        operation: entityOperation,
        entity: entity,
        onChanged: (e) {
          setState(() => entity = e);
          onEntityChanged();
        },
      );

  /// Mientras se resuelve, o si no hay Entidad, lo que va en lugar del contenido.
  Widget? entityPlaceholder() {
    if (!entityResolved) return const Center(child: CircularProgressIndicator());
    if (entity == null) return const EmptyView(icon: Icons.apartment_outlined, message: 'No hay Entidades en las que pueda hacer esto.');
    return null;
  }
}

/// Selector de la Entidad en Gestión: la tarjeta de la Entidad con ↕ (como
/// en Inicio). Al tocarla se abre la lista de Entidades en las que puede
/// hacer [operation], con ✓ en la elegida.
class ManagementEntitySelector extends StatelessWidget {
  final String operation;
  final Entity? entity;
  final ValueChanged<Entity> onChanged;

  const ManagementEntitySelector({super.key, required this.operation, required this.entity, required this.onChanged});

  Future<void> _pick(BuildContext context) async {
    final picked = await showModalBottomSheet<Entity>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.8),
          child: FutureBuilder<List<Entity>>(
            future: ManagementEntity.options(context, operation),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return snapshot.hasError
                    ? const Padding(padding: EdgeInsets.all(24), child: Text('No se pudieron cargar las Entidades.'))
                    : const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
              }
              return ListView(shrinkWrap: true, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Entidades', style: Theme.of(context).textTheme.headlineSmall),
                ),
                for (final e in snapshot.data!) EntityCard(e, checked: e.id == entity?.id, onTap: () => Navigator.pop(sheetContext, e)),
                const SizedBox(height: 12),
              ]);
            },
          ),
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    ManagementEntity.remember(context, picked);
    onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    if (entity == null) {
      return InfoCard(images: const [CardImage(icon: Icons.apartment)], title: 'Elija una Entidad', lines: const ['Toque aquí para elegirla'], onTap: () => _pick(context));
    }
    return EntityCard(entity, selector: true, onTap: () => _pick(context));
  }
}

/// Imagen de una Entidad, un itinerario o una parada (docs/11 §11.10): sin
/// imagen, el ícono. Si [uploadPath] no es null se puede cambiar o quitar
/// (POST/DELETE `<uploadPath>`, campo `image`).
class ImageEditor extends StatelessWidget {
  final String? url;
  final IconData icon;
  final String? uploadPath;
  final VoidCallback? onChanged;

  const ImageEditor({super.key, this.url, required this.icon, this.uploadPath, this.onChanged});

  Future<void> _change(BuildContext context) async {
    final choice = await pickFrom<String>(context, 'Imagen', [
      'gallery',
      'camera',
      if (url != null) 'delete',
    ], (c) => const {'gallery': 'Elegir de la galería', 'camera': 'Tomar una foto', 'delete': 'Quitar la imagen'}[c]!);
    if (choice == null || !context.mounted) return;
    final api = context.api;
    if (choice == 'delete') {
      if (await runAction(context, () => api.delete(uploadPath!), success: 'Imagen quitada')) onChanged?.call();
      return;
    }
    final file = await ImagePicker().pickImage(source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
    if (file == null || !context.mounted) return;
    if (await runAction(context, () => api.upload(uploadPath!, 'image', file.path), success: 'Imagen guardada')) onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final image = CardImage(url: url, icon: icon, size: 110);
    if (uploadPath == null) return Center(child: image);
    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _change(context),
        child: Stack(clipBehavior: Clip.none, children: [
          image,
          Positioned(
            right: -6,
            bottom: -6,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(color: orange, shape: BoxShape.circle),
              child: const Icon(Icons.photo_camera, size: 18, color: Colors.black),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Un dato que se puede copiar y compartir (usuario, contraseña…).
class CopyShareField extends StatelessWidget {
  final String label;
  final String value;

  /// Texto que se comparte (por defecto, «label: value»).
  final String? shareText;

  const CopyShareField({super.key, required this.label, required this.value, this.shareText});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'Copiar ${label.toLowerCase()}',
              icon: const Icon(Icons.copy),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (context.mounted) showMessage(context, '$label copiado.');
              },
            ),
            IconButton(
              tooltip: 'Compartir',
              icon: const Icon(Icons.share),
              onPressed: () => SharePlus.instance.share(ShareParams(text: shareText ?? '$label: $value')),
            ),
          ]),
        ),
        child: SelectableText(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// Campo de solo lectura con el aspecto de los demás.
class ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;

  const ReadOnlyField({super.key, required this.label, required this.value, this.icon});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, enabled: false, suffixIcon: Icon(icon ?? Icons.lock_outline, size: 18)),
          child: Text(value.isEmpty ? '—' : value),
        ),
      );
}

/// «Solicitada el mar. 03/11/26».
String requestedOn(DateTime? date, {String verb = 'Solicitada'}) => date == null ? '' : '$verb el ${formatDay(date)}';

/// Fecha con día de la semana (docs/09): «mar. 03/11/26».
String formatDay(DateTime date) {
  const days = ['lun.', 'mar.', 'mié.', 'jue.', 'vie.', 'sáb.', 'dom.'];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${days[date.weekday - 1]} ${two(date.day)}/${two(date.month)}/${two(date.year % 100)}';
}
