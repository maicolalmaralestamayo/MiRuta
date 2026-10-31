<?php

namespace App\Models;

use Illuminate\Auth\Authenticatable;
use Illuminate\Contracts\Auth\Access\Authorizable as AuthorizableContract;
use Illuminate\Contracts\Auth\Authenticatable as AuthenticatableContract;
use Illuminate\Database\Eloquent\Model;
use App\Support\CardNumber;
use App\Support\Username;
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
        'username', 'card_number_encrypted', 'card_number_hash', 'first_name', 'last_name',
        'sex', 'password', 'rank_id', 'photo_path', 'is_admin',
    ];

    protected $hidden = ['card_number_encrypted', 'card_number_hash', 'password'];

    protected $casts = [
        'is_admin' => 'boolean',
        'must_change_password' => 'boolean',
    ];

    /**
     * Trabajador activo que inicia sesión con su usuario o, como alternativa,
     * con su carné (11 dígitos). Un usuario nunca son 11 dígitos: empieza por letra.
     */
    public static function findByLogin($login): ?self
    {
        if (! is_string($login)) {
            return null;
        }

        $login = trim($login);

        if (preg_match('/^\d{11}$/', $login)) {
            return static::where('card_number_hash', CardNumber::hashOf($login))->first();
        }

        return Username::isValid($login) ? static::where('username', Username::normalize($login))->first() : null;
    }

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

    public function children()
    {
        return $this->hasMany(Child::class);
    }

    public function applications()
    {
        return $this->hasMany(Application::class);
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

    /**
     * El Administrador cuenta como Jefe de todos los itinerarios.
     */
    public function isChiefOf(?int $itineraryId): bool
    {
        return $itineraryId !== null && ($this->isAdmin() || in_array($itineraryId, $this->chiefItineraryIds(), true));
    }

    /**
     * Puede planificar viajes de ese itinerario: Administrador, Jefes de
     * Transporte y los Jefes de ese itinerario.
     */
    public function canPlan(?int $itineraryId): bool
    {
        return $this->managesTransport() || $this->isChiefOf($itineraryId);
    }

    /**
     * Puede planificar viajes de algún itinerario.
     */
    public function plansTrips(): bool
    {
        return $this->managesTransport() || $this->chiefItineraryIds() !== [];
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
