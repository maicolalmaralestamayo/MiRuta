import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../applications/application_forms.dart';
import '../widgets/common.dart';
import 'children_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<_ProfileData> _load(BuildContext context, Worker me) async {
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

  Future<void> _editName(BuildContext context, Worker me) async {
    final first = await promptText(context, 'Nombre', initial: me.firstName, required: true);
    if (first == null || !context.mounted) return;
    final last = await promptText(context, 'Apellidos', initial: me.lastName, required: true);
    if (last == null || !context.mounted) return;
    await runAction(context, () => context.api.patch('/me', resourceData('workers', attributes: {'firstName': first, 'lastName': last})));
    if (context.mounted) await context.session.reloadMe();
  }

  Future<void> _changePassword(BuildContext context) async {
    final current = await promptText(context, 'Contraseña actual', required: true);
    if (current == null || !context.mounted) return;
    final next = await promptText(context, 'Contraseña nueva (mínimo 8 caracteres)', required: true);
    if (next == null || !context.mounted) return;
    final body = resourceData('workers', attributes: {'password': next})..['meta'] = {'currentPassword': current};
    final ok = await runAction(context, () => context.api.patch('/me', body), success: 'Contraseña cambiada. Se cerró la sesión en los demás dispositivos.');
    if (ok && context.mounted) {
      // El servidor revocó todas las sesiones: se vuelve a entrar con la nueva contraseña.
      final card = context.me.cardNumber;
      if (card != null) await context.session.login(card, next);
    }
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
                WorkerAvatar(me, radius: 48),
                const Positioned(right: 0, bottom: 0, child: CircleAvatar(radius: 14, child: Icon(Icons.camera_alt, size: 16))),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Center(child: Text(me.fullName, style: Theme.of(context).textTheme.titleLarge)),
          Center(child: RankBadge(me.rank)),
          const SectionTitle('Mis datos'),
          ListTile(leading: const Icon(Icons.badge_outlined), title: Text(me.cardNumber ?? ''), subtitle: const Text('Carné (solo lo ves tú y el Administrador)')),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Cambiar nombre y apellidos'), onTap: () => _editName(context, me)),
          ListTile(leading: const Icon(Icons.password), title: const Text('Cambiar contraseña'), onTap: () => _changePassword(context)),
          ListTile(
            leading: const Icon(Icons.military_tech_outlined),
            title: Text(me.rank?.name ?? ''),
            subtitle: const Text('Jerarquía'),
            trailing: TextButton(onPressed: () => showApplicationForm(context, ApplicationType.rankChange), child: const Text('Solicitar cambio')),
          ),
          ListTile(
            leading: const Icon(Icons.child_care),
            title: Text('${me.childrenCount} hijo(s) con derecho a viajar'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChildrenScreen())),
          ),
          const SectionTitle('Mi itinerario'),
          if (data.itinerary == null)
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
          if (me.isAdmin) const ListTile(leading: Icon(Icons.admin_panel_settings), title: Text('Administrador (y desarrollador)')),
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
