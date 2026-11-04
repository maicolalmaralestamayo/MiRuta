<?php

namespace App\Support;

use App\JsonApi\JsonApiException;
use Illuminate\Support\Facades\DB;

/**
 * Compartimentación por Entidad (docs/08-version-2.md §8.2).
 *
 * Solo las tablas raíz (pertenencias, itinerarios, paradas y vehículos)
 * guardan la Entidad; las demás la heredan. Aquí se resuelve la Entidad de
 * cualquier registro y se comprueba que lo relacionado sea de la misma. Qué
 * puede ver o hacer cada uno lo decide App\Services\Permissions.
 */
final class Tenancy
{
    /**
     * Cómo llegar a la Entidad desde cada tabla: [tabla => SQL que devuelve entity_id para ?].
     */
    const PATHS = [
        'workers' => 'SELECT entity_id FROM workers WHERE id = ?',
        'itineraries' => 'SELECT entity_id FROM itineraries WHERE id = ?',
        'stops' => 'SELECT entity_id FROM stops WHERE id = ?',
        'vehicles' => 'SELECT entity_id FROM vehicles WHERE id = ?',
        'itinerary_stop' => 'SELECT i.entity_id FROM itinerary_stop s JOIN itineraries i ON i.id = s.itinerary_id WHERE s.id = ?',
        'trips' => 'SELECT i.entity_id FROM trips t JOIN itineraries i ON i.id = t.itinerary_id WHERE t.id = ?',
        'trip_legs' => 'SELECT i.entity_id FROM trip_legs l JOIN trips t ON t.id = l.trip_id JOIN itineraries i ON i.id = t.itinerary_id WHERE l.id = ?',
        'applications' => 'SELECT entity_id FROM applications WHERE id = ?',
        'absences' => 'SELECT w.entity_id FROM absences a JOIN workers w ON w.id = a.worker_id WHERE a.id = ?',
        'worker_roles' => 'SELECT w.entity_id FROM worker_roles r JOIN workers w ON w.id = r.worker_id WHERE r.id = ?',
    ];

    public static function entityOf(string $table, $id): ?int
    {
        if ($id === null || ! isset(self::PATHS[$table])) {
            return null;
        }

        $row = DB::selectOne(self::PATHS[$table], [(int) $id]);

        return $row && $row->entity_id !== null ? (int) $row->entity_id : null;
    }

    /**
     * El registro relacionado tiene que ser de la Entidad indicada.
     */
    public static function ensureSame(?int $entityId, string $table, $id, string $pointer): void
    {
        if ($id === null || $entityId === null) {
            return;
        }

        if (self::entityOf($table, $id) !== $entityId) {
            throw new JsonApiException(422, 'ENTITY_MISMATCH', 'De otra Entidad',
                'Lo indicado pertenece a otra Entidad.', ['pointer' => $pointer]);
        }
    }

}
