<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Instalación de la app sin sesión (cabecera X-Installation): para «Olvidé algo».
 */
class Installation extends Model
{
    protected $fillable = ['secret_hash', 'device_model', 'android_version', 'app_version_code', 'user_id', 'blocked_at'];

    protected $hidden = ['secret_hash'];

    protected $casts = ['blocked_at' => 'datetime'];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function isBlocked(): bool
    {
        return $this->blocked_at !== null;
    }
}
