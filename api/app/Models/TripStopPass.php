<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class TripStopPass extends Model
{
    protected $fillable = ['trip_id', 'stop_id', 'route_index', 'passed_at', 'marked_by'];

    protected $casts = ['passed_at' => 'datetime', 'route_index' => 'integer', 'stop_id' => 'integer', 'marked_by' => 'integer'];
}
