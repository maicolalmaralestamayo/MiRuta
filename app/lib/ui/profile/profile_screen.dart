import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../applications/application_forms.dart';
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
    if (!await confirm(context, title, 'Se avisará a tus superiores. ¿Continuar?', accept: 'Darme de baja', destructive: true)) return;
    if (!context.mounted) return;
    await runAction(context, action, success: 'Baja registrada');
    if (context.mounted) await context.session.reloadMe();
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me!;
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
          Center(child: Text(me.fullName, style: Theme.of(context).textTheme.titleLarge)),
          Center(child: RankBadge(me.rank)),
          const SectionTitle('Mis datos'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(me.username ?? ''),
            subtitle: const Text('Usuario para entrar a la app'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => editUsername(context),
          ),
          if (me.hasWorker) ...[
            ListTile(
              leading: const Icon(Icons.apartment_outlined),
              title: Text(me.entity?.abbreviation ?? ''),
              subtitle: Text('Entidad${me.entity == null ? '' : ' · ${me.entity!.name}'}'),
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text('${me.pass ?? ''}'),
              subtitle: const Text('Pase (lo ven tú, tus jefes y el Administrador)'),
            ),
          ],
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Cambiar nombres y apellidos'), onTap: () => _editNames(context)),
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Cambiar contraseña'),
            subtitle: me.account.passwordExpiresAt == null ? null : Text('Caduca el ${formatDate(me.account.passwordExpiresAt!.toLocal())}'),
            onTap: () => _changePassword(context),
          ),
          if (me.hasWorker)
            BusyListTile(
              leading: const Icon(Icons.military_tech_outlined),
              title: Text(me.rank?.name ?? ''),
              subtitle: const Text('Jerarquía'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _changeRank(context),
            ),
          if (me.hasWorker)
          ListTile(
            leading: const Icon(Icons.child_care),
            title: Text('${me.childrenCount} hijo(s) con derecho a viajar'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChildrenScreen())),
          ),
          if (me.hasWorker) const SectionTitle('Mi itinerario'),
          if (!me.hasWorker)
            const SizedBox.shrink()
          else if (data.itinerary == null)
            ListTile(
              leading: const Icon(Icons.route),
              title: const Text('Sin itinerario'),
              trailing: TextButton(onPressed: () => showApplicationForm(context, ApplicationType.itineraryMembership), child: const Text('Solicitar')),
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.route),
              title: Text(data.itinerary!.name),
              subtitle: Text('Parada: ${data.stop?.landmark ?? ''}'),
              trailing: TextButton(onPressed: () => showApplicationForm(context, ApplicationType.itineraryMembership), child: const Text('Cambiar')),
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Darme de baja del itinerario'),
              onTap: () => _leave(context, 'Baja del itinerario', () => context.api.post('/applications', resourceData('applications', attributes: {'type': ApplicationType.itineraryLeave}))),
            ),
          ],
          const SectionTitle('Mis roles'),
          if (me.isAdmin) const ListTile(leading: Icon(Icons.admin_panel_settings), title: Text('Administrador (y desarrollador)'), subtitle: Text('Ve y hace todo, en todas las Entidades')),
          if (data.transportChiefId != null)
            ListTile(
              leading: const Icon(Icons.directions_bus),
              title: const Text('Jefe de Transporte'),
              trailing: TextButton(onPressed: () => _leave(context, 'Baja como Jefe de Transporte', () => context.api.delete('/transport-chiefs/${data.transportChiefId}')), child: const Text('Darme de baja')),
            ),
          for (final chief in data.chiefs)
            ListTile(
              leading: const Icon(Icons.groups),
              title: Text('Jefe de ${chief.related('itinerary')?.string('name') ?? 'itinerario'}'),
              trailing: TextButton(onPressed: () => _leave(context, 'Baja como Jefe de itinerario', () => context.api.delete('/itinerary-chiefs/${chief.id}')), child: const Text('Darme de baja')),
            ),
          if (me.roles.isDriver)
            ListTile(
              leading: const Icon(Icons.airline_seat_recline_normal),
              title: const Text('Chofer'),
              trailing: TextButton(onPressed: () => _leave(context, 'Baja como chofer', () => context.api.delete('/drivers/${me.roles.driverId}')), child: const Text('Darme de baja')),
            ),
          if (!me.isAdmin && data.transportChiefId == null && data.chiefs.isEmpty && !me.roles.isDriver)
            const ListTile(title: Text('No tienes roles. Puedes solicitarlos en Solicitudes.')),
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
