<?php

namespace App\Http\Controllers;

use App\JsonApi\JsonApiException;
use App\JsonApi\QueryParameters;
use App\Models\Itinerary;
use App\Models\ItineraryStop;
use App\Models\Stop;
use App\Services\Access;
use App\Services\Organization;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Paradas, compartidas entre itinerarios y Entidades (docs/11 §11.24).
 *
 * - Ven todas: el Administrador y los Jefes (para «Añadir parada existente»);
 *   el trabajador, las de los itinerarios de sus Entidades.
 * - Crean: el Administrador y el Jefe (en su itinerario: relationships.itinerary).
 * - Editan: el Administrador; el Jefe, las de su itinerario (aunque las usen otros).
 * - Eliminan: el Administrador; el Jefe, solo las de su itinerario que no use
 *   ningún otro (si no, solo puede quitarla del suyo).
 *
 * Con filter[itinerary] salen en el orden del itinerario (sort=position).
 */
class StopController extends Controller
{
    public function __construct(private Access $access)
    {
    }

    public function index(Request $request)
    {
        $sortable = [
            'id' => 'id', 'landmark' => 'landmark', 'street' => 'street', 'createdAt' => 'created_at',
            'position' => ItineraryStop::select('position')->whereColumn('itinerary_stop.stop_id', 'stops.id')
                ->where('itinerary_stop.itinerary_id', (int) $request->input('filter.itinerary')),
        ];
        $parameters = QueryParameters::fromRequest($request, $sortable, ['itinerary', 'entity', 'search', 'active'], [],
            ctype_digit((string) $request->input('filter.itinerary')) ? 'position' : 'landmark');
        $query = $this->visible($request);
        $itinerary = $parameters->filter('itinerary');

        if ($itinerary === 'none') {
            $query->whereNotIn('id', ItineraryStop::select('stop_id'));
        } elseif ($itinerary !== null) {
            $query->whereIn('id', ItineraryStop::where('itinerary_id', (int) $itinerary)->select('stop_id'));
        }

        if ($entity = $parameters->filter('entity')) {
            $query->whereIn('id', ItineraryStop::whereIn('itinerary_id', Itinerary::where('entity_id', (int) $entity)->select('id'))->select('stop_id'));
        }

        if ($search = $parameters->filter('search')) {
            $like = '%'.$search.'%';
            $query->where(fn ($q) => $q->where('landmark', 'like', $like)->orWhere('street', 'like', $like)
                ->orWhere('cross_street_1', 'like', $like)->orWhere('cross_street_2', 'like', $like));
        }

        if ($parameters->filter('active') !== null) {
            $query->where('active', $parameters->filter('active') === 'true');
        }

        return $this->paginate($request, $query, $parameters, $sortable);
    }

    public function show(Request $request, $id)
    {
        return $this->respond($request, $this->visible($request)->findOrFail($id));
    }

    /**
     * Con relationships.itinerary se añade a ese itinerario (al final o en
     * meta.position). El Jefe tiene que indicar su itinerario.
     */
    public function store(Request $request, Organization $organization)
    {
        $user = $request->user();
        $data = $this->validateResource($request, 'stops', $this->rules(true) + $this->relationshipRules('itinerary', 'itineraries', 'itineraries', false));
        $itineraryId = $this->relationshipId($data, 'itinerary');

        if (! $this->access->isAdmin($user) && ! ($itineraryId !== null && $this->access->isChiefOf($user, $itineraryId))) {
            throw Access::forbidden('Solo el Administrador crea paradas; el Jefe, en su itinerario (relationships.itinerary).');
        }

        $stop = DB::transaction(function () use ($data, $itineraryId, $organization, $request) {
            $stop = new Stop();
            $this->fill($stop, $data['attributes']);
            $stop->save();

            if ($itineraryId !== null) {
                $position = $request->json('meta.position');
                $organization->addStop(Itinerary::findOrFail($itineraryId), $stop, is_int($position) ? $position : null);
            }

            return $stop;
        });

        return $this->created($request, $stop->fresh(), 'stops');
    }

    public function update(Request $request, $id)
    {
        $stop = Stop::findOrFail($id);
        $user = $request->user();

        if (! $this->access->isAdmin($user) && ! $this->inChiefItinerary($user, $stop)) {
            throw Access::forbidden('Solo el Administrador, o el Jefe de un itinerario que la tiene, editan esta parada.');
        }

        $data = $this->validateResource($request, 'stops', $this->rules(false));
        $this->fill($stop, $data['attributes'] ?? []);
        $stop->save();

        return $this->respond($request, $stop->fresh());
    }

    public function destroy(Request $request, Organization $organization, $id)
    {
        $stop = Stop::findOrFail($id);
        $user = $request->user();

        if (! $this->access->isAdmin($user)) {
            if (! $this->inChiefItinerary($user, $stop)) {
                throw Access::forbidden('Solo el Administrador, o el Jefe de su itinerario, eliminan esta parada.');
            }

            if (ItineraryStop::where('stop_id', $stop->id)->where('itinerary_id', '<>', $this->access->chiefItineraryId($user))->exists()) {
                throw JsonApiException::conflict('STOP_SHARED', 'La parada la usan otros itinerarios: solo puede quitarla del suyo.');
            }
        }

        $organization->deleteStop($stop);

        return $this->noContent();
    }

    private function inChiefItinerary($user, Stop $stop): bool
    {
        $itineraryId = $this->access->chiefItineraryId($user);

        return $itineraryId !== null && ItineraryStop::where('itinerary_id', $itineraryId)->where('stop_id', $stop->id)->exists();
    }

    private function rules(bool $creating): array
    {
        $presence = $creating ? 'required' : 'sometimes';

        return [
            'attributes' => [$presence, 'array'],
            'attributes.landmark' => [$presence, 'string', 'max:255', 'regex:/\S/'],
            'attributes.street' => [$presence, 'string', 'max:255', 'regex:/\S/'],
            'attributes.crossStreet1' => ['sometimes', 'nullable', 'string', 'max:255'],
            'attributes.crossStreet2' => ['sometimes', 'nullable', 'string', 'max:255'],
            'attributes.latitude' => [$presence, 'numeric', 'between:-90,90'],
            'attributes.longitude' => [$presence, 'numeric', 'between:-180,180'],
            'attributes.active' => ['sometimes', 'boolean'],
        ];
    }

    private function fill(Stop $stop, array $attributes): void
    {
        foreach (['landmark' => 'landmark', 'street' => 'street', 'crossStreet1' => 'cross_street_1', 'crossStreet2' => 'cross_street_2'] as $attribute => $column) {
            if (array_key_exists($attribute, $attributes)) {
                $stop->{$column} = self::text($attributes[$attribute]);
            }
        }

        foreach (['latitude', 'longitude'] as $field) {
            if (array_key_exists($field, $attributes)) {
                $stop->{$field} = round((float) $attributes[$field], 7);
            }
        }

        if (array_key_exists('active', $attributes)) {
            $stop->active = (bool) $attributes['active'];
        }
    }

    private function visible(Request $request): Builder
    {
        $user = $request->user();
        $query = Stop::query();

        if ($this->access->isAdmin($user) || $this->access->isChief($user)) {
            return $query;
        }

        $itineraries = Itinerary::whereIn('entity_id', $this->access->entityIds($user) ?: [0])->select('id');

        return $query->where('active', true)->whereIn('id', ItineraryStop::whereIn('itinerary_id', $itineraries)->select('stop_id'));
    }
}
