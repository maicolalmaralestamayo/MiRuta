<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Application;
use App\Models\User;
use App\Models\Worker;

/**
 * Tres roles fijos con sus permisos en el código (docs/11 §11.30):
 *
 * - Administrador (users.is_admin): todo, en todas las Entidades.
 * - Jefe de itinerario (workers.is_chief): gestiona su itinerario (paradas,
 *   personas, solicitudes e Incluir por QR) y ve sus Entidades. Cada persona es
 *   Jefe de un solo itinerario, y viaja en él.
 * - Trabajador: consulta sus Entidades; solicita, sale y gestiona lo suyo.
 *
 * Lo leído se guarda durante la petición; flush() tras cambiar pertenencias.
 */
class Access
{
    /** @var array<int, \Illuminate\Support\Collection> [id de persona => pertenencias] */
    private array $workers = [];

    public function isAdmin(?User $user): bool
    {
        return $user !== null && $user->isAdmin();
    }

    /**
     * Sus pertenencias (una por Entidad).
     *
     * @return \Illuminate\Support\Collection<int, Worker>
     */
    public function workersOf(User $user)
    {
        return $this->workers[$user->id] ??= Worker::where('user_id', $user->id)->orderBy('id')->get();
    }

    /** @return int[] Entidades a las que pertenece */
    public function entityIds(User $user): array
    {
        return $this->workersOf($user)->pluck('entity_id')->map(fn ($id) => (int) $id)->all();
    }

    /** @return int[] Itinerarios en los que está */
    public function itineraryIds(User $user): array
    {
        return $this->workersOf($user)->pluck('itinerary_id')->filter()->map(fn ($id) => (int) $id)->values()->all();
    }

    public function workerIn(User $user, $entityId): ?Worker
    {
        return $this->workersOf($user)->firstWhere('entity_id', (int) $entityId);
    }

    /**
     * La pertenencia en la que es Jefe (con su itinerario), o null.
     */
    public function chiefWorker(User $user): ?Worker
    {
        return $this->workersOf($user)->first(fn (Worker $w) => $w->is_chief && $w->itinerary_id);
    }

    public function chiefItineraryId(User $user): ?int
    {
        $worker = $this->chiefWorker($user);

        return $worker ? (int) $worker->itinerary_id : null;
    }

    public function isChief(User $user): bool
    {
        return $this->chiefItineraryId($user) !== null;
    }

    public function isChiefOf(User $user, $itineraryId): bool
    {
        return $itineraryId !== null && $this->chiefItineraryId($user) === (int) $itineraryId;
    }

    /**
     * Administrador o Jefe de ese itinerario.
     */
    public function canManageItinerary(User $user, $itineraryId): bool
    {
        return $this->isAdmin($user) || $this->isChiefOf($user, $itineraryId);
    }

    /**
     * Entidades cuyos datos ve: null = todas (Administrador).
     *
     * @return int[]|null
     */
    public function visibleEntityIds(User $user): ?array
    {
        return $this->isAdmin($user) ? null : $this->entityIds($user);
    }

    public function canSeeEntity(User $user, $entityId): bool
    {
        return $this->isAdmin($user) || in_array((int) $entityId, $this->entityIds($user), true);
    }

    /**
     * Ve lo desactivado (atenuado): el Administrador, y el Jefe en su ámbito.
     */
    public function seesInactive(User $user): bool
    {
        return $this->isAdmin($user) || $this->isChief($user);
    }

    /**
     * Ve el carné de esa persona: ella misma, el Administrador y el Jefe de
     * itinerario (miembros de su itinerario y quienes solicitan entrar en él).
     */
    public function canSeeIdentityCard(?User $viewer, User $person): bool
    {
        if (! $viewer) {
            return false;
        }

        if ($this->isAdmin($viewer) || (int) $viewer->id === (int) $person->id) {
            return true;
        }

        $itineraryId = $this->chiefItineraryId($viewer);

        if ($itineraryId === null) {
            return false;
        }

        return Worker::where('user_id', $person->id)->where('itinerary_id', $itineraryId)->exists()
            || Application::where('user_id', $person->id)->where('itinerary_id', $itineraryId)->exists();
    }

    public function requireAdmin(User $user, string $detail = 'Solo el Administrador puede hacerlo.'): void
    {
        if (! $this->isAdmin($user)) {
            throw self::forbidden($detail);
        }
    }

    public function requireItineraryManager(User $user, $itineraryId, string $detail = 'Solo el Administrador o el Jefe de ese itinerario pueden hacerlo.'): void
    {
        if (! $this->canManageItinerary($user, $itineraryId)) {
            throw self::forbidden($detail);
        }
    }

    public static function forbidden(string $detail = 'No tiene permiso para realizar esta acción.'): JsonApiException
    {
        return new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', $detail);
    }

    /**
     * Rol principal, para la app: administrador, jefe o trabajador.
     */
    public function roleOf(User $user): string
    {
        return $this->isAdmin($user) ? 'administrador' : ($this->isChief($user) ? 'jefe' : 'trabajador');
    }

    public function flush(?int $userId = null): void
    {
        if ($userId === null) {
            $this->workers = [];
        } else {
            unset($this->workers[$userId]);
        }
    }
}
