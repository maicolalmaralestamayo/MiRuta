<?php

namespace App\Http\Controllers;

use App\JsonApi\JsonApiException;
use App\JsonApi\QueryParameters;
use App\Models\ItineraryStop;
use App\Models\Stop;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class StopController extends ResourceController
{
    protected $model = Stop::class;

    protected $type = 'stops';

    protected $attributes = [
        'landmark' => 'landmark',
        'street' => 'street',
        'crossStreet1' => 'cross_street_1',
        'crossStreet2' => 'cross_street_2',
        'latitude' => 'latitude',
        'longitude' => 'longitude',
    ];

    protected $sortable = ['id' => 'id', 'landmark' => 'landmark', 'street' => 'street'];

    protected $filterable = ['itinerary', 'search'];

    protected $defaultSort = 'landmark';

    protected function rules(Request $request, ?Model $model): array
    {
        $presence = $model ? 'sometimes' : 'required';

        return [
            'attributes.landmark' => [$presence, 'string', 'max:255'],
            'attributes.street' => [$presence, 'string', 'max:255'],
            'attributes.crossStreet1' => ['sometimes', 'nullable', 'string', 'max:255'],
            'attributes.crossStreet2' => ['sometimes', 'nullable', 'string', 'max:255'],
            'attributes.latitude' => [$presence, 'numeric', 'between:-90,90'],
            'attributes.longitude' => [$presence, 'numeric', 'between:-180,180'],
        ];
    }

    protected function applyFilters(Builder $query, QueryParameters $parameters, Request $request): void
    {
        if ($itinerary = $parameters->filter('itinerary')) {
            $query->whereIn('id', ItineraryStop::where('itinerary_id', $itinerary)->select('stop_id'));
        }

        if ($search = $parameters->filter('search')) {
            $query->where(function ($query) use ($search) {
                foreach (['landmark', 'street', 'cross_street_1', 'cross_street_2'] as $column) {
                    $query->orWhere($column, 'like', '%'.$search.'%');
                }
            });
        }
    }

    protected function beforeDelete(Model $stop, Request $request): void
    {
        if (ItineraryStop::where('stop_id', $stop->id)->exists()) {
            throw JsonApiException::conflict('STOP_IN_USE', 'La parada está en algún itinerario. Primero hay que quitarla de ellos.');
        }
    }
}
