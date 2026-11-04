# Widgets comunes (MiRuta 3.0)

Forma de todas las pantallas: docs/11 §11.3, §11.10 y §11.18 y las maquetas aprobadas.

| Archivo | Qué | Uso |
|---|---|---|
| `app_scaffold.dart` | `AppScaffold` / `AppScaffold.list` | Toda pantalla con sesión. Título, punto de conexión, barra «N seleccionados» (con `selection`), botón **Acciones** (con `actions`) y la barra principal Inicio/Viajes/Mensajes/Más. `tab:` marca la pestaña. |
| `actions.dart` | `ActionItem`, `ActionsOverlay`, `ActionsMenu`, `ActionsButton` | `ActionItem(icon:, label:, onPressed:, needs: ActionNeeds.none/one/some, destructive:, confirmation:)`; `ActionItem.divider()`. Sin selección válida sale en gris; `confirmation` pide confirmar; los errores se muestran solos. |
| `selection.dart` | `SelectionController`, `SelectableCardList`, `SelectableCard`, `CardSection` | Tocar = abrir (`onOpen`); mantener pulsado = selección múltiple. Pase el mismo controlador a `AppScaffold(selection:)`. Seleccionados: `controller.selectedOf(items, keyOf)`. |
| `cards.dart` | `InfoCard`, `CardImage`, `CardChip`, `SectionHeader`, `UserCard`, `ChildCard`, `EntityCard`, `ItineraryStopCard`, `RoleCard`, `roleIcon`, `applicationStatusColor` | Tarjetas modelo: sin botones dentro; `selected:` ✓, `dim:` atenuada; `onTap`/`onLongPress`. Solicitud pendiente: `chip: CardChip('Pendiente', color: applicationStatusColor('pending'))`. |
| `entity_selector.dart` | `EntitySelector`, `showMyEntitiesSheet`, `requestEntityMembership`, `joinEntityAsAdmin`, `leaveEntity`, `askEntityAbbreviation` | Tarjeta de la Entidad con ↕ → hoja «Mis Entidades». La elegida: `context.watch<Session>().selectedMembership`. |
| `connection_dot.dart` | `ConnectionDot` | Ya va en `AppScaffold`. |
| `pending_screen.dart` | `PendingScreen` | Stub de una pantalla aún no hecha. |
| `common.dart` | `AsyncView`, `BusyButton`, `confirm`, `runAction`, `showError`, `plural`… | Lo de antes. |

Ejemplo (pantalla Hijos):

```dart
final selection = SelectionController();
AppScaffold(
  title: 'Hijos',
  selection: selection,
  actions: [
    ActionItem(icon: Icons.person_add_alt_1, label: 'Crear hijo nuevo', onPressed: () => AppRoutes.childForm(context)),
    const ActionItem.divider(),
    ActionItem(icon: Icons.edit_outlined, label: 'Editar', needs: ActionNeeds.one, onPressed: _edit),
    ActionItem(icon: Icons.delete_outline, label: 'Eliminar', needs: ActionNeeds.some, destructive: true,
        confirmation: '¿Quitar los hijos seleccionados?', onPressed: _delete),
  ],
  body: SelectableCardList<Child>(
    controller: selection,
    sections: [CardSection(title: 'Con derecho a viajar', items: eligible), CardSection(title: 'Desactivados', items: inactive)],
    keyOf: (c) => c.id,
    onOpen: (c) => AppRoutes.childForm(context, c),
    cardBuilder: (context, c, selected, onTap, onLongPress) => ChildCard(c, selected: selected, onTap: onTap, onLongPress: onLongPress),
  ),
)
```
