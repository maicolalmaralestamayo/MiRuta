<?php

namespace App\Models;

use Illuminate\Auth\Authenticatable;
use Illuminate\Contracts\Auth\Access\Authorizable as AuthorizableContract;
use Illuminate\Contracts\Auth\Authenticatable as AuthenticatableContract;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Laravel\Lumen\Auth\Authorizable;

/**
 * Trabajador y usuario de la app. Inactivo = borrado lógico.
 */
class Worker extends Model implements AuthenticatableContract, AuthorizableContract
{
    use Authenticatable, Authorizable, SoftDeletes;

    const SEX_FEMALE = 'F';
    const SEX_MALE = 'M';

    protected $fillable = [
        'card_number_encrypted', 'card_number_hash', 'first_name', 'last_name',
        'sex', 'password', 'rank_id', 'photo_path', 'is_admin',
    ];

    protected $hidden = ['card_number_encrypted', 'card_number_hash', 'password'];

    protected $casts = [
        'is_admin' => 'boolean',
    ];

    /**
     * Id del token de renovación de la sesión que hace la petición (claim "sid").
     *
     * @var int|null
     */
    private $currentSessionId;

    public function setCurrentSessionId(?int $id): void
    {
        $this->currentSessionId = $id;
    }

    public function currentSessionId(): ?int
    {
        return $this->currentSessionId;
    }

    /** @var array|null Roles leídos (se calculan una vez por instancia) */
    private $roleCache;

    public function rank()
    {
        return $this->belongsTo(Rank::class);
    }

    public function itinerary()
    {
        return $this->belongsTo(Itinerary::class);
    }

    public function stop()
    {
        return $this->belongsTo(Stop::class);
    }

    public function driver()
    {
        return $this->hasOne(Driver::class);
    }

    public function transportChief()
    {
        return $this->hasOne(TransportChief::class);
    }

    public function itineraryChiefs()
    {
        return $this->hasMany(ItineraryChief::class);
    }

    public function isAdmin(): bool
    {
        return (bool) $this->is_admin;
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

    public function isDriver(): bool
    {
        return $this->roles()['driver_id'] !== null;
    }

    public function driverId(): ?int
    {
        return $this->roles()['driver_id'];
    }

    /**
     * Ids de los itinerarios de los que es jefe.
     *
     * @return int[]
     */
    public function chiefItineraryIds(): array
    {
        return $this->roles()['itinerary_ids'];
    }

    public function isChiefOf(?int $itineraryId): bool
    {
        return $itineraryId !== null && in_array($itineraryId, $this->chiefItineraryIds(), true);
    }

    /**
     * Olvida los roles leídos (tras cambiarlos).
     */
    public function refreshRoles(): self
    {
        $this->roleCache = null;

        return $this;
    }

    private function roles(): array
    {
        if ($this->roleCache === null) {
            $this->roleCache = [
                'transport_chief' => TransportChief::where('worker_id', $this->id)->exists(),
                'driver_id' => ($id = Driver::where('worker_id', $this->id)->value('id')) ? (int) $id : null,
                'itinerary_ids' => array_map('intval', ItineraryChief::where('worker_id', $this->id)->pluck('itinerary_id')->all()),
            ];
        }

        return $this->roleCache;
    }

    public function settings()
    {
        return $this->hasMany(UserSetting::class);
    }
}
