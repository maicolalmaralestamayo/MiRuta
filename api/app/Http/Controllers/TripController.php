<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Trip;
use App\Models\Worker;
use App\Services\Memberships;
use App\Services\Permissions;
use App\Services\Trips;
use Carbon\Carbon;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;

class TripController extends Controller
{
    const SORTABLE = ['departsAt' => 'departs_at', 'returnsAt' => 'returns_at', 'updatedAt' => 'updated_at', 'id' => 'id'];

    const FILTERABLE = ['itinerary', 'vehicle', 'driver', 'status', 'from', 'to', 'updatedSince', 'overloaded'];

    const INCLUDABLE = ['itinerary', 'vehicle', 'vehicle.vehicleType', 'driver', 'driver.user', 'createdBy'];

    /** @var Trips */
    private $trips;

    public function __construct(Trips $trips)
    {
        $this->trips = $trips;
    }

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, self::SORTABLE, self::FILTERABLE, self::INCLUDABLE, 'departsAt');
        $query = $this->trips->visibleTo($request->user())->with('itinerary.stops', 'vehicle', 'driver');
        $this->applyFilters($query, $parameters);
        $parameters->applySort($query, self::SORTABLE);

        if ($parameters->filter('overloaded') !== null) {
            $wanted = $parameters->filter('overloaded') === 'true';
            $all = $query->get()->filter(function (Trip $trip) use ($wanted) {
                return $this->trips->occupancy($trip)['overloaded'] === $wanted;
            })->values();
            $paginator = new LengthAwarePaginator(
                $all->forPage($parameters->pageNumber(), $parameters->pageSize())->values(),
                $all->count(),
                $parameters->pageSize(),
                $parameters->pageNumber()
            );
        } else {
            $paginator = $query->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());
        }

        return JsonApiResponse::make((new Document($request))->collection($paginator, $parameters->includes()));
    }

    public function show(Request $request, $id)
    {
        $trip = $this->findVisible($request, $id);

        return JsonApiResponse::make((new Document($request))->resource($trip, QueryParameters::readIncludes($request, self::INCLUDABLE)));
    }

    public function store(Request $request)
    {
        $this->authorizeManagement($request);
        $data = $this->validateResource($request, 'trips', $this->rules(true));
        $trip = $this->create($data, $request);

        return JsonApiResponse::make((new Document($request))->resource($trip), 201, ['Location' => url('api/v1/trips/'.$trip->id)]);
    }

    public function update(Request $request, $id)
    {
        $this->authorizeManagement($request);
        $trip = $this->findVisible($request, $id);
        $data = $this->validateResource($request, 'trips', $this->rules(false));

        if (isset($data['id']) && (string) $data['id'] !== (string) $trip->id) {
            throw JsonApiException::conflict('ID_MISMATCH', 'El id del documento no coincide con el de la URL.', '/data/id');
        }

        return JsonApiResponse::make((new Document($request))->resource($this->modify($trip, $data, $request)));
    }

    /**
     * Eliminar un viaje (trips.delete en su Entidad).
     */
    public function destroy(Request $request, $id)
    {
        $trip = $this->findVisible($request, $id);
        $this->permissions()->authorize($request->user(), 'trips.delete', $this->trips->entityOf($trip), null, 'No puede eliminar viajes de esta Entidad.');

        if (\App\Models\TripLeg::where('trip_id', $trip->id)->exists()) {
            throw JsonApiException::conflict('TRIP_STARTED', 'El viaje ya comenzó: no se puede eliminar. Puede cancelarlo.');
        }

        $trip->delete();

        return response('', 204);
    }

    /**
     * Crea un viaje (también desde /operations): trips.plan sobre el itinerario.
     */
    public function create(array $data, Request $request): Trip
    {
        return DB::transaction(function () use ($data, $request) {
            $trip = new Trip(['status' => Trip::STATUS_UNCONFIRMED, 'created_by' => $request->user()->id]);
            $this->fill($trip, $data);
            $this->authorizeOperation($request, 'trips.plan', $trip, 'Solo puede planificar viajes de los itinerarios de su ámbito.');

            if ($trip->status !== Trip::STATUS_UNCONFIRMED) {
                $this->authorizeOperation($request, $trip->status === Trip::STATUS_COMPLETED ? 'trips.complete' : 'trips.confirm_cancel', $trip);
            }

            $this->ensureSameEntity($trip);
            $this->trips->validate($trip);
            $trip->save();

            return $trip->fresh();
        });
    }

    /**
     * Modifica un viaje (también desde /operations): vehículo, chofer y horas
     * con trips.edit; confirmar, desconfirmar y cancelar con
     * trips.confirm_cancel; marcarlo como realizado con trips.complete.
     */
    public function modify(Trip $trip, array $data, Request $request): Trip
    {
        return DB::transaction(function () use ($trip, $data, $request) {
            $trip = Trip::lockForUpdate()->findOrFail($trip->id);
            $previousStatus = $trip->status;
            $original = clone $trip;
            $this->fill($trip, $data);

            if ($trip->isDirty(['itinerary_id', 'vehicle_id', 'driver_id', 'departs_at', 'returns_at'])) {
                $this->authorizeOperation($request, 'trips.edit', $original);
                $this->authorizeOperation($request, 'trips.edit', $trip);
            }

            if ($trip->status !== $previousStatus) {
                $this->authorizeOperation($request, $trip->status === Trip::STATUS_COMPLETED ? 'trips.complete' : 'trips.confirm_cancel', $trip);
            }

            $this->ensureSameEntity($trip);
            $this->trips->applyStatusChange($trip, $previousStatus, $request->user());

            if ($trip->isDirty(['departs_at', 'returns_at', 'vehicle_id', 'driver_id', 'status'])) {
                $this->trips->validate($trip);
            }

            $trip->save();
            $this->trips->afterStatusChange($trip, $previousStatus, $request->user());

            return $trip->fresh();
        });
    }

    public function rules(bool $creating): array
    {
        $presence = $creating ? 'required' : 'sometimes';
        $relationship = function (string $name, string $type, string $table) use ($presence) {
            return [
                "relationships.{$name}.data.type" => [$presence, "in:{$type}"],
                "relationships.{$name}.data.id" => [$presence, "exists:{$table},id,deleted_at,NULL"],
            ];
        };

        return array_merge([
            'attributes.departsAt' => [$presence, 'date'],
            'attributes.returnsAt' => [$presence, 'date'],
            'attributes.status' => ['sometimes', 'in:'.implode(',', Trip::STATUSES)],
        ],
            $relationship('itinerary', 'itineraries', 'itineraries'),
            $relationship('vehicle', 'vehicles', 'vehicles'),
            $relationship('driver', 'workers', 'workers')
        );
    }

    /**
     * Tiene alguna operación de gestión de viajes en algún sitio (el detalle
     * se comprueba con el itinerario de cada viaje).
     */
    public function authorizeManagement(Request $request): void
    {
        $permissions = $this->permissions();

        foreach (['trips.plan', 'trips.edit', 'trips.confirm_cancel', 'trips.complete'] as $operation) {
            if ($permissions->canAnywhere($request->user(), $operation)) {
                return;
            }
        }

        throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'No tiene permiso para planificar ni modificar viajes.');
    }

    private function authorizeOperation(Request $request, string $operation, Trip $trip, ?string $detail = null): void
    {
        if (! $this->permissions()->can($request->user(), $operation, null, (int) $trip->itinerary_id)) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', $detail ?: 'No tiene permiso para hacer esto con los viajes de ese itinerario.', ['pointer' => '/data/relationships/itinerary']);
        }
    }

    private function permissions(): Permissions
    {
        return app(Permissions::class);
    }

    /**
     * El vehículo y el chofer tienen que ser de la Entidad del itinerario, y el
     * chofer, una pertenencia que puede conducir (tracking.drive).
     */
    private function ensureSameEntity(Trip $trip): void
    {
        $entityId = \App\Support\Tenancy::entityOf('itineraries', $trip->itinerary_id);
        \App\Support\Tenancy::ensureSame($entityId, 'vehicles', $trip->vehicle_id, '/data/relationships/vehicle');
        \App\Support\Tenancy::ensureSame($entityId, 'workers', $trip->driver_id, '/data/relationships/driver');

        if ($trip->isDirty('driver_id') && ! app(Memberships::class)->canDrive(Worker::find($trip->driver_id))) {
            throw new JsonApiException(422, 'NOT_A_DRIVER', 'No es chofer', 'Esa persona no tiene permiso para conducir en esta Entidad.', ['pointer' => '/data/relationships/driver']);
        }
    }

    private function fill(Trip $trip, array $data): void
    {
        $attributes = isset($data['attributes']) ? $data['attributes'] : [];
        $timezone = config('app.timezone');

        foreach (['departsAt' => 'departs_at', 'returnsAt' => 'returns_at'] as $attribute => $column) {
            if (isset($attributes[$attribute])) {
                $trip->{$column} = Carbon::parse($attributes[$attribute])->setTimezone($timezone);
            }
        }

        if (isset($attributes['status'])) {
            $trip->status = $attributes['status'];
        }

        foreach (['itinerary' => 'itinerary_id', 'vehicle' => 'vehicle_id', 'driver' => 'driver_id'] as $relationship => $column) {
            if (isset($data['relationships'][$relationship]['data']['id'])) {
                $trip->{$column} = (int) $data['relationships'][$relationship]['data']['id'];
            }
        }
    }

    private function applyFilters(Builder $query, QueryParameters $parameters): void
    {
        foreach (['itinerary' => 'itinerary_id', 'vehicle' => 'vehicle_id', 'driver' => 'driver_id'] as $filter => $column) {
            if ($value = $parameters->filter($filter)) {
                $query->where($column, $value);
            }
        }

        if ($status = $parameters->filter('status')) {
            $query->whereIn('status', explode(',', $status));
        }

        if ($from = $parameters->filter('from')) {
            $query->where('departs_at', '>=', $this->date($from, 'from')->startOfDay());
        }

        if ($to = $parameters->filter('to')) {
            $query->where('departs_at', '<=', $this->date($to, 'to')->endOfDay());
        }

        if ($since = $parameters->filter('updatedSince')) {
            $query->where('updated_at', '>', $this->date($since, 'updatedSince')->setTimezone(config('app.timezone')));
        }
    }

    private function date(string $value, string $filter): Carbon
    {
        try {
            return Carbon::parse($value);
        } catch (\Exception $exception) {
            throw JsonApiException::badRequest("filter[{$filter}] no es una fecha válida.", "filter[{$filter}]");
        }
    }

    private function findVisible(Request $request, $id): Trip
    {
        $trip = $this->trips->visibleTo($request->user())->find($id);

        if (! $trip) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'El viaje no existe o no puede verlo.');
        }

        return $trip;
    }
}
