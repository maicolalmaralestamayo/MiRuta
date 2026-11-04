import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api/memberships_api.dart';
import '../../services/session.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/entity_selector.dart';
import '../widgets/selection.dart';
import 'worker_common.dart';

/// Entidades (docs/11 §11.6 y §11.18; maqueta pantallas-final.png, 4). Sin
/// selector de Entidad: «Mis Entidades» y «Solicitudes pendientes».
///
/// Acciones: Solicitar entrar en una Entidad (se escribe la abreviatura, se
/// comprueba y se muestra su nombre; el Administrador entra sin solicitud),
/// Darme de baja y Cancelar solicitud (una o varias).
class MyEntitiesScreen extends StatefulWidget {
  const MyEntitiesScreen({super.key});

  @override
  State<MyEntitiesScreen> createState() => _MyEntitiesScreenState();
}

class _MyEntitiesScreenState extends State<MyEntitiesScreen> {
  static const _entity = 'entity:';
  static const _application = 'application:';

  final _selection = SelectionController();
  final _view = GlobalKey<AsyncViewState<List<Application>>>();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  Future<List<Application>> _load() => MembershipsApi(context.api).myApplications(type: ApplicationType.entityMembership);

  Future<void> _reload() async {
    _selection.clear();
    await _view.currentState?.reload();
  }

  Future<void> _request() async {
    final me = context.me;
    final done = me.isAdmin ? await joinEntityAsAdmin(context) : await requestEntityMembership(context);
    if (done && mounted) await _reload();
  }

  Future<void> _leave() async {
    final session = context.session;
    for (final entityId in SelectionKeys.ids(_selection, _entity)) {
      await session.leaveEntity(entityId);
    }
    if (!mounted) return;
    showMessage(context, 'Se dio de baja.');
    await _reload();
  }

  Future<void> _cancel() async {
    final api = MembershipsApi(context.api);
    for (final id in SelectionKeys.ids(_selection, _application)) {
      await api.cancelApplication(id);
    }
    if (!mounted) return;
    showMessage(context, 'Solicitud cancelada');
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me!;
    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) => AppScaffold(
        title: 'Entidades',
        selection: _selection,
        actions: [
          ActionItem(icon: Icons.add_business_outlined, label: me.isAdmin ? 'Unirme a una Entidad' : 'Solicitar entrar en una Entidad', onPressed: _request),
          const ActionItem.divider(),
          ActionItem(
            icon: Icons.logout,
            label: 'Darme de baja',
            needs: ActionNeeds.some,
            enabled: SelectionKeys.allAre(_selection, _entity),
            confirmation: 'Perderá su itinerario, su parada y sus roles en las Entidades seleccionadas. Para volver tendrá que solicitarlo de nuevo. ¿Darse de baja?',
            onPressed: _leave,
          ),
          ActionItem(
            icon: Icons.cancel_outlined,
            label: 'Cancelar solicitud',
            needs: ActionNeeds.some,
            enabled: SelectionKeys.allAre(_selection, _application),
            confirmation: '¿Cancelar las solicitudes seleccionadas?',
            onPressed: _cancel,
          ),
        ],
        body: AsyncView<List<Application>>(
          key: _view,
          load: _load,
          builder: (context, applications, reload) {
            String keyOf(Object item) => item is Membership ? '$_entity${item.entityId}' : '$_application${(item as Application).id}';
            return ListView(padding: const EdgeInsets.only(top: 4, bottom: 96), physics: const AlwaysScrollableScrollPhysics(), children: [
              SelectableCardList<Object>(
                controller: _selection,
                scrollable: false,
                sections: [
                  CardSection(title: 'Mis Entidades', items: me.memberships, hideIfEmpty: false, emptyText: 'Todavía no pertenece a ninguna Entidad.'),
                  CardSection(title: 'Solicitudes pendientes', items: applications),
                ],
                keyOf: keyOf,
                cardBuilder: (context, item, selected, onTap, onLongPress) => item is Membership
                    ? EntityCard(item.entity, selected: selected, onTap: onTap, onLongPress: onLongPress)
                    : _ApplicationCard(item as Application, selected: selected, onTap: onTap, onLongPress: onLongPress),
              ),
              const DeveloperChatFooter(),
            ]);
          },
        ),
      ),
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  final Application application;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _ApplicationCard(this.application, {this.selected = false, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) => InfoCard(
        images: const [CardImage(icon: Icons.apartment)],
        title: application.entityAbbreviation ?? '',
        chip: pendingChip(),
        lines: [requestedOn(application)],
        selected: selected,
        onTap: onTap,
        onLongPress: onLongPress,
      );
}
