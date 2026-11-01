<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Application;
use App\Models\Worker;
use App\Support\Tenancy;
use App\Services\Applications;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

class ApplicationController extends Controller
{
    const SORTABLE = ['createdAt' => 'created_at', 'resolvedAt' => 'resolved_at', 'id' => 'id'];

    const FILTERABLE = ['status', 'type', 'mine', 'toResolve', 'worker'];

    const INCLUDABLE = ['worker', 'createdBy', 'resolvedBy', 'itinerary', 'stop', 'child', 'absenceType'];

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
        $query = $this->applications->visibleTo($user)->with('itineraryApplication', 'childApplication.child', 'absenceApplication');

        if ($status = $parameters->filter('status')) {
            $query->whereIn('status', explode(',', $status));
        }

        if ($type = $parameters->filter('type')) {
            $query->whereIn('type', explode(',', $type));
        }

        if ($worker = $parameters->filter('worker')) {
            $query->where('worker_id', $worker);
        }

        if ($parameters->filter('mine') === 'true') {
            $query->where('worker_id', (int) $user->workerId());
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

    public function store(Request $request)
    {
        $type = $request->json('data.attributes.type');
        $data = $this->validateResource($request, 'applications', array_merge(
            [
                'attributes.type' => ['required', 'in:'.implode(',', $this->creatableTypes())],
                'relationships.worker.data.type' => ['sometimes', 'in:workers'],
                'relationships.worker.data.id' => ['sometimes', 'integer'],
            ],
            $this->rulesFor(is_string($type) ? $type : '')
        ));

        $user = $request->user();
        $workerId = isset($data['relationships']['worker']['data']['id']) ? (int) $data['relationships']['worker']['data']['id'] : $user->workerId();

        if ($workerId === null) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Falta el trabajador', 'Indica a qué trabajador se asigna (relationships.worker).', ['pointer' => '/data/relationships/worker']);
        }

        // Para otro trabajador es una asignación o retirada de un superior.
        Tenancy::ensureVisible($user, 'workers', $workerId);
        $worker = Worker::findOrFail($workerId);

        $application = $this->applications->create($user, $worker, $data);

        return JsonApiResponse::make((new Document($request))->resource($application->fresh()), 201, [
            'Location' => url('api/v1/applications/'.$application->id),
        ]);
    }

    /**
     * status = approved o rejected (quien puede resolverla) o cancelled (el solicitante).
     */
    public function update(Request $request, $id)
    {
        $application = $this->findVisible($request, $id);
        $user = $request->user();

        // El trabajador pone (o cambia) las fechas de su ausencia indefinida ya aprobada.
        if ($request->json('data.attributes.status') === null && $application->type === Application::TYPE_ABSENCE) {
            $data = $this->validateResource($request, 'applications', [
                'attributes.startsOn' => ['required', 'date_format:Y-m-d'],
                'attributes.endsOn' => ['required', 'date_format:Y-m-d', 'after_or_equal:data.attributes.startsOn'],
            ]);
            $application = $this->applications->setAbsenceDates($application, $user, $data['attributes']['startsOn'], $data['attributes']['endsOn']);

            return JsonApiResponse::make((new Document($request))->resource($application->fresh()));
        }

        $data = $this->validateResource($request, 'applications', [
            'attributes.status' => ['required', 'in:approved,rejected,cancelled'],
            // Al rechazar, el motivo es obligatorio (docs/09 §16).
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
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'La solicitud no existe o no puedes verla.');
        }

        return $application;
    }

    private function creatableTypes(): array
    {
        return [
            Application::TYPE_ITINERARY_MEMBERSHIP, Application::TYPE_ITINERARY_CHIEF, Application::TYPE_DRIVER,
            Application::TYPE_TRANSPORT_CHIEF, Application::TYPE_CHILD_ADDITION,
            Application::TYPE_CHILD_REMOVAL, Application::TYPE_ABSENCE, Application::TYPE_ITINERARY_LEAVE,
            Application::TYPE_ITINERARY_CHIEF_LEAVE, Application::TYPE_DRIVER_LEAVE, Application::TYPE_TRANSPORT_CHIEF_LEAVE,
        ];
    }

    private function rulesFor(string $type): array
    {
        $relationship = function (string $name, string $jsonType, string $table) {
            return [
                "relationships.{$name}.data.type" => ['required', "in:{$jsonType}"],
                "relationships.{$name}.data.id" => ['required', "exists:{$table},id,deleted_at,NULL"],
            ];
        };

        switch ($type) {
            case Application::TYPE_ITINERARY_MEMBERSHIP:
            case Application::TYPE_ITINERARY_CHIEF:
                return array_merge($relationship('itinerary', 'itineraries', 'itineraries'), $relationship('stop', 'stops', 'stops'));
            case Application::TYPE_ITINERARY_CHIEF_LEAVE:
                return [
                    'relationships.itinerary.data.type' => ['required', 'in:itineraries'],
                    'relationships.itinerary.data.id' => ['required', 'exists:itineraries,id'],
                ];
            case Application::TYPE_CHILD_ADDITION:
                // Varios hijos en una misma solicitud (docs/09 §11) o uno solo (forma anterior).
                if (is_array(request()->json('data.attributes.children'))) {
                    return [
                        'attributes.children' => ['required', 'array', 'min:1', 'max:10'],
                        'attributes.children.*.firstName' => ['required', 'string', 'max:50', 'regex:/\S/'],
                        'attributes.children.*.middleName' => ['sometimes', 'nullable', 'string', 'max:50'],
                        'attributes.children.*.firstSurname' => ['required', 'string', 'max:50', 'regex:/\S/'],
                        'attributes.children.*.secondSurname' => ['required', 'string', 'max:50', 'regex:/\S/'],
                        'attributes.children.*.birthDate' => ['required', 'date_format:Y-m-d'],
                    ];
                }

                return UserController::nameRules('attributes.child') + [
                    'attributes.childBirthDate' => ['required', 'date_format:Y-m-d'],
                ];
            case Application::TYPE_CHILD_REMOVAL:
                return [
                    'relationships.child.data.type' => ['required', 'in:children'],
                    'relationships.child.data.id' => ['required', 'integer'],
                ];
            case Application::TYPE_ABSENCE:
                // Indefinida: sin fechas, hasta que el trabajador se las ponga o la quite (docs/09 §38).
                $indefinite = request()->json('data.attributes.indefinite') === true;

                return array_merge($relationship('absenceType', 'absence-types', 'absence_types'), [
                    'attributes.indefinite' => ['sometimes', 'boolean'],
                    'attributes.startsOn' => $indefinite ? ['sometimes', 'nullable', 'in:'] : ['required', 'date_format:Y-m-d'],
                    'attributes.endsOn' => $indefinite ? ['sometimes', 'nullable', 'in:'] : ['required', 'date_format:Y-m-d', 'after_or_equal:data.attributes.startsOn'],
                    'attributes.observation' => ['sometimes', 'nullable', 'string', 'max:1000'],
                ]);
            default:
                return [];
        }
    }
}
