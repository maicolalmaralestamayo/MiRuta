import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_exception.dart';
import '../../models/models.dart';
import '../../services/api/children_api.dart';
import '../../services/templates.dart';
import '../auth/names_fields.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import 'worker_common.dart';

/// Formulario de un hijo (docs/11 §11.11 y §11.18; maqueta pantallas-final.png, 3c).
///
/// Foto; nombres, apellidos y carné editables; sexo, nacimiento y «Derecho a
/// viajar hasta» de solo lectura (salen del carné y los calcula el servidor);
/// «También lo tiene declarado» (los otros padres).
/// Acciones: Guardar, Desactivar / Reactivar y Eliminar.
///
/// [child] null = hijo nuevo. [registered] = «Agregar hijo ya registrado»:
/// el mismo alta por carné; si otra persona ya lo declaró, se le asigna
/// también y se avisa. Sin derecho a viajar no se deja añadir (lo comprueba
/// el servidor al guardar).
class ChildFormScreen extends StatefulWidget {
  final Child? child;
  final bool registered;

  const ChildFormScreen({super.key, this.child, this.registered = false});

  @override
  State<ChildFormScreen> createState() => _ChildFormScreenState();
}

class _ChildFormScreenState extends State<ChildFormScreen> {
  final _form = GlobalKey<FormState>();
  late Child? _child = widget.child;
  late final _firstName = TextEditingController(text: _child?.name.firstName ?? '');
  late final _middleName = TextEditingController(text: _child?.name.middleName ?? '');
  late final _firstSurname = TextEditingController(text: _child?.name.firstSurname ?? '');
  late final _secondSurname = TextEditingController(text: _child?.name.secondSurname ?? '');
  late final _identityCard = TextEditingController(text: _child?.identityCard ?? '');
  late final _names = NamesFields(firstName: _firstName, middleName: _middleName, firstSurname: _firstSurname, secondSurname: _secondSurname);

  /// Foto elegida para un hijo nuevo (se sube al guardar).
  String? _pendingPhoto;
  ApiException? _error;

  bool get _isNew => _child == null;

