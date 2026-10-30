<?php

namespace App\Http\Controllers;

use App\JsonApi\QueryParameters;
use App\Models\ItineraryChief;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

class ItineraryChiefController extends RoleController
{
    protected $model = ItineraryChief::class;

    protected $type = 'itinerary-chiefs';

    protected $filterable = ['worker', 'itinerary'];

    protected $includable = ['worker', 'itinerary'];

    protected function applyFilters(Builder $query, QueryParameters $parameters, Request $request): void
    {
        parent::applyFilters($query, $parameters, $request);

        if ($itinerary = $parameters->filter('itinerary')) {
            $query->where('itinerary_id', $itinerary);
        }
    }
}
