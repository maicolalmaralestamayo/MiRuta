<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\Models\Itinerary;
use App\Models\TripLeg;
use App\Models\Worker;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class ItineraryController extends NomenclatorController
{
    protected $model = Itinerary::class;

    protected $type = 'itineraries';

    protected $entityScoped = true;

    protected $filterable = ['name', 'entity'];

    protected $relationships = [
        'referenceOutboundLeg' => ['trip-legs', 'reference_outbound_leg_id'],
        'referenceReturnLeg' => ['trip-legs', 'reference_return_leg_id'],
    ];

    /**
     * El Jefe de itinerario puede marcar el recorrido de referencia del suyo
     * (solo eso); el resto lo gestiona el Jefe de Transporte.
     */
    public function update(Request $request, $id)
    {
        $user = $request->user();
        $data = $request->json('data');
        $onlyReference = is_array($data) && empty($data['attributes'])
            && ! empty($data['relationships'])
            && ! array_diff(array_keys($data['relationships']), ['referenceOutboundLeg', 'referenceReturnLeg']);

        if ($onlyReference && ! $user->isTransportChief() && ! $user->isAdmin() && $user->isChiefOf((int) $id)) {
            $itinerary = $this->findOrFail($request, $id);
            $validated = $this->validateResource($request, $this->type, $this->rules($request, $itinerary));
            DB::transaction(function () use ($itinerary, $validated, $request) {
                $this->fill($itinerary, $validated);
                $this->beforeSave($itinerary, $request, false);
                $itinerary->save();
            });

            return JsonApiResponse::make((new Document($request))->resource($itinerary->fresh()));
        }

        return parent::update($request, $id);
    }

    protected function newQuery(Request $request): Builder
    {
        return parent::newQuery($request)->with('stops');
    }

    /**
     * El nombre es único dentro de la Entidad.
     */
    protected function rules(Request $request, ?Model $model): array
    {
        $entityId = self::targetEntityId($request, $model);

        return [
            'attributes.name' => [$model ? 'sometimes' : 'required', 'string', 'max:100',
                \Illuminate\Validation\Rule::unique('itineraries', 'name')->where('entity_id', $entityId)->whereNull('deleted_at')->ignore($model ? $model->id : null)],
            'attributes.description' => ['sometimes', 'nullable', 'string'],
            'attributes.observation' => ['sometimes', 'nullable', 'string'],
            'relationships.referenceOutboundLeg.data' => ['sometimes', 'nullable', 'array'],
            'relationships.referenceOutboundLeg.data.type' => ['required_with:data.relationships.referenceOutboundLeg.data', 'in:trip-legs'],
            'relationships.referenceReturnLeg.data' => ['sometimes', 'nullable', 'array'],
            'relationships.referenceReturnLeg.data.type' => ['required_with:data.relationships.referenceReturnLeg.data', 'in:trip-legs'],
        ];
    }

    /**
     * Recorrido de referencia (opción B, docs/09 §8): un viaje de ida o de
     * regreso ya terminado de un viaje de este itinerario, del mismo sentido.
     */
    protected function beforeSave(Model $itinerary, Request $request, bool $creating): void
    {
        parent::beforeSave($itinerary, $request, $creating);

        foreach (['reference_outbound_leg_id' => TripLeg::DIRECTION_OUTBOUND, 'reference_return_leg_id' => TripLeg::DIRECTION_RETURN] as $column => $direction) {
            if (! $itinerary->isDirty($column) || $itinerary->{$column} === null) {
                continue;
            }

            $leg = TripLeg::with('trip')->find($itinerary->{$column});

            if (! $leg || $creating || (int) $leg->trip->itinerary_id !== (int) $itinerary->id || $leg->direction !== $direction || $leg->isActive()) {
                $name = $direction === TripLeg::DIRECTION_OUTBOUND ? 'referenceOutboundLeg' : 'referenceReturnLeg';
                throw new JsonApiException(422, 'INVALID_REFERENCE_LEG', 'Recorrido de referencia no válido',
                    'Tiene que ser un viaje de '.($direction === TripLeg::DIRECTION_OUTBOUND ? 'ida' : 'regreso').' ya terminado de este itinerario.',
                    ['pointer' => "/data/relationships/{$name}"]);
            }
        }
    }

    protected function restorable(array $data): ?Model
    {
        $entityId = self::targetEntityId(app('request'), null);

        return Itinerary::onlyTrashed()->where('entity_id', $entityId)->where('name', trim($data['attributes']['name']))->first();
    }

    /**
     * Entidad en la que se crea o está el recurso.
     */
    public static function targetEntityId(Request $request, ?Model $model): ?int
    {
        if ($model) {
            return (int) $model->entity_id;
        }

        $user = $request->user();

        return $user->isAdmin() ? (int) $request->input('data.relationships.entity.data.id') : $user->entityId();
    }

    protected function beforeDelete(Model $itinerary, Request $request): void
    {
        if (Worker::where('itinerary_id', $itinerary->id)->exists()) {
            throw JsonApiException::conflict('ITINERARY_HAS_MEMBERS', 'El itinerario tiene miembros. Primero hay que cambiarlos de itinerario.');
        }
    }
}