  @override
  void dispose() {
    for (final c in [_firstName, _middleName, _firstSurname, _secondSurname, _identityCard]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _error = null);
    final api = ChildrenApi(context.api);
    final card = _identityCard.text.trim();
    try {
      if (_isNew) {
        final added = await api.add(name: _names.value, identityCard: card);
        if (_pendingPhoto != null) {
          try {
            await api.uploadPhoto(added.child.id, _pendingPhoto!);
          } catch (error) {
            if (mounted) showError(context, error);
          }
        }
        if (!mounted) return;
        if (added.alreadyDeclared) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Ya estaba declarado'),
              content: Text(added.notice ?? 'Ese niño ya está declarado por otra persona. Se le asignó también a usted.'),
              actions: [FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Aceptar'))],
            ),
          );
        } else {
          showMessage(context, 'Hijo añadido');
        }
        if (mounted) Navigator.pop(context);
      } else {
        final child = _child!;
        final updated = await api.update(child.id, name: _names.value, identityCard: card == (child.identityCard ?? '') ? null : card);
        if (!mounted) return;
        setState(() => _child = _keepParents(updated, child));
        showMessage(context, 'Hijo guardado');
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  /// La respuesta de PATCH puede no traer a los padres: se conservan.
  Child _keepParents(Child updated, Child before) => updated.parents.isNotEmpty || before.parents.isEmpty
      ? updated
      : Child(
          id: updated.id,
          name: updated.name,
          sex: updated.sex,
          birthDate: updated.birthDate,
          eligibleUntil: updated.eligibleUntil,
          eligible: updated.eligible,
          active: updated.active,
          photoUrl: updated.photoUrl,
          identityCard: updated.identityCard ?? before.identityCard,
          parents: before.parents,
        );

  Future<void> _toggleActive() async {
    final child = _child!;
    final updated = await ChildrenApi(context.api).setActive(child.id, !child.active);
    if (!mounted) return;
    setState(() => _child = _keepParents(updated, child));
    showMessage(context, updated.active ? 'Hijo reactivado' : 'Hijo desactivado');
  }

  Future<void> _remove() async {
    await ChildrenApi(context.api).remove(_child!.id);
    if (!mounted) return;
    showMessage(context, 'Hijo quitado');
    Navigator.pop(context);
  }

  Future<void> _photo() async {
    final child = _child;
    final hasPhoto = child?.photoUrl != null || _pendingPhoto != null;
    final choice = await pickFrom<String>(context, 'Foto del hijo', ['camera', 'gallery', if (hasPhoto) 'delete'],
        (c) => const {'camera': 'Hacer una foto', 'gallery': 'Elegir de la galería', 'delete': 'Quitar la foto'}[c]!);
    if (choice == null || !mounted) return;
    final api = ChildrenApi(context.api);
    if (choice == 'delete') {
      if (child == null) {
        setState(() => _pendingPhoto = null);
        return;
      }
      if (await runAction(context, () => api.deletePhoto(child.id))) await _refresh();
      return;
    }
    final file = await ImagePicker().pickImage(source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (file == null || !mounted) return;
    if (child == null) {
      setState(() => _pendingPhoto = file.path);
      return;
    }
    if (await runAction(context, () => api.uploadPhoto(child.id, file.path), success: 'Foto actualizada')) await _refresh();
  }

  Future<void> _refresh() async {
    final child = _child;
    if (child == null) return;
    try {
      final fresh = await ChildrenApi(context.api).get(child.id);
      if (mounted) setState(() => _child = _keepParents(fresh, child));
    } catch (_) {
      // Sin conexión: se queda lo que había.
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = _child;
    final card = _identityCard.text.trim();
    final birth = IdentityCard.birthDate(card) ?? (child?.birthDate == null ? null : DateTime.tryParse(child!.birthDate!));
    final sex = IdentityCard.sex(card) ?? child?.sex;
    final meId = context.me.id;
    final others = [for (final p in child?.parents ?? const <({String id, String fullName})>[]) if (p.id != meId) p];
    final unchangedCard = child != null && card == (child.identityCard ?? '');
    final eligibleText = child == null || !unchangedCard
        ? 'Se comprueba al guardar'
        : (!child.eligible ? 'Sin derecho a viajar' : formatShortDay(child.eligibleUntil));
    final title = child != null ? 'Hijo' : (widget.registered ? 'Agregar hijo ya registrado' : 'Hijo nuevo');

    return AppScaffold(
      title: title,
      actions: [
        ActionItem(icon: Icons.save, label: child == null ? (widget.registered ? 'Agregar' : 'Guardar') : 'Guardar', onPressed: _save),
        if (child != null) ...[
          ActionItem(
            icon: child.active ? Icons.toggle_off_outlined : Icons.toggle_on_outlined,
            label: child.active ? 'Desactivar' : 'Reactivar',
            confirmation: child.active ? '¿Desactivar a ${child.fullName}? Dejará de mostrarse en Inicio y no podrá marcarlo al subir.' : null,
            onPressed: _toggleActive,
          ),
          ActionItem(
            icon: Icons.delete_outline,
            label: 'Eliminar',
            destructive: true,
            confirmation: '¿Quitar a ${child.fullName} de sus hijos?${others.isEmpty ? '' : ' Seguirá siendo hijo de quien más lo tiene declarado.'}',
            onPressed: _remove,
          ),
        ],
      ],
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
          if (widget.registered && child == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('Escriba el carné de identidad y los nombres del niño que ya declaró otra persona (por ejemplo, el otro padre). '
                  'Se le asignará también a usted.'),
            ),
          Center(
            child: GestureDetector(
              onTap: _photo,
              child: Stack(children: [
                CardImage(
                  url: child?.photoUrl,
                  image: _pendingPhoto == null ? null : FileImage(File(_pendingPhoto!)),
                  icon: Icons.face,
                  round: true,
                  size: 104,
                  dim: child != null && !child.active,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(radius: 18, backgroundColor: Theme.of(context).colorScheme.secondary, child: const Icon(Icons.photo_camera, size: 18, color: Colors.black)),
                ),
              ]),
            ),
          ),
          if (child != null && !child.active)
            const Padding(padding: EdgeInsets.only(top: 8), child: Center(child: Text('Desactivado'))),
          const SizedBox(height: 16),
          _names,
          TextFormField(
            controller: _identityCard,
            decoration: InputDecoration(
              labelText: 'Carné de identidad',
              prefixIcon: const Icon(Icons.badge_outlined),
              errorText: _error?.fieldError('/identityCard'),
              errorMaxLines: 4,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(IdentityCard.length)],
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: (_) => setState(() {}),
            validator: IdentityCard.validate,
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Sexo y nacimiento', suffixIcon: Icon(Icons.lock_outline, size: 18)),
            child: Text([sexLabel(sex), if (birth != null) formatShortDate(birth)].where((s) => s.isNotEmpty).join(' • ')),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Derecho a viajar hasta', suffixIcon: Icon(Icons.lock_outline, size: 18)),
            child: Text(eligibleText),
          ),
          if (_error != null && _error!.fieldError('/identityCard') == null) ...[
            const SizedBox(height: 12),
            Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (others.isNotEmpty) ...[
            const SectionHeader('También lo tiene declarado'),
            for (final parent in others)
              InfoCard(images: const [CardImage(icon: Icons.person, round: true)], title: parent.fullName),
          ],
          const DeveloperChatFooter(),
        ]),
      ),
    );
  }
}
