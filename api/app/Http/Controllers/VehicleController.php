<?php

namespace App\Http\Controllers;

use App\JsonApi\QueryParameters;
use App\Models\Vehicle;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class VehicleController extends ResourceController
{
    protected $model = Vehicle::class;

    protected $type = 'vehicles';

    protected $attributes = [
        'plate' => 'plate',
        'seats' => 'seats',
        'standingCapacity' => 'standing_capacity',
    ];

    protected $relationships = [
        'vehicleType' => ['vehicle-types', 'vehicle_type_id'],
        'driver' => ['drivers', 'driver_id'],
    ];

    protected $sortable = ['id' => 'id', 'plate' => 'plate'];

    protected $filterable = ['vehicleType', 'driver', 'search', 'entity'];

    protected $entityScoped = true;

    protected $includable = ['vehicleType', 'driver', 'driver.worker', 'driver.worker.user', 'entity'];

    protected $defaultSort = 'plate';

    protected function rules(Request $request, ?Model $model): array
    {
        $presence = $model ? 'sometimes' : 'required';
        // La matrícula es única dentro de la Entidad.
        $unique = \Illuminate\Validation\Rule::unique('vehicles', 'plate')
            ->where('entity_id', ItineraryController::targetEntityId($request, $model))
            ->whereNull('deleted_at')->ignore($model ? $model->id : null);

        return array_merge([
            'attributes.plate' => [$presence, 'string', 'max:20', $unique],
            'attributes.seats' => [$presence, 'integer', 'min:0', 'max:500'],
            'attributes.standingCapacity' => [$presence, 'integer', 'min:0', 'max:500'],
        ],
            $this->relationshipRules('vehicleType', 'vehicle-types', 'vehicle_types', ! $model),
            $this->relationshipRules('driver', 'drivers', 'drivers', false, true)
        );
    }

    protected function applyFilters(Builder $query, QueryParameters $parameters, Request $request): void
    {
        if ($type = $parameters->filter('vehicleType')) {
            $query->where('vehicle_type_id', $type);
        }

        if ($driver = $parameters->filter('driver')) {
            $query->where('driver_id', $driver);
        }

        if ($search = $parameters->filter('search')) {
            $query->where('plate', 'like', '%'.$search.'%');
        }
    }

    protected function restorable(array $data): ?Model
    {
        return Vehicle::onlyTrashed()
            ->where('entity_id', ItineraryController::targetEntityId(app('request'), null))
            ->where('plate', trim($data['attributes']['plate']))->first();
    }

    /**
     * El chofer habitual tiene que ser de la misma Entidad.
     */
    protected function beforeSave(Model $model, Request $request, bool $creating): void
    {
        parent::beforeSave($model, $request, $creating);
        \App\Support\Tenancy::ensureSame((int) $model->entity_id, 'drivers', $model->driver_id, '/data/relationships/driver');
    }
}
