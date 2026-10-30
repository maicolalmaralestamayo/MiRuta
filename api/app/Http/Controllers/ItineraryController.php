<?php

namespace App\Http\Controllers;

use App\JsonApi\JsonApiException;
use App\Models\Itinerary;
use App\Models\Worker;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class ItineraryController extends NomenclatorController
{
    protected $model = Itinerary::class;

    protected $type = 'itineraries';

    protected function newQuery(Request $request): Builder
    {
        return Itinerary::with('stops');
    }

    protected function beforeDelete(Model $itinerary, Request $request): void
    {
        if (Worker::where('itinerary_id', $itinerary->id)->exists()) {
            throw JsonApiException::conflict('ITINERARY_HAS_MEMBERS', 'El itinerario tiene miembros. Primero hay que cambiarlos de itinerario.');
        }
    }
}
