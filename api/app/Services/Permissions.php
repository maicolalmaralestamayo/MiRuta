<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Itinerary;
use App\Models\User;
use App\Support\Operations;
use Illuminate\Support\Facades\DB;

/**
 * Permisos por roles configurables (docs/11 §11.16).
 *
 * Cada persona tiene, en cada Entidad a la que pertenece, unos roles; cada
 * rol da operaciones con un ámbito:
 *
 * - all: en toda la app;
 * - entity: en la Entidad donde tiene el rol;
 * - itinerary: en el itinerario del rol (si es por itinerario, p. ej. Jefe
 *   de itinerario) o, si no, en el itinerario del que es miembro en esa Entidad;
 * - own: solo lo suyo (sus viajes, sus hijos…), en esa Entidad.
 *
 * El Administrador (users.is_admin) tiene todas las operaciones con «all».
 */
class Permissions
{
    /** @var array [id de persona => lista de permisos] */
    private $cache = [];

    /** @var array [id de itinerario => id de Entidad] */
    private $itineraryEntities = [];

    public function flush(?int $userId = null): void
    {
        if ($userId === null) {
            $this->cache = [];
        } else {
            unset($this->cache[$userId]);
        }
    }

    /**
     * Permisos de la persona: [operation, scope, entityId, itineraryId, roleId, workerId].
     *
     * @return array[]
     */
    public function grants(User $user): array
    {
        if ($user->isAdmin()) {
            return array_map(function ($operation) {
                return ['operation' => $operation, 'scope' => Operations::SCOPE_ALL, 'entityId' => null, 'itineraryId' => null, 'roleId' => null, 'workerId' => null];
            }, Operations::keys());
        }

        if (! isset($this->cache[$user->id])) {
            $grants = [];

            foreach ($this->baseQuery()->where('w.user_id', $user->id)->get() as $row) {
                $grant = $this->grantFromRow($row);

                if ($grant !== null) {
                    $grants[] = $grant;
                }
            }

            $this->cache[$user->id] = $grants;
        }

        return $this->cache[$user->id];
    }

    /**
     * Lista para GET /me, sin repetidos: [{operation, scope, entityId, itineraryId}].
     */
    public function forUser(User $user): array
    {
        $list = [];

        foreach ($this->grants($user) as $grant) {
            $item = [
                'operation' => $grant['operation'],
                'scope' => $grant['scope'],
                'entityId' => $grant['entityId'] === null ? null : (string) $grant['entityId'],
                'itineraryId' => $grant['itineraryId'] === null ? null : (string) $grant['itineraryId'],
            ];
            $list[implode('|', $item)] = $item;
        }

        return array_values($list);
    }

    /**
     * Puede hacer la operación sobre esa Entidad (o ese itinerario). Sin
     * Entidad ni itinerario solo vale el ámbito «all». El ámbito «own» no
     * cuenta aquí (ver canOwn).
     */
    public function can(User $user, string $operation, $entityId = null, $itineraryId = null): bool
    {
        $this->ensureOperation($operation);

        if ($user->isAdmin()) {
            return true;
        }

        $itineraryId = $itineraryId === null ? null : (int) $itineraryId;
        $entityId = $entityId === null ? ($itineraryId !== null ? $this->entityOfItinerary($itineraryId) : null) : (int) $entityId;

        foreach ($this->grants($user) as $grant) {
            if ($grant['operation'] !== $operation) {
                continue;
            }

            switch ($grant['scope']) {
                case Operations::SCOPE_ALL:
                    return true;
                case Operations::SCOPE_ENTITY:
                    if ($entityId !== null && $grant['entityId'] === $entityId) {
                        return true;
                    }
                    break;
                case Operations::SCOPE_ITINERARY:
                    if ($itineraryId !== null && $grant['itineraryId'] === $itineraryId) {
                        return true;
                    }
                    break;
            }
        }

        return false;
    }

