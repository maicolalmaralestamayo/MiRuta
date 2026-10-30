<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Trabajador y usuario de la app. Inactivo = borrado lógico.
 */
class Worker extends Model
{
    use SoftDeletes;

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

    public function rank()
    {
        return $this->belongsTo(Rank::class);
    }

    public function settings()
    {
        return $this->hasMany(UserSetting::class);
    }
}
