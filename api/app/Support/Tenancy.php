<?php

namespace App\Support;

use App\JsonApi\JsonApiException;
use App\Models\User;
use Illuminate\Support\Facades\DB;

/**
 * Compartimentación por Entidad (docs/08-version-2.md §8.2).
 *
 * Solo las tablas raíz (trabajadores, itinerarios, paradas y vehículos)
 * guardan la Entidad; las demás la heredan. Aquí se resuelve la Entidad de
 * cualquier registro y se comprueba que lo relacionado sea de la misma.
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
        'drivers' => 'SELECT w.entity_id FROM drivers d JOIN workers w ON w.id = d.worker_id WHERE d.id = ?',
        'transport_chiefs' => 'SELECT w.entity_id FROM transport_chiefs t JOIN workers w ON w.id = t.worker_id WHERE t.id = ?',
        'itinerary_chiefs' => 'SELECT i.entity_id FROM itinerary_chiefs c JOIN itineraries i ON i.id = c.itinerary_id WHERE c.id = ?',
        'itinerary_stop' => 'SELECT i.entity_id FROM itinerary_stop s JOIN itineraries i ON i.id = s.itinerary_id WHERE s.id = ?',
        'trips' => 'SELECT i.entity_id FROM trips t JOIN itineraries i ON i.id = t.itinerary_id WHERE t.id = ?',
        'trip_legs' => 'SELECT i.entity_id FROM trip_legs l JOIN trips t ON t.id = l.trip_id JOIN itineraries i ON i.id = t.itinerary_id WHERE l.id = ?',
        'children' => 'SELECT w.entity_id FROM children c JOIN workers w ON w.id = c.worker_id WHERE c.id = ?',
        'applications' => 'SELECT w.entity_id FROM applications a JOIN workers w ON w.id = a.worker_id WHERE a.id = ?',
        'users' => 'SELECT entity_id FROM workers WHERE user_id = ? ORDER BY deleted_at IS NULL DESC LIMIT 1',
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

    /**
     * La cuenta puede ver el registro; si no, 404 como si no existiera.
     */
    public static function ensureVisible(User $user, string $table, $id): void
    {
        if (! $user->canAccessEntity(self::entityOf($table, $id))) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'El recurso no existe.');
        }
    }
}
