<?php

namespace App\Models;

use App\Support\IdentityCard;
use App\Support\Username;
use Illuminate\Auth\Authenticatable;
use Illuminate\Contracts\Auth\Access\Authorizable as AuthorizableContract;
use Illuminate\Contracts\Auth\Authenticatable as AuthenticatableContract;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Laravel\Lumen\Auth\Authorizable;

/**
 * La persona (docs/11 §11.2 y §11.6). Inactiva = borrado lógico.
 *
 * - La cuenta es de la persona: usuario, contraseña, nombres, carné (y con
 *   él sexo y fecha de nacimiento), hijos y QR.
 * - En cada Entidad tiene una pertenencia (`workers`), con su itinerario y
 *   parada y sus roles. Puede no tener ninguna (sin Entidad).
 * - El Administrador (is_admin) tiene todas las operaciones con ámbito
 *   «Todas» y también puede pertenecer a Entidades como un trabajador más.
 */
class User extends Model implements AuthenticatableContract, AuthorizableContract
{
    use Authenticatable, Authorizable, SoftDeletes;

    protected $fillable = [
        'username', 'password', 'password_changed_at', 'must_change_password',
        'first_name', 'middle_name', 'first_surname', 'second_surname',
        'identity_card_encrypted', 'identity_card_hash', 'sex', 'birth_date',
        'photo_path', 'is_admin', 'has_phone', 'printed_qr_version',
    ];

    protected $hidden = ['password', 'identity_card_encrypted', 'identity_card_hash'];

    protected $casts = [
        'is_admin' => 'boolean',
        'must_change_password' => 'boolean',
        'has_phone' => 'boolean',
        'printed_qr_version' => 'integer',
        'birth_date' => 'date',
    ];

    protected $dates = ['password_changed_at'];

    /**
     * Id del token de renovación de la sesión que hace la petición (claim "sid").
     *
     * @var int|null
     */
    private $currentSessionId;

    public static function findByUsername($username): ?self
    {
        return Username::looksValid($username) ? static::where('username', Username::normalize($username))->first() : null;
    }

    public static function findByIdentityCard(string $card, bool $withTrashed = false): ?self
    {
        $query = $withTrashed ? static::withTrashed() : static::query();

        return $query->where('identity_card_hash', IdentityCard::hash($card))->first();
    }

    /**
     * Pertenencias activas (una por Entidad).
     */
    public function workers()
    {
        return $this->hasMany(Worker::class);
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
        return implode(' ', array_filter([$this->first_name, $this->middle_name, $this->first_surname, $this->second_surname], 'strlen'));
    }

    public function isAdmin(): bool
    {
        return (bool) $this->is_admin;
    }

    public function identityCard(): ?string
    {
        return IdentityCard::decrypt($this->identity_card_encrypted);
    }

    /**
     * Pertenencia activa en esa Entidad, o null.
     */
    public function workerIn($entityId): ?Worker
    {
        if ($entityId === null) {
            return null;
        }

        return $this->activeWorkers()->firstWhere('entity_id', (int) $entityId);
    }

    /**
     * @return \Illuminate\Support\Collection|Worker[]
     */
    public function activeWorkers()
    {
        if (! $this->relationLoaded('workers')) {
            $this->setRelation('workers', $this->workers()->orderBy('id')->get());
        }

        return $this->getRelation('workers');
    }

    /**
     * @return int[] ids de sus pertenencias activas
     */
    public function workerIds(): array
    {
        return $this->activeWorkers()->pluck('id')->map(function ($id) {
            return (int) $id;
        })->all();
    }

    /**
     * @return int[] Entidades a las que pertenece
     */
    public function entityIds(): array
    {
        return $this->activeWorkers()->pluck('entity_id')->map(function ($id) {
            return (int) $id;
        })->all();
    }

    /**
     * La Entidad, si pertenece exactamente a una.
     */
    public function singleEntityId(): ?int
    {
        $ids = $this->entityIds();

        return count($ids) === 1 ? $ids[0] : null;
    }

    public function belongsToEntity($entityId): bool
    {
        return $entityId !== null && in_array((int) $entityId, $this->entityIds(), true);
    }

    /**
     * Olvida las pertenencias y permisos leídos (tras cambiarlos).
     */
    public function refreshMemberships(): self
    {
        $this->unsetRelation('workers');
        app(\App\Services\Permissions::class)->flush($this->id);

        return $this;
    }
}
