<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Usuario que alguien dejó de usar: queda bloqueado para los demás un tiempo.
 */
class ReleasedUsername extends Model
{
    use SoftDeletes;

    protected $fillable = ['user_id', 'username', 'released_at'];

    protected $dates = ['released_at'];
}
