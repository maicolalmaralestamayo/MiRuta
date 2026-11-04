<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class ChildParent extends Model
{
    use SoftDeletes;

    protected $table = 'child_parents';

    protected $fillable = ['child_id', 'user_id'];

    public function child()
    {
        return $this->belongsTo(Child::class)->withTrashed();
    }

    public function user()
    {
        return $this->belongsTo(User::class)->withTrashed();
    }
}
