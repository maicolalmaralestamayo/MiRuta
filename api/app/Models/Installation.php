<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Instalación de la app en un teléfono. Permite hablar con el desarrollador
 * y recuperar el acceso sin haber iniciado sesión.
 */
class Installation extends Model
{
    use SoftDeletes;

    protected $fillable = ['secret_hash', 'device_model', 'android_version', 'app_version_code', 'user_id', 'blocked_at'];

    protected $hidden = ['secret_hash'];

    protected $dates = ['blocked_at'];

    public function user()
    {
        return $this->belongsTo(User::class)->withTrashed();
    }

    public function isBlocked(): bool
    {
        return $this->blocked_at !== null;
    }
}
