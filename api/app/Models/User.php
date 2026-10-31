<?php

namespace App\Models;

use App\Support\Username;
use Illuminate\Auth\Authenticatable;
use Illuminate\Contracts\Auth\Access\Authorizable as AuthorizableContract;
use Illuminate\Contracts\Auth\Authenticatable as AuthenticatableContract;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Laravel\Lumen\Auth\Authorizable;

/**
 * Cuenta de la app (docs/08-version-2.md §8.3). Inactiva = borrado lógico.
 *
 * - El Administrador es una cuenta sin trabajador: ve y hace todo, en todas
 *   las Entidades, y cuenta como Jefe de Transporte y Jefe de todos los itinerarios.
 * - Los demás tienen un trabajador (`worker`) en una Entidad. Mientras no lo
 *   tengan solo pueden unirse a una Entidad.
 * - Una cuenta creada por un superior no tiene usuario ni contraseña hasta
 *   que el trabajador la activa con su código.
 */
class User extends Model implements AuthenticatableContract, AuthorizableContract
{
    use Authenticatable, Authorizable, SoftDeletes;

    protected $fillable = [
        'username', 'password', 'password_changed_at', 'must_change_password',
        'first_name', 'middle_name', 'first_surname', 'second_surname',
        'photo_path', 'is_admin',
    ];

    protected $hidden = ['password'];

    protected $casts = [
        'is_admin' => 'boolean',
        'must_change_password' => 'boolean',
    ];

    protected $dates = ['password_changed_at'];

    /**
     * Id del token de renovación de la sesión que hace la petición (claim "sid").
     *
     * @var int|null
     */
    private $currentSessionId;

    /** @var array|null Roles leídos (se calculan una vez por instancia) */
    private $roleCache;

    public static function findByUsername($username): ?self
    {
        return Username::looksValid($username) ? static::where('username', Username::normalize($username))->first() : null;
    }

    public function worker()
    {
        return $this->hasOne(Worker::class);
    }

    public function settings()
    {
        return $this->hasMany(UserSetting::class);
    }

    public function passwordHistories()
    {
        return $this->hasMany(PasswordHistory::class);
    }

    public function setCurrentSessionId(?int $id): void
    {
        $this->currentSessionId = $id;
    }

    public function currentSessionId(): ?int
    {
        return $this->currentSessionId;
    }

    public function fullName(): string
    {
        return trim(implode(' ', [$this->first_name, $this->middle_name, $this->first_surname, $this->second_surname]));
    }

    public function isAdmin(): bool
    {
        return (bool) $this->is_admin;
    }

    public function isActivated(): bool
    {
        return $this->username !== null && $this->password !== null;
    }

    /**
     * Trabajador de la cuenta (null para el Administrador o si aún no se unió a una Entidad).
     */
    public function workerModel(): ?Worker
    {
        if (! $this->relationLoaded('worker')) {
            $this->setRelation('worker', $this->worker()->first());
        }

        return $this->getRelation('worker');
    }

    public function workerId(): ?int
    {
        $worker = $this->workerModel();

        return $worker ? (int) $worker->id : null;
    }

    public function entityId(): ?int
    {
        $worker = $this->workerModel();

        return $worker ? (int) $worker->entity_id : null;
    }

    /**
     * Puede ver y actuar sobre los datos de esa Entidad.
     */
    public function canAccessEntity($entityId): bool
    {
        return $this->isAdmin() || ($entityId !== null && (int) $entityId === $this->entityId());
    }

    public function isTransportChief(): bool
    {
        return $this->roles()['transport_chief'];
    }

    /**
     * Administrador o Jefe de Transporte: gestiona vehículos, itinerarios y viajes.
     */
    public function managesTransport(): bool
    {
        return $this->isAdmin() || $this->isTransportChief();
    }

    /**
     * Gestiona el transporte de esa Entidad.
     */
    public function managesEntity($entityId): bool
    {
        return $this->isAdmin() || ($this->isTransportChief() && (int) $entityId === $this->entityId());
    }

    public function isDriver(): bool
    {
        return $this->roles()['driver_id'] !== null;
    }

    public function driverId(): ?int
    {
        return $this->roles()['driver_id'];
    }

    /**
     * Ids de los itinerarios de los que es jefe (como mucho uno).
     *
     * @return int[]
     */
    public function chiefItineraryIds(): array
    {
        return $this->roles()['itinerary_ids'];
    }

    public function isItineraryChief(): bool
    {
        return $this->chiefItineraryIds() !== [];
    }

    /**
     * Jefe de ese itinerario. El Administrador lo es de todos, y el Jefe de
     * Transporte de todos los de su Entidad.
     */
    public function isChiefOf(?int $itineraryId): bool
    {
        if ($itineraryId === null) {
            return false;
        }

        if ($this->isAdmin() || in_array($itineraryId, $this->chiefItineraryIds(), true)) {
            return true;
        }

        return $this->isTransportChief() && (int) Itinerary::withTrashed()->whereKey($itineraryId)->value('entity_id') === $this->entityId();
    }

    /**
     * Puede planificar viajes de ese itinerario: Administrador, Jefes de
     * Transporte de su Entidad y los Jefes de ese itinerario.
     */
    public function canPlan(?int $itineraryId): bool
    {
        return $this->isChiefOf($itineraryId);
    }

    /**
     * Puede planificar viajes de algún itinerario.
     */
    public function plansTrips(): bool
    {
        return $this->managesTransport() || $this->isItineraryChief();
    }

    /**
     * Olvida los roles leídos (tras cambiarlos).
     */
    public function refreshRoles(): self
    {
        $this->roleCache = null;
        $this->unsetRelation('worker');

        return $this;
    }

    private function roles(): array
    {
        if ($this->roleCache === null) {
            $workerId = $this->workerId();
            $this->roleCache = $workerId === null
                ? ['transport_chief' => false, 'driver_id' => null, 'itinerary_ids' => []]
                : [
                    'transport_chief' => TransportChief::where('worker_id', $workerId)->exists(),
                    'driver_id' => ($id = Driver::where('worker_id', $workerId)->value('id')) ? (int) $id : null,
                    'itinerary_ids' => array_map('intval', ItineraryChief::where('worker_id', $workerId)->pluck('itinerary_id')->all()),
                ];
        }

        return $this->roleCache;
    }
}
