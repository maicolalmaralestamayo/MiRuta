<?php

namespace App\Support;

/**
 * Catálogo fijo de operaciones (docs/11 §11.16). Viene con la app: nadie lo
 * edita, solo se consulta (GET /operations). Cada rol marca algunas con un
 * ámbito de los posibles. Lo propio (perfil, hijos, ausencias, solicitudes,
 * ajustes, QR) no es una operación: lo puede siempre cada persona.
 */
final class Operations
{
    const SCOPE_OWN = 'own';
    const SCOPE_ITINERARY = 'itinerary';
    const SCOPE_ENTITY = 'entity';
    const SCOPE_ALL = 'all';

    const SCOPES = [self::SCOPE_OWN, self::SCOPE_ITINERARY, self::SCOPE_ENTITY, self::SCOPE_ALL];

    const SCOPE_NAMES = [
        self::SCOPE_OWN => 'Propio',
        self::SCOPE_ITINERARY => 'Su itinerario',
        self::SCOPE_ENTITY => 'Su Entidad',
        self::SCOPE_ALL => 'Todas',
    ];

    /**
     * [clave => [grupo, nombre, ámbitos posibles]]
     */
    const CATALOG = [
        'workers.view' => ['Trabajadores', 'Consultar trabajadores', ['itinerary', 'entity', 'all']],
        'workers.register' => ['Trabajadores', 'Registrar trabajadores (con o sin teléfono)', ['entity', 'all']],
        'workers.edit' => ['Trabajadores', 'Editar los datos de un trabajador', ['itinerary', 'entity', 'all']],
        'workers.deactivate' => ['Trabajadores', 'Desactivar y reactivar trabajadores', ['entity', 'all']],
        'workers.delete' => ['Trabajadores', 'Eliminar trabajadores', ['all']],
        'workers.view_identity_card' => ['Trabajadores', 'Ver el carné', ['itinerary', 'entity', 'all']],
        'workers.printed_qr' => ['Trabajadores', 'Ver, reimprimir y anular el QR impreso', ['itinerary', 'entity', 'all']],
        'children.view' => ['Hijos', 'Consultar hijos', ['own', 'itinerary', 'entity', 'all']],
        'children.manage' => ['Hijos', 'Añadir, editar y quitar hijos', ['own', 'all']],
        'entities.view' => ['Entidades', 'Consultar Entidades', ['entity', 'all']],
        'entities.manage' => ['Entidades', 'Crear, editar y eliminar Entidades', ['all']],
        'entities.approve_membership' => ['Entidades', 'Aprobar o rechazar la entrada en una Entidad', ['entity', 'all']],
        'entities.assign_members' => ['Entidades', 'Añadir o quitar a alguien de una Entidad directamente', ['entity', 'all']],
        'itineraries.view' => ['Itinerarios y paradas', 'Consultar itinerarios y paradas', ['itinerary', 'entity', 'all']],
        'itineraries.manage' => ['Itinerarios y paradas', 'Crear, editar y eliminar itinerarios', ['entity', 'all']],
        'stops.manage' => ['Itinerarios y paradas', 'Crear, editar y eliminar paradas', ['entity', 'all']],
        'itineraries.order_stops' => ['Itinerarios y paradas', 'Ordenar las paradas de un itinerario', ['itinerary', 'entity', 'all']],
        'itineraries.reference_route' => ['Itinerarios y paradas', 'Marcar el recorrido de referencia', ['itinerary', 'entity', 'all']],
        'members.approve' => ['Miembros del itinerario', 'Aprobar o rechazar solicitudes de itinerario y parada', ['itinerary', 'entity', 'all']],
        'members.assign' => ['Miembros del itinerario', 'Asignar o quitar itinerario y parada directamente', ['itinerary', 'entity', 'all']],
        'members.assign_by_qr' => ['Miembros del itinerario', 'Alta en un itinerario escaneando el QR', ['itinerary', 'entity', 'all']],
        'roles.view' => ['Roles', 'Consultar roles y la tabla de operaciones', ['all']],
        'roles.manage' => ['Roles', 'Crear, editar y eliminar roles', ['all']],
        'roles.set_default' => ['Roles', 'Elegir el rol por defecto', ['all']],
        'roles.assign' => ['Roles', 'Asignar o quitar roles directamente', ['entity', 'all']],
        'roles.approve' => ['Roles', 'Aprobar o rechazar solicitudes de rol', ['entity', 'all']],
        'vehicles.view' => ['Vehículos', 'Consultar vehículos', ['entity', 'all']],
        'vehicles.manage' => ['Vehículos', 'Crear, editar y eliminar vehículos', ['entity', 'all']],
        'vehicles.assign_driver' => ['Vehículos', 'Asignar el chofer habitual de un vehículo', ['entity', 'all']],
        'trips.view' => ['Viajes', 'Consultar viajes', ['own', 'itinerary', 'entity', 'all']],
        'trips.plan' => ['Viajes', 'Planificar viajes (crear y copiar a un rango de fechas)', ['itinerary', 'entity', 'all']],
        'trips.edit' => ['Viajes', 'Editar viajes (vehículo, chofer, horas)', ['itinerary', 'entity', 'all']],
        'trips.confirm_cancel' => ['Viajes', 'Confirmar y cancelar viajes', ['itinerary', 'entity', 'all']],
        'trips.delete' => ['Viajes', 'Eliminar viajes', ['entity', 'all']],
        'trips.complete' => ['Viajes', 'Marcar un viaje como realizado', ['itinerary', 'entity', 'all']],
        'tracking.drive' => ['Recorrido', 'Conducir: iniciar y terminar el recorrido y enviar la ubicación', ['entity', 'all']],
        'tracking.view_live' => ['Recorrido', 'Ver el recorrido en tiempo real', ['own', 'itinerary', 'entity', 'all']],
        'tracking.scan_boarding' => ['Recorrido', 'Escanear la subida', ['itinerary', 'entity', 'all']],
        'tracking.allow_outsiders' => ['Recorrido', 'Dejar subir a alguien de otro itinerario o Entidad', ['itinerary', 'entity', 'all']],
        'tracking.fix_passengers' => ['Recorrido', 'Corregir los pasajeros de un viaje', ['itinerary', 'entity', 'all']],
        'absences.view' => ['Ausencias', 'Consultar ausencias de otros', ['itinerary', 'entity', 'all']],
        'absences.manage' => ['Ausencias', 'Declarar, editar y quitar ausencias de otros', ['itinerary', 'entity', 'all']],
        'absence_types.manage' => ['Ausencias', 'Crear, editar y eliminar tipos de ausencia', ['all']],
        'settings.app' => ['Configuración', 'Ajustes de la app', ['all']],
        'settings.entity' => ['Configuración', 'Ajustes de la Entidad', ['entity', 'all']],
        'settings.itinerary' => ['Configuración', 'Ajustes por itinerario y parada', ['itinerary', 'entity', 'all']],
        'settings.worker' => ['Configuración', 'Ajustes de un trabajador', ['itinerary', 'entity', 'all']],
        'nomenclators.manage' => ['Nomencladores', 'Tipos de vehículo y motivos de conversación', ['all']],
        'chat.role_conversations' => ['Mensajes', 'Recibir y responder conversaciones dirigidas a un rol', ['itinerary', 'entity', 'all']],
        'chat.delete_messages' => ['Mensajes', 'Borrar mensajes de otros', ['itinerary', 'entity', 'all']],
        'statistics.view' => ['Estadísticas', 'Consultar estadísticas', ['itinerary', 'entity', 'all']],
        'access_recoveries.manage' => ['Olvidé algo', 'Consultar, aprobar, rechazar y bloquear teléfonos', ['all']],
        'app_versions.manage' => ['Actualizaciones de la app', 'Publicar y retirar versiones', ['all']],
        'maintenance.run' => ['Mantenimiento del servidor', 'Ver el estado y ejecutar órdenes', ['all']],
    ];

    public static function exists(string $operation): bool
    {
        return isset(self::CATALOG[$operation]);
    }

    /**
     * @return string[]
     */
    public static function keys(): array
    {
        return array_keys(self::CATALOG);
    }

    /**
     * @return string[]
     */
    public static function scopesOf(string $operation): array
    {
        return self::exists($operation) ? self::CATALOG[$operation][2] : [];
    }

    public static function allows(string $operation, string $scope): bool
    {
        return in_array($scope, self::scopesOf($operation), true);
    }

    /**
     * Para GET /operations.
     */
    public static function toArray(string $operation): array
    {
        list($group, $name, $scopes) = self::CATALOG[$operation];

        return ['key' => $operation, 'group' => $group, 'name' => $name, 'scopes' => $scopes];
    }
}
