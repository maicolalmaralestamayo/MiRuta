<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Application;
use App\Models\Entity;
use App\Services\Applications;
use Illuminate\Http\Request;

/**
 * Solicitudes (docs/11 §11.6 y §11.16): entity_membership,
 * itinerary_membership y role. Las envía la propia persona; las resuelve
 * quien tenga permiso; el solicitante las puede cancelar.
 */
class ApplicationController extends Controller
{
    const SORTABLE = ['createdAt' => 'created_at', 'resolvedAt' => 'resolved_at', 'id' => 'id'];

    const FILTERABLE = ['status', 'type', 'mine', 'toResolve', 'user', 'entity', 'itinerary', 'role'];

    const INCLUDABLE = ['user', 'entity', 'createdBy', 'resolvedBy', 'itinerary', 'stop', 'role'];

    /** @var Applications */
    private $applications;

    public function __construct(Applications $applications)
    {
        $this->applications = $applications;
    }

    public function index(Request $request)
    {
        $user = $request->user();
        $parameters = QueryParameters::fromRequest($request, self::SORTABLE, self::FILTERABLE, self::INCLUDABLE, '-createdAt');
        $query = $this->applications->visibleTo($user);

        if ($status = $parameters->filter('status')) {
            $query->whereIn('status', explode(',', $status));
        }

        if ($type = $parameters->filter('type')) {
            $query->whereIn('type', explode(',', $type));
        }

        foreach (['user' => 'user_id', 'entity' => 'entity_id', 'itinerary' => 'itinerary_id', 'role' => 'role_id'] as $filter => $column) {
            if ($value = $parameters->filter($filter)) {
                $query->where($column, $value);
            }
        }

        if ($parameters->filter('mine') === 'true') {
            $query->where('user_id', $user->id);
        }

        if ($parameters->filter('toResolve') === 'true') {
            $this->applications->resolvableBy($user, $query);
        }

        $paginator = $parameters->applySort($query, self::SORTABLE)
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator, $parameters->includes()));
    }

    public function show(Request $request, $id)
    {
        $application = $this->findVisible($request, $id);

        return JsonApiResponse::make((new Document($request))->resource($application, QueryParameters::readIncludes($request, self::INCLUDABLE)));
    }

    /**
     * - entity_membership: relationships.entity o attributes.entityAbbreviation.
     * - itinerary_membership: relationships.itinerary y relationships.stop.
     * - role: relationships.role, relationships.entity (si pertenece a varias)
     *   y relationships.itinerary (si el rol es por itinerario).
     */
    public function store(Request $request)
    {
        $relationship = function (string $name, string $jsonType, string $table) {
            return [
                "relationships.{$name}.data.type" => ['sometimes', "in:{$jsonType}"],
                "relationships.{$name}.data.id" => ['sometimes', "exists:{$table},id,deleted_at,NULL"],
            ];
        };
        $data = $this->validateResource($request, 'applications', array_merge(
            [
                'attributes.type' => ['required', 'in:'.implode(',', Application::TYPES)],
                'attributes.entityAbbreviation' => ['sometimes', 'string', 'max:15'],
            ],
            $relationship('entity', 'entities', 'entities'),
            $relationship('itinerary', 'itineraries', 'itineraries'),
            $relationship('stop', 'stops', 'stops'),
            $relationship('role', 'roles', 'roles')
        ));

        $relationships = isset($data['relationships']) ? $data['relationships'] : [];
        $id = function (string $name) use ($relationships) {
            return isset($relationships[$name]['data']['id']) ? (int) $relationships[$name]['data']['id'] : null;
        };
        $entityId = $id('entity');

        if ($entityId === null && isset($data['attributes']['entityAbbreviation'])) {
            $entity = Entity::findByAbbreviation($data['attributes']['entityAbbreviation']);

            if (! $entity) {
                throw new JsonApiException(422, 'ENTITY_NOT_FOUND', 'Entidad no encontrada',
                    'No hay ninguna Entidad con esa abreviatura. Pregúntela a su superior.', ['pointer' => '/data/attributes/entityAbbreviation']);
            }

            $entityId = (int) $entity->id;
        }

        $application = $this->applications->create($request->user(), [
            'type' => $data['attributes']['type'],
            'entityId' => $entityId,
            'itineraryId' => $id('itinerary'),
            'stopId' => $id('stop'),
            'roleId' => $id('role'),
        ]);

        return JsonApiResponse::make((new Document($request))->resource($application->fresh()), 201, [
            'Location' => url('api/v1/applications/'.$application->id),
        ]);
    }

    /**
     * status = approved o rejected (quien puede resolverla; al rechazar, el
     * motivo es obligatorio) o cancelled (el solicitante).
     */
    public function update(Request $request, $id)
    {
        $application = $this->findVisible($request, $id);
        $user = $request->user();

        $data = $this->validateResource($request, 'applications', [
            'attributes.status' => ['required', 'in:approved,rejected,cancelled'],
            'attributes.resolutionNote' => $request->json('data.attributes.status') === Application::STATUS_REJECTED
                ? ['required', 'string', 'min:3', 'max:1000', 'regex:/\S/']
                : ['sometimes', 'nullable', 'string', 'max:1000'],
        ]);
        $note = isset($data['attributes']['resolutionNote']) ? $data['attributes']['resolutionNote'] : null;

        switch ($data['attributes']['status']) {
            case Application::STATUS_APPROVED:
                $application = $this->applications->approve($application, $user, $note);
                break;
            case Application::STATUS_REJECTED:
                $application = $this->applications->reject($application, $user, $note);
                break;
            default:
                $application = $this->applications->cancel($application, $user);
        }

        return JsonApiResponse::make((new Document($request))->resource($application->fresh()));
    }

    private function findVisible(Request $request, $id): Application
    {
        $application = $this->applications->visibleTo($request->user())->find($id);

        if (! $application) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'La solicitud no existe o no puede verla.');
        }

        return $application;
    }
}
