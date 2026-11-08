<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ReleasedUsername extends Model
{
    protected $fillable = ['user_id', 'username', 'released_at'];

    protected $casts = ['released_at' => 'datetime'];
}
