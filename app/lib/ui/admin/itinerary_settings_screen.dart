import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../navigation.dart';
import '../settings/scoped_settings_screen.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/selection.dart';
import 'itineraries_screen.dart';
import 'management.dart';

/// Ajustes por itinerario y parada (Gestión, docs/11 §11.17): los
/// itinerarios de la Entidad elegida en los que tiene settings.itinerary.
/// Tocar uno abre sus ajustes y los de cada una de sus paradas.
class ItinerarySettingsScreen extends StatefulWidget {
  const ItinerarySettingsScreen({super.key});

  @override
  State<ItinerarySettingsScreen> createState() => _ItinerarySettingsScreenState();
}

class _ItinerarySettingsScreenState extends State<ItinerarySettingsScreen> with ManagementEntityState {
  final _view = GlobalKey<AsyncViewState<List<Itinerary>>>();
  final _selection = SelectionController();

  @override
  String get entityOperation => Op.settingsItinerary;

  @override
  void initState() {
    super.initState();
    initEntity();
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  void onEntityChanged() => _view.currentState?.reload();

  Future<List<Itinerary>> _load() async {
    final me = context.me;
    final e = entity!;
    return (await context.api.getAll('/itineraries', query: {'sort': 'name', 'filter[entity]': e.id}))
        .map(Itinerary.from)
        .where((i) => me.can(Op.settingsItinerary, entityId: e.id, itineraryId: i.id))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Ajustes por itinerario',
      tab: MainTab.more,
      body: entityPlaceholder() ??
          AsyncView<List<Itinerary>>(
            key: _view,
            load: _load,
            builder: (context, items, reload) => SelectableCardList<Itinerary>(
              controller: _selection,
              header: [entitySelector()],
              sections: [CardSection(title: 'Itinerarios', items: items)],
              emptyText: 'No hay itinerarios cuyos ajustes pueda cambiar.',
              keyOf: (i) => i.id,
              canSelect: (_) => false,
              onOpen: (i) => Navigator.push(context, MaterialPageRoute(builder: (_) => ItineraryLevelsScreen(itinerary: i))),
              cardBuilder: (context, i, selected, onTap, onLongPress) => ItineraryCard(i, onTap: onTap),
            ),
          ),
    );
  }
}

/// Niveles de ajustes de un itinerario: el propio itinerario y cada parada.
class ItineraryLevelsScreen extends StatelessWidget {
  final Itinerary itinerary;

  const ItineraryLevelsScreen({super.key, required this.itinerary});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: itinerary.name,
      tab: MainTab.more,
      body: AsyncView<List<ItineraryStop>>(
        load: () async => (await context.api.getAll('/itinerary-stops', query: {'filter[itinerary]': itinerary.id, 'include': 'stop', 'sort': 'position'}))
            .map(ItineraryStop.from)
            .toList(),
        builder: (context, links, reload) => ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          const SectionHeader('Itinerario'),
          ItineraryCard(
            itinerary,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ScopedSettingsScreen.itinerary(itineraryId: itinerary.id, name: itinerary.name))),
          ),
          const SectionHeader('Paradas'),
          if (links.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('El itinerario no tiene paradas.')),
          for (final link in links)
            InfoCard(
              images: [CardImage(url: link.stop?.imageUrl, icon: Icons.place)],
              title: link.stop?.landmark ?? '',
              lines: [link.stop?.street ?? '', 'Parada ${link.position}'],
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ScopedSettingsScreen.stop(itineraryStopId: link.id, name: link.stop?.landmark ?? ''))),
            ),
        ]),
      ),
    );
  }
}
