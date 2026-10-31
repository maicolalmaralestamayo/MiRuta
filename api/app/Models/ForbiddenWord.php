<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Palabra que no puede aparecer en un nombre de usuario (nomenclador).
 */
class ForbiddenWord extends Model
{
    use SoftDeletes;

    protected $fillable = ['name', 'description', 'observation'];
}
