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

    protected $entityScoped = true;

    protected $filterable = ['name', 'entity'];

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
        ];
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
