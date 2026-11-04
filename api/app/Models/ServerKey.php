<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Clave del servidor para firmar los QR (la lógica es de la parte del QR).
 */
class ServerKey extends Model
{
    use SoftDeletes;

    protected $fillable = ['purpose', 'public_key', 'private_key_encrypted'];

    protected $hidden = ['private_key_encrypted'];
}
