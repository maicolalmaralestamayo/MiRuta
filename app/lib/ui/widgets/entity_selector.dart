import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api/memberships_api.dart';
import '../../services/session.dart';
import '../auth/entity_field.dart';
import '../theme.dart';
import 'cards.dart';
import 'common.dart';

/// Selector de Entidad (docs/11 §11.10 y §11.18): la tarjeta de la Entidad
/// elegida con ↕. Al tocarla se abre la hoja «Mis Entidades» con ✓ en la
/// elegida y, al final, «Solicitar entrar en otra Entidad» y «Darme de baja
/// de esta Entidad». La elegida se recuerda en el teléfono (Session).
///
/// Sin Entidad muestra la tarjeta «Sin Entidad», que abre la solicitud (o,
/// para el Administrador, «Unirme a una Entidad»).
///
/// Lea la Entidad elegida con `context.watch<Session>().selectedMembership`.
class EntitySelector extends StatelessWidget {
  /// Se llama después de elegir otra Entidad (la sesión ya avisa a quien la mire).
  final ValueChanged<Membership>? onChanged;

  const EntitySelector({super.key, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final membership = session.selectedMembership;
    if (membership == null) {
      return EntityCard(null, onTap: () => session.me?.isAdmin == true ? joinEntityAsAdmin(context) : requestEntityMembership(context));
    }
    return EntityCard(membership.entity, selector: true, onTap: () async {
      final picked = await showMyEntitiesSheet(context);
      if (picked != null) onChanged?.call(picked);
    });
  }
}

/// Hoja «Mis Entidades». Devuelve la pertenencia elegida (ya guardada como
/// la elegida en la sesión) o null.
Future<Membership?> showMyEntitiesSheet(BuildContext context) {
  final session = context.read<Session>();
  return showModalBottomSheet<Membership>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final me = session.me!;
      final selected = session.selectedEntityId;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.8),
          child: ListView(shrinkWrap: true, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Mis Entidades', style: Theme.of(sheetContext).textTheme.headlineSmall),
            ),
            for (final m in me.memberships)
              EntityCard(m.entity, checked: m.entityId == selected, onTap: () async {
                await session.selectEntity(m.entityId);
                if (sheetContext.mounted) Navigator.pop(sheetContext, m);
              }),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.add_business_outlined),
              title: Text(me.isAdmin ? 'Unirme a otra Entidad' : 'Solicitar entrar en otra Entidad'),
              onTap: () {
                Navigator.pop(sheetContext);
                me.isAdmin ? joinEntityAsAdmin(context) : requestEntityMembership(context);
              },
            ),
            if (selected != null)
              ListTile(
                leading: const Icon(Icons.logout, color: overloadColor),
                title: const Text('Darme de baja de esta Entidad', style: TextStyle(color: overloadColor)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  leaveEntity(context, me.membershipIn(selected)!);
                },
              ),
          ]),
        ),
      );
    },
  );
}

/// Pide la abreviatura de una Entidad (se comprueba y se muestra su nombre
/// para confirmar; nunca se muestra la lista). Devuelve la abreviatura.
Future<String?> askEntityAbbreviation(BuildContext context, {required String title, required String accept, String? message}) {
  final controller = TextEditingController();
  final form = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Form(
        key: form,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (message != null) ...[Text(message), const SizedBox(height: 12)],
          EntityAbbreviationField(controller: controller),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) Navigator.pop(dialogContext, controller.text.trim());
          },
          child: Text(accept),
        ),
      ],
    ),
  );
}

/// «Solicitar entrar en una Entidad» (docs/11 §11.6): la aprueba el Administrador.
Future<bool> requestEntityMembership(BuildContext context) async {
  final abbreviation = await askEntityAbbreviation(context,
      title: 'Solicitar entrar en una Entidad', accept: 'Solicitar', message: 'Escriba la abreviatura de la Entidad. La solicitud la aprueba el Administrador.');
  if (abbreviation == null || !context.mounted) return false;
  return runAction(context, () => MembershipsApi(context.api).requestEntity(abbreviation),
      success: 'Solicitud enviada. Le avisaremos cuando la resuelvan.');
}

/// «Unirme a una Entidad» del Administrador (docs/11 §11.13), sin solicitud.
Future<bool> joinEntityAsAdmin(BuildContext context) async {
  final abbreviation = await askEntityAbbreviation(context,
      title: 'Unirme a una Entidad', accept: 'Unirme', message: 'Como Administrador entra directamente, sin solicitud, y sigue siendo Administrador.');
  if (abbreviation == null || !context.mounted) return false;
  final session = context.session;
  return runAction(context, () => session.joinEntity(abbreviation), success: 'Ya pertenece a $abbreviation.');
}

/// «Darme de baja de esta Entidad» (docs/11 §11.6): pierde allí itinerario,
/// parada y roles; para volver tiene que solicitarlo de nuevo.
Future<bool> leaveEntity(BuildContext context, Membership membership) async {
  final ok = await confirm(
    context,
    'Darme de baja de ${membership.entity.abbreviation}',
    'Perderá su itinerario, su parada y sus roles en ${membership.entity.abbreviation}. Para volver tendrá que solicitarlo de nuevo. ¿Darse de baja?',
    accept: 'Darme de baja',
    destructive: true,
  );
  if (!ok || !context.mounted) return false;
  final session = context.session;
  return runAction(context, () => session.leaveEntity(membership.entityId), success: 'Se dio de baja de ${membership.entity.abbreviation}.');
}
