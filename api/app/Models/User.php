<?php

namespace App\Models;

use App\Support\IdentityCard;
use App\Support\Username;
use Illuminate\Database\Eloquent\Model;

/**
 * La persona (docs/11 §11.2 y §11.6). La cuenta es de la persona; en cada
 * Entidad tiene una fila en workers (itinerario, parada, Jefe, activación).
 *
 * Roles fijos (docs/11 §11.30): Administrador (is_admin), Jefe de itinerario
 * (workers.is_chief, en un solo itinerario) y Trabajador (pertenecer a una Entidad).
 */
class User extends Model
{
    protected $fillable = [
        'username', 'password', 'password_changed_at', 'must_change_password',
        'first_name', 'middle_name', 'first_surname', 'second_surname',
        'identity_card_encrypted', 'identity_card_hash', 'sex', 'birth_date',
        'photo_path', 'is_admin', 'app_version_code',
    ];

    protected $hidden = ['password', 'identity_card_encrypted', 'identity_card_hash'];

    protected $casts = [
        'is_admin' => 'boolean',
        'must_change_password' => 'boolean',
        'birth_date' => 'date',
        'password_changed_at' => 'datetime',
        'app_version_code' => 'integer',
    ];

    /** Id del token de renovación de la sesión que hace la petición (claim "sid"). */
    private ?int $currentSessionId = null;

    public static function findByUsername($username): ?self
    {
        return Username::looksValid($username) ? static::where('username', Username::normalize($username))->first() : null;
    }

    public static function findByIdentityCard(string $card): ?self
    {
        return static::where('identity_card_hash', IdentityCard::hash($card))->first();
    }

    public function workers()
    {
        return $this->hasMany(Worker::class);
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
}
