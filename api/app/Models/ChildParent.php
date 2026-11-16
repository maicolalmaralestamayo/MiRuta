<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ChildParent extends Model
{
    use \App\Models\Concerns\LogsChanges;

    protected $fillable = ['child_id', 'user_id'];
}
