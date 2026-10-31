<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Hash de una contraseña anterior, para no repetirla.
 */
class PasswordHistory extends Model
{
    use SoftDeletes;

    protected $fillable = ['user_id', 'password_hash'];

    protected $hidden = ['password_hash'];
}
