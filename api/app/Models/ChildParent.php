<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ChildParent extends Model
{
    protected $fillable = ['child_id', 'user_id'];
}
