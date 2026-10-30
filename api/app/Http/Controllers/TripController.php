<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Trip;
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

    const INCLUDABLE = ['itinerary', 'vehicle', 'vehicle.vehicleType', 'driver', 'driver.worker', 'createdBy'];

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
        $trip = Trip::findOrFail($id);
        $data = $this->validateResource($request, 'trips', $this->rules(false));

        if (isset($data['id']) && (string) $data['id'] !== (string) $trip->id) {
            throw JsonApiException::conflict('ID_MISMATCH', 'El id del documento no coincide con el de la URL.', '/data/id');
        }

        return JsonApiResponse::make((new Document($request))->resource($this->modify($trip, $data, $request)));
    }

    /**
     * Crea un viaje (también desde /operations).
     */
    public function create(array $data, Request $request): Trip
    {
        return DB::transaction(function () use ($data, $request) {
            $trip = new Trip(['status' => Trip::STATUS_UNCONFIRMED, 'created_by' => $request->user()->id]);
            $this->fill($trip, $data);
            $this->trips->validate($trip);
            $trip->save();

            return $trip->fresh();
        });
    }

    /**
     * Modifica un viaje (también desde /operations).
     */
    public function modify(Trip $trip, array $data, Request $request): Trip
    {
        return DB::transaction(function () use ($trip, $data, $request) {
            $trip = Trip::lockForUpdate()->findOrFail($trip->id);
            $previousStatus = $trip->status;
            $this->fill($trip, $data);
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
            $relationship('driver', 'drivers', 'drivers')
        );
    }

    public function authorizeManagement(Request $request): void
    {
        if (! $request->user()->managesTransport()) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'Solo los Jefes de Transporte planifican los viajes.');
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
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'El viaje no existe o no puedes verlo.');
        }

        return $trip;
    }
}
