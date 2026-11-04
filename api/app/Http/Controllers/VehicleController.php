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
        'driver' => ['workers', 'driver_id'],
    ];

    protected $manageOperation = 'vehicles.manage';

    protected $viewOperation = 'vehicles.view';

    protected $membersCanView = false;

    protected $sortable = ['id' => 'id', 'plate' => 'plate'];

    protected $filterable = ['vehicleType', 'driver', 'search', 'entity'];

    protected $entityScoped = true;

    protected $includable = ['vehicleType', 'driver', 'driver.user', 'entity'];

    protected $defaultSort = 'plate';

    /**
     * Nomenclatura cubana (docs/09 §9): una letra de las permitidas en el ajuste
     * plate_letters y 6 dígitos. Se guarda junta y en mayúsculas.
     */
    public static function normalizePlate(string $plate): string
    {
        return strtoupper((string) preg_replace('/[\s-]+/', '', $plate));
    }

    /**
     * @return string[]
     */
    public static function plateLetters(): array
    {
        $letters = array_map('trim', explode(',', strtoupper((string) app(\App\Services\Settings::class)->get('plate_letters'))));

        return array_values(array_filter($letters, function ($letter) {
            return preg_match('/^[A-Z]$/', $letter) === 1;
        }));
    }

    protected function rules(Request $request, ?Model $model): array
    {
        $presence = $model ? 'sometimes' : 'required';

        $plate = $request->json('data.attributes.plate');
        if (is_string($plate)) {
            $data = $request->json('data');
            $data['attributes']['plate'] = self::normalizePlate($plate);
            $request->json()->set('data', $data);
        }
        $letters = self::plateLetters();
        $format = function ($attribute, $value, $fail) use ($letters) {
            if (! is_string($value) || ! preg_match('/^['.implode('', $letters).']\d{6}$/', $value)) {
                $fail('La matrícula debe ser una letra ('.implode(', ', $letters).') seguida de 6 dígitos.');
            }
        };
        // La matrícula es única dentro de la Entidad.
        $unique = \Illuminate\Validation\Rule::unique('vehicles', 'plate')
            ->where('entity_id', ItineraryController::targetEntityId($request, $model, 'vehicles.manage'))
            ->whereNull('deleted_at')->ignore($model ? $model->id : null);

        return array_merge([
            'attributes.plate' => [$presence, 'string', 'max:20', $format, $unique],
            'attributes.seats' => [$presence, 'integer', 'min:0', 'max:500'],
            'attributes.standingCapacity' => [$presence, 'integer', 'min:0', 'max:500'],
        ],
            $this->relationshipRules('vehicleType', 'vehicle-types', 'vehicle_types', ! $model),
            $this->relationshipRules('driver', 'workers', 'workers', false, true)
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
            ->where('entity_id', ItineraryController::targetEntityId(app('request'), null, 'vehicles.manage'))
            ->where('plate', trim($data['attributes']['plate']))->first();
    }

    /**
     * Crear, editar y eliminar: vehicles.manage. Solo cambiar el chofer
     * habitual: también vehicles.assign_driver.
     */
    protected function authorizeManage(Request $request, ?int $entityId, ?Model $model = null): void
    {
        $data = $request->json('data');
        $onlyDriver = $model && $request->getMethod() === 'PATCH' && is_array($data) && empty($data['attributes'])
            && isset($data['relationships']) && array_keys($data['relationships']) === ['driver'];

        if ($onlyDriver && app(\App\Services\Permissions::class)->can($request->user(), 'vehicles.assign_driver', $entityId)) {
            return;
        }

        parent::authorizeManage($request, $entityId, $model);
    }

    /**
     * El chofer habitual tiene que ser de la misma Entidad y poder conducir.
     */
    protected function beforeSave(Model $model, Request $request, bool $creating): void
    {
        parent::beforeSave($model, $request, $creating);

        if ($model->isDirty('driver_id') && $model->driver_id !== null) {
            \App\Support\Tenancy::ensureSame((int) $model->entity_id, 'workers', $model->driver_id, '/data/relationships/driver');

            if ($model->driver_id !== $model->getOriginal('driver_id') && ! app(\App\Services\Memberships::class)->canDrive(\App\Models\Worker::find($model->driver_id))) {
                throw new \App\JsonApi\JsonApiException(422, 'NOT_A_DRIVER', 'No es chofer', 'Esa persona no tiene permiso para conducir en esta Entidad.', ['pointer' => '/data/relationships/driver']);
            }
        }
    }
}
