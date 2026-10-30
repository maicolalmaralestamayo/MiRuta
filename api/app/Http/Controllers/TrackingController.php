<?php

namespace App\Http\Controllers;

use App\JsonApi\JsonApiException;
use App\Models\TripLeg;
use App\Services\Trips;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

/**
 * Base de los recursos del recorrido: solo se ven los trayectos de viajes visibles.
 */
abstract class TrackingController extends Controller
{
    protected function visibleLegs(Request $request): Builder
    {
        return TripLeg::whereIn('trip_id', app(Trips::class)->visibleTo($request->user())->select('id'));
    }

    protected function findLeg(Request $request, $id): TripLeg
    {
        $leg = $this->visibleLegs($request)->find($id);

        if (! $leg) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'El trayecto no existe o no puedes verlo.', ['pointer' => '/data/relationships/tripLeg']);
        }

        return $leg;
    }

    protected function legRules(): array
    {
        return [
            'relationships.tripLeg.data.type' => ['required', 'in:trip-legs'],
            'relationships.tripLeg.data.id' => ['required', 'integer'],
        ];
    }
}
