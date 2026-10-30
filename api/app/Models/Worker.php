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

    public function rank()
    {
        return $this->belongsTo(Rank::class);
    }

    public function settings()
    {
        return $this->hasMany(UserSetting::class);
    }
}
