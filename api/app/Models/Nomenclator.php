<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Elemento de un nomenclador (docs/11 §11.26 y §11.31).
 */
abstract class Nomenclator extends Model
{
    protected $fillable = ['name', 'description', 'observation', 'active'];

    protected $casts = ['active' => 'boolean'];
}
