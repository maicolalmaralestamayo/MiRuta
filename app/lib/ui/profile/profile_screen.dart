import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../applications/application_forms.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../../services/templates.dart';
import 'account_screens.dart';
import 'children_screen.dart';
import 'username_dialog.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<_ProfileData> _load(BuildContext context, Me me) async {
    final api = context.api;
    Itinerary? itinerary;
    Stop? stop;
    if (me.itineraryId != null) {
      itinerary = Itinerary.from((await api.get('/itineraries/${me.itineraryId}')).resource);
      stop = Stop.from((await api.get('/stops/${me.stopId}')).resource);
    }
    final chiefs = me.roles.isItineraryChief
        ? (await api.getAll('/itinerary-chiefs', query: {'filter[worker]': me.id, 'include': 'itinerary'}))
        : <Resource>[];
    final transportChief = me.roles.isTransportChief ? (await api.get('/transport-chiefs', query: {'filter[worker]': me.id})).resources.firstOrNull : null;
    return _ProfileData(itinerary, stop, chiefs, transportChief?.id);
  }

  Future<void> _photo(BuildContext context) async {
    final choice = await pickFrom<String>(context, 'Foto de perfil', ['camera', 'gallery', if (context.me.photoUrl != null) 'delete'],
        (c) => const {'camera': 'Hacer una foto', 'gallery': 'Elegir de la galería', 'delete': 'Quitar la foto'}[c]!);
    if (choice == null || !context.mounted) return;
    final session = context.session;
    if (choice == 'delete') {
      await runAction(context, () => session.api.delete('/me/photo'));
    } else {
      final file = await ImagePicker().pickImage(source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery, maxWidth: 800, imageQuality: 85);
      if (file == null || !context.mounted) return;
      await runAction(context, () => session.api.upload('/me/photo', 'photo', file.path), success: 'Foto actualizada');
    }
    await session.reloadMe();
  }

  Future<void> _editNames(BuildContext context) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const EditNamesScreen()));

  Future<void> _changePassword(BuildContext context) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen()));

  /// La jerarquía la cambia cada uno, sin solicitud (solo sirve para estadísticas).
  Future<void> _changeRank(BuildContext context) async {
    final ranks = (await context.api.getAll('/ranks', query: {'sort': 'sortOrder,name'})).map(Rank.from).toList();
    if (!context.mounted) return;
    final rank = await pickFrom<Rank>(context, 'Jerarquía', ranks, (r) => r.name);
    if (rank == null || !context.mounted) return;
    await runAction(context, () => context.api.patch('/me', resourceData('users', relationships: {'rank': ResourceId('ranks', rank.id)})), success: 'Jerarquía cambiada');
    if (context.mounted) await context.session.reloadMe();
  }

  Future<void> _leave(BuildContext context, String title, Future<void> Function() action) async {
    if (!await confirm(context, title, 'Se avisará a sus superiores. ¿Continuar?', accept: 'Darme de baja', destructive: true)) return;
    if (!context.mounted) return;
    await runAction(context, action, success: 'Baja registrada');
    if (context.mounted) await context.session.reloadMe();
  }

  Widget _leaveButton(BuildContext context, String title, Future<void> Function() action) => TextButton.icon(
        icon: const Icon(Icons.logout, color: overloadColor),
        label: const Text('Darme de baja'),
        onPressed: () => _leave(context, title, action),
      );

  /// Fila con el nombre del dato y su valor; si se puede editar, al tocarla se edita.
  Widget _row(IconData icon, String label, String value, {VoidCallback? onTap}) =>
      ListTile(leading: Icon(icon), title: Text(label), subtitle: Text(value), onTap: onTap);

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me!;
    final expires = me.account.passwordExpiresAt;
    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil')),
      body: AsyncView<_ProfileData>(
        key: ValueKey('${me.itineraryId}-${me.roles.chiefOfItineraries.length}-${me.roles.isDriver}-${me.roles.isTransportChief}'),
        load: () => _load(context, me),
        builder: (context, data, reload) => ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTap: () => _photo(context),
              child: Stack(children: [
                WorkerAvatar.of(photoUrl: me.photoUrl, name: me.name, radius: 48),
                const Positioned(right: 0, bottom: 0, child: CircleAvatar(radius: 14, child: Icon(Icons.camera_alt, size: 16))),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _editNames(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(me.fullName, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
              ),
            ),
          ),
          Center(child: RankBadge(me.rank)),
          const SectionTitle('Mis datos'),
          _row(Icons.person_outline, 'Nombre de usuario', me.username ?? '', onTap: () => editUsername(context)),
          if (me.hasWorker) ...[
            _row(Icons.apartment_outlined, 'Entidad', [me.entity?.abbreviation, me.entity?.name].whereType<String>().where((s) => s.isNotEmpty).join(' · ')),
            _row(Icons.badge_outlined, 'Pase', '${me.pass ?? ''}'),
          ],
          _row(Icons.password, 'Contraseña', expires == null ? '••••••••' : 'caduca el ${formatDate(expires.toLocal())}', onTap: () => _changePassword(context)),
          if (me.hasWorker) ...[
            BusyListTile(
              leading: const Icon(rankIcon),
              title: const Text('Jerarquía'),
              subtitle: Text(me.rank?.name ?? ''),
              onTap: () => _changeRank(context),
            ),
            _row(Icons.child_care, 'Hijos con derecho a viajar', plural(me.childrenCount, 'hijo', 'hijos'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChildrenScreen()))),
            const SectionTitle('Mi itinerario'),
            if (data.itinerary == null) ...[
              _row(Icons.route, 'Itinerario', 'Sin itinerario'),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton.icon(
                    icon: const Icon(Icons.send),
                    label: const Text('Solicitar itinerario y parada'),
                    onPressed: () => showApplicationForm(context, ApplicationType.itineraryMembership),
                  ),
                ),
              ),
            ] else ...[
              _row(Icons.route, 'Itinerario', data.itinerary!.name),
              _row(Icons.place_outlined, 'Parada', data.stop?.landmark ?? ''),
              _row(Icons.signpost_outlined, 'Dirección', data.stop?.address ?? ''),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton.icon(
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Solicitar cambio de itinerario'),
                    onPressed: () => showApplicationForm(context, ApplicationType.itineraryMembership),
                  ),
                ),
              ),
            ],
          ],
          const SectionTitle('Mis roles'),
          if (me.isAdmin) const ListTile(leading: Icon(Icons.admin_panel_settings), title: Text('Administrador')),
          if (data.transportChiefId != null)
            ListTile(
              leading: const Icon(Icons.directions_bus),
              title: const Text('Jefe de Transporte'),
              trailing: _leaveButton(context, 'Baja como Jefe de Transporte', () => context.api.delete('/transport-chiefs/${data.transportChiefId}')),
            ),
          for (final chief in data.chiefs)
            ListTile(
              leading: const Icon(Icons.groups),
              title: Text('Jefe de itinerario · ${chief.related('itinerary')?.string('name') ?? ''}'),
              trailing: _leaveButton(context, 'Baja como Jefe de itinerario', () => context.api.delete('/itinerary-chiefs/${chief.id}')),
            ),
          if (me.roles.isDriver)
            ListTile(
              leading: const Icon(Icons.airline_seat_recline_normal),
              title: const Text('Chofer'),
              trailing: _leaveButton(context, 'Baja como Chofer', () => context.api.delete('/drivers/${me.roles.driverId}')),
            ),
          if (!me.isAdmin && data.transportChiefId == null && data.chiefs.isEmpty && !me.roles.isDriver)
            const ListTile(title: Text('No tiene roles.')),
        ]),
      ),
    );
  }
}

class _ProfileData {
  final Itinerary? itinerary;
  final Stop? stop;
  final List<Resource> chiefs;
  final String? transportChiefId;

  _ProfileData(this.itinerary, this.stop, this.chiefs, this.transportChiefId);
}
