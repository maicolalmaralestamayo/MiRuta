import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/session.dart';
import '../navigation.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import '../widgets/entity_selector.dart';

/// «Otros datos del registro» (docs/11 §11.5, pantalla 2). Se abre justo
/// después de registrarse, ya con la sesión iniciada. Cada opción lleva a la
/// pantalla que la hace; «Hablar con el desarrollador» está aquí y en todas
/// las que se abren desde ella.
class OtherRegistrationDataScreen extends StatelessWidget {
  const OtherRegistrationDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final me = session.me!;
    final hasEntity = me.hasEntity;
    Widget option(IconData icon, String title, String subtitle, VoidCallback? onTap) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right),
            enabled: onTap != null,
            onTap: onTap,
          ),
        );

    return AppScaffold.list(title: 'Otros datos del registro', children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(
          me.isAdmin
              ? 'Ya es el Administrador de la aplicación. Si además trabaja en una Entidad, puede unirse a ella.'
              : 'Ya tiene su cuenta. Complete ahora estos datos, cuando quiera: también puede hacerlo después desde Inicio.',
        ),
      ),
      option(
        Icons.add_business_outlined,
        me.isAdmin ? 'Unirme a una Entidad' : 'Solicitar entrar en una Entidad',
        hasEntity ? 'Ya pertenece a ${me.memberships.map((m) => m.entity.abbreviation).join(' • ')}' : 'Escriba la abreviatura de su Entidad',
        () => me.isAdmin ? joinEntityAsAdmin(context) : requestEntityMembership(context),
      ),
      option(
        Icons.route,
        'Solicitar itinerario y parada',
        hasEntity ? 'Siempre juntos, en su Entidad' : 'Cuando le aprueben la entrada en una Entidad',
        hasEntity ? () => AppRoutes.itinerary(context) : null,
      ),
      option(Icons.child_care, 'Añadir hijos', 'Directamente, sin solicitud', () => AppRoutes.childForm(context)),
      option(
        Icons.badge_outlined,
        'Solicitar roles',
        hasEntity ? 'Chofer, Jefe de itinerario o Jefe de Transporte' : 'Cuando le aprueben la entrada en una Entidad',
        hasEntity ? () => AppRoutes.roles(context) : null,
      ),
      option(Icons.qr_code_2, 'Mi QR', 'Para que un jefe le dé de alta en un itinerario y su parada', () => AppRoutes.myQr(context)),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: FilledButton.icon(
          onPressed: () {
            context.session.finishRegistration();
            MainTabs.go(context, MainTab.home);
          },
          icon: const Icon(Icons.home),
          label: const Text('Ir a Inicio'),
        ),
      ),
      const SizedBox(height: 8),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: DeveloperChatButton()),
    ]);
  }
}
