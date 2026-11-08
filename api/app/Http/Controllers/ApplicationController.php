<?php

namespace App\Http\Controllers;

use App\JsonApi\JsonApiException;
use App\JsonApi\QueryParameters;
use App\Models\Application;
use App\Models\Entity;
use App\Models\Itinerary;
use App\Services\Access;
use App\Services\Accounts;
use App\Services\Applications;
use Illuminate\Http\Request;

/**
 * Solicitudes de Entidad y de itinerario (docs/11 §11.23 y §11.26).
 *
 * - POST: type «entidad» (relationships.entity o attributes.entityAbbreviation)
 *   o «itinerario» (relationships.itinerary y, si quiere, relationships.stop).
 * - PATCH: attributes.status «aprobada» o «rechazada» (con relationships.denialReason
 *   y attributes.resolutionNote opcional), por quien la resuelve.
 * - DELETE: quien la hizo (cancelar una pendiente o eliminar una resuelta).
 * - filter[status]: lista separada por comas (por omisión, todas);
 *   filter[mine]=true: solo las propias.
 */
class ApplicationController extends Controller
{
    public const SORTABLE = ['id' => 'id', 'createdAt' => 'created_at', 'resolvedAt' => 'resolved_at'];
    public const INCLUDABLE = ['user', 'entity', 'itinerary', 'stop', 'denialReason', 'resolvedBy'];

    public function __construct(private Applications $applications, private Access $access)
    {
    }

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, self::SORTABLE, ['status', 'type', 'entity', 'itinerary', 'mine'], self::INCLUDABLE, '-createdAt');
        $query = $this->applications->visibleQuery($request->user());

        if ($status = $parameters->filter('status')) {
            $query->whereIn('status', explode(',', $status));
        }

        if ($type = $parameters->filter('type')) {
            $query->where('type', $type);
        }

        foreach (['entity' => 'entity_id', 'itinerary' => 'itinerary_id'] as $filter => $column) {
            if ($value = $parameters->filter($filter)) {
                $query->where($column, (int) $value);
            }
        }

        if ($parameters->filter('mine') === 'true') {
            $query->where('user_id', $request->user()->id);
        } elseif ($parameters->filter('mine') === 'false') {
            $query->where('user_id', '<>', $request->user()->id);
        }

        return $this->paginate($request, $query, $parameters, self::SORTABLE);
    }

    public function show(Request $request, $id)
    {
        return $this->respond($request, $this->applications->visibleQuery($request->user())->findOrFail($id),
            QueryParameters::readIncludes($request, self::INCLUDABLE));
    }

    public function store(Request $request, Accounts $accounts)
    {
        $data = $this->validateResource($request, 'applications', [
            'attributes.type' => ['required', 'in:entidad,itinerario'],
            'attributes.entityAbbreviation' => ['sometimes', 'string', 'max:15'],
        ] + $this->relationshipRules('entity', 'entities', 'entities', false)
          + $this->relationshipRules('itinerary', 'itineraries', 'itineraries', false)
          + $this->relationshipRules('stop', 'stops', 'stops', false, true));
        $user = $request->user();

        if ($data['attributes']['type'] === Application::TYPE_ENTITY) {
            $entity = $this->relationshipId($data, 'entity') !== null
                ? Entity::findOrFail($this->relationshipId($data, 'entity'))
                : $accounts->entityOrFail((string) ($data['attributes']['entityAbbreviation'] ?? ''));
            $application = $this->applications->requestEntity($user, $entity);
        } else {
            if ($this->relationshipId($data, 'itinerary') === null) {
                throw new JsonApiException(422, 'VALIDATION_ERROR', 'Falta el itinerario', 'Indique el itinerario (relationships.itinerary).', ['pointer' => '/data/relationships/itinerary']);
            }
            $application = $this->applications->requestItinerary($user, Itinerary::findOrFail($this->relationshipId($data, 'itinerary')), $this->relationshipId($data, 'stop'));
        }

        return $this->created($request, $application->fresh(), 'applications');
    }

    public function update(Request $request, $id)
    {
        $application = $this->applications->visibleQuery($request->user())->findOrFail($id);
        $data = $this->validateResource($request, 'applications', [
            'attributes.status' => ['required', 'in:aprobada,rechazada'],
            'attributes.resolutionNote' => ['sometimes', 'nullable', 'string', 'max:1000'],
        ] + $this->relationshipRules('denialReason', 'denial-reasons', 'denial_reasons', false));

        if ($data['attributes']['status'] === Application::APPROVED) {
            $this->applications->approve($application, $request->user());
        } else {
            if ($this->relationshipId($data, 'denialReason') === null) {
                throw new JsonApiException(422, 'DENIAL_REASON_REQUIRED', 'Falta el motivo', 'Para rechazar hay que elegir el motivo (relationships.denialReason).', ['pointer' => '/data/relationships/denialReason']);
            }
            $this->applications->reject($application, $request->user(), $this->relationshipId($data, 'denialReason'),
                self::text($data['attributes']['resolutionNote'] ?? null));
        }

        return $this->respond($request, $application->fresh(), QueryParameters::readIncludes($request, self::INCLUDABLE));
    }

    public function destroy(Request $request, $id)
    {
        $application = $this->applications->visibleQuery($request->user())->findOrFail($id);

        if ((int) $application->user_id !== (int) $request->user()->id) {
            throw Access::forbidden('Solo quien hizo la solicitud la cancela o la elimina.');
        }

        $application->delete();

        return $this->noContent();
    }
}