    /**
     * Tiene la operación en esa Entidad con cualquier ámbito (también «own»):
     * para lo suyo dentro de la Entidad.
     */
    public function canOwn(User $user, string $operation, $entityId): bool
    {
        if ($user->isAdmin()) {
            return true;
        }

        foreach ($this->grants($user) as $grant) {
            if ($grant['operation'] === $operation
                && ($grant['scope'] === Operations::SCOPE_ALL || $grant['entityId'] === (int) $entityId)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Tiene la operación con algún ámbito (para mostrar u ocultar funciones).
     */
    public function canAnywhere(User $user, string $operation, bool $includeOwn = false): bool
    {
        if ($user->isAdmin()) {
            return true;
        }

        foreach ($this->grants($user) as $grant) {
            if ($grant['operation'] === $operation && ($includeOwn || $grant['scope'] !== Operations::SCOPE_OWN)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Tiene la operación con algún ámbito que toque esa Entidad (la Entidad
     * entera o alguno de sus itinerarios).
     */
    public function canInEntity(User $user, string $operation, $entityId): bool
    {
        if ($user->isAdmin()) {
            return true;
        }

        foreach ($this->grants($user) as $grant) {
            if ($grant['operation'] === $operation && $grant['scope'] !== Operations::SCOPE_OWN
                && ($grant['scope'] === Operations::SCOPE_ALL || $grant['entityId'] === (int) $entityId)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Dónde puede hacer la operación:
     * ['all' => bool, 'entities' => int[], 'itineraries' => int[], 'own' => int[] (Entidades con «own»)].
     */
    public function scope(User $user, string $operation): array
    {
        $this->ensureOperation($operation);
        $scope = ['all' => $user->isAdmin(), 'entities' => [], 'itineraries' => [], 'own' => []];

        if ($scope['all']) {
            return $scope;
        }

        foreach ($this->grants($user) as $grant) {
            if ($grant['operation'] !== $operation) {
                continue;
            }

            switch ($grant['scope']) {
                case Operations::SCOPE_ALL:
                    $scope['all'] = true;
                    break;
                case Operations::SCOPE_ENTITY:
                    $scope['entities'][] = $grant['entityId'];
                    break;
                case Operations::SCOPE_ITINERARY:
                    $scope['itineraries'][] = $grant['itineraryId'];
                    break;
                case Operations::SCOPE_OWN:
                    $scope['own'][] = $grant['entityId'];
                    break;
            }
        }

        foreach (['entities', 'itineraries', 'own'] as $key) {
            $scope[$key] = array_values(array_unique($scope[$key]));
        }

        return $scope;
    }

    /**
     * Limita una consulta a lo que la persona puede ver o hacer con la
     * operación. Devuelve false si no puede nada (la consulta queda vacía).
     *
     * @param \Illuminate\Database\Eloquent\Builder|\Illuminate\Database\Query\Builder $query
     * @param callable|null $own añade a la consulta (con orWhere) lo suyo
     */
    public function restrict($query, User $user, string $operation, string $entityColumn, ?string $itineraryColumn = null, ?callable $own = null): bool
    {
        $scope = $this->scope($user, $operation);

        if ($scope['all']) {
            return true;
        }

        $query->where(function ($query) use ($scope, $entityColumn, $itineraryColumn, $own) {
            $query->whereRaw('1 = 0');

            if ($scope['entities']) {
                $query->orWhereIn($entityColumn, $scope['entities']);
            }

            if ($scope['itineraries'] && $itineraryColumn !== null) {
                $query->orWhereIn($itineraryColumn, $scope['itineraries']);
            }

            if ($own) {
                $own($query, $scope);
            }
        });

        return $scope['entities'] || $scope['itineraries'] || $own;
    }

    /**
     * Comprueba el permiso o lanza 403.
     */
    public function authorize(User $user, string $operation, $entityId = null, $itineraryId = null, ?string $detail = null): void
    {
        if (! $this->can($user, $operation, $entityId, $itineraryId)) {
            throw self::forbidden($detail);
        }
    }

    public static function forbidden(?string $detail = null): JsonApiException
    {
        return new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', $detail ?: 'No tiene permiso para hacer esto.');
    }

    /**
     * Personas que pueden hacer la operación sobre esa Entidad o itinerario
     * (con el Administrador), p. ej. para avisar a quien resuelve.
     *
     * @return int[]
     */
    public function userIdsWith(string $operation, $entityId = null, $itineraryId = null, bool $includeAdmins = true): array
    {
        $itineraryId = $itineraryId === null ? null : (int) $itineraryId;
        $entityId = $entityId === null ? ($itineraryId !== null ? $this->entityOfItinerary($itineraryId) : null) : (int) $entityId;
        $ids = $includeAdmins ? array_map('intval', User::where('is_admin', true)->pluck('id')->all()) : [];

        $rows = $this->baseQuery()->where('rp.operation', $operation)->where(function ($query) use ($entityId, $itineraryId) {
            $query->where('rp.scope', Operations::SCOPE_ALL);

            if ($entityId !== null) {
                $query->orWhere(function ($query) use ($entityId) {
                    $query->where('rp.scope', Operations::SCOPE_ENTITY)->where('w.entity_id', $entityId);
                });
            }

            if ($itineraryId !== null) {
                $query->orWhere(function ($query) use ($itineraryId) {
                    $query->where('rp.scope', Operations::SCOPE_ITINERARY)->where(function ($query) use ($itineraryId) {
                        $query->where(function ($query) use ($itineraryId) {
                            $query->where('r.itinerary_scoped', true)->where('wr.itinerary_id', $itineraryId);
                        })->orWhere(function ($query) use ($itineraryId) {
                            $query->where('r.itinerary_scoped', false)->where('w.itinerary_id', $itineraryId);
                        });
                    });
                });
            }
        })->pluck('w.user_id')->all();

        return array_values(array_unique(array_merge($ids, array_map('intval', $rows))));
    }

    /**
     * Roles que tiene la persona: en esa Entidad o, sin ella, en cualquiera.
     *
     * @return int[]
     */
    public function heldRoleIds(User $user, $entityId = null): array
    {
        $query = DB::table('worker_roles AS wr')
            ->join('workers AS w', 'w.id', '=', 'wr.worker_id')
            ->join('roles AS r', 'r.id', '=', 'wr.role_id')
            ->whereNull('wr.deleted_at')->whereNull('w.deleted_at')->whereNull('r.deleted_at')
            ->where('w.user_id', $user->id);

        if ($entityId !== null) {
            $query->where('w.entity_id', (int) $entityId);
        }

        return array_values(array_unique(array_map('intval', $query->pluck('wr.role_id')->all())));
    }

    public function entityOfItinerary(int $itineraryId): ?int
    {
        if (! array_key_exists($itineraryId, $this->itineraryEntities)) {
            $entityId = Itinerary::withTrashed()->whereKey($itineraryId)->value('entity_id');
            $this->itineraryEntities[$itineraryId] = $entityId === null ? null : (int) $entityId;
        }

        return $this->itineraryEntities[$itineraryId];
    }

    private function baseQuery()
    {
        return DB::table('worker_roles AS wr')
            ->join('workers AS w', 'w.id', '=', 'wr.worker_id')
            ->join('entities AS e', 'e.id', '=', 'w.entity_id')
            ->join('roles AS r', 'r.id', '=', 'wr.role_id')
            ->join('role_permissions AS rp', 'rp.role_id', '=', 'r.id')
            ->whereNull('wr.deleted_at')->whereNull('w.deleted_at')->whereNull('e.deleted_at')
            ->whereNull('r.deleted_at')->whereNull('rp.deleted_at')
            ->select('rp.operation', 'rp.scope', 'w.entity_id', 'w.itinerary_id AS member_itinerary_id',
                'wr.itinerary_id AS role_itinerary_id', 'r.itinerary_scoped', 'r.id AS role_id', 'w.id AS worker_id', 'w.user_id');
    }

    private function grantFromRow($row): ?array
    {
        $itineraryId = null;

        if ($row->scope === Operations::SCOPE_ITINERARY) {
            $itineraryId = $row->itinerary_scoped ? $row->role_itinerary_id : $row->member_itinerary_id;

            if ($itineraryId === null) {
                return null;
            }
        }

        return [
            'operation' => $row->operation,
            'scope' => $row->scope,
            'entityId' => $row->scope === Operations::SCOPE_ALL ? null : (int) $row->entity_id,
            'itineraryId' => $itineraryId === null ? null : (int) $itineraryId,
            'roleId' => (int) $row->role_id,
            'workerId' => (int) $row->worker_id,
        ];
    }

    private function ensureOperation(string $operation): void
    {
        if (! Operations::exists($operation)) {
            throw new \InvalidArgumentException("Operación desconocida: {$operation}");
        }
    }
}
