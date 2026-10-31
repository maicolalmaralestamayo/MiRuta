<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Rank extends Model
{
    use SoftDeletes;

    protected $fillable = ['name', 'description', 'observation', 'sort_order', 'icon_path'];

    protected $casts = [
        'sort_order' => 'integer',
    ];

    public function workers()
    {
        return $this->hasMany(Worker::class);
    }
}
