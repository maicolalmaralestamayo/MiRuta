<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class ConversationTopic extends Model
{
    use SoftDeletes;

    const RECIPIENT_ITINERARY_CHIEFS = 'itinerary_chiefs';
    const RECIPIENT_TRANSPORT_CHIEFS = 'transport_chiefs';
    const RECIPIENT_DEVELOPER = 'developer';

    protected $fillable = ['name', 'description', 'observation', 'recipient'];
}
