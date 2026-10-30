<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Application;
use App\Rules\CardNumberRule;
use App\Services\Applications;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

class ApplicationController extends Controller
{
    const SORTABLE = ['createdAt' => 'created_at', 'resolvedAt' => 'resolved_at', 'id' => 'id'];

    const FILTERABLE = ['status', 'type', 'mine', 'toResolve', 'worker'];

    const INCLUDABLE = ['worker', 'resolvedBy', 'itinerary', 'stop', 'rank', 'child', 'absenceType'];

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
        $query = $this->applications->visibleTo($user)->with('itineraryApplication', 'rankApplication', 'childApplication.child', 'absenceApplication');

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
            $query->where('worker_id', $user->id);
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
            ['attributes.type' => ['required', 'in:'.implode(',', $this->creatableTypes())]],
            $this->rulesFor(is_string($type) ? $type : '')
        ));

        $application = $this->applications->create($request->user(), $data);

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
        $data = $this->validateResource($request, 'applications', [
            'attributes.status' => ['required', 'in:approved,rejected,cancelled'],
            'attributes.resolutionNote' => ['sometimes', 'nullable', 'string', 'max:1000'],
        ]);
        $user = $request->user();
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
            Application::TYPE_TRANSPORT_CHIEF, Application::TYPE_RANK_CHANGE, Application::TYPE_CHILD_ADDITION,
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
            case Application::TYPE_RANK_CHANGE:
                return $relationship('rank', 'ranks', 'ranks');
            case Application::TYPE_CHILD_ADDITION:
                return [
                    'attributes.childFirstName' => ['required', 'string', 'max:100'],
                    'attributes.childLastName' => ['required', 'string', 'max:150'],
                    'attributes.childCardNumber' => ['required', 'string', new CardNumberRule()],
                ];
            case Application::TYPE_CHILD_REMOVAL:
                return [
                    'relationships.child.data.type' => ['required', 'in:children'],
                    'relationships.child.data.id' => ['required', 'integer'],
                ];
            case Application::TYPE_ABSENCE:
                return array_merge($relationship('absenceType', 'absence-types', 'absence_types'), [
                    'attributes.startsOn' => ['required', 'date_format:Y-m-d'],
                    'attributes.endsOn' => ['required', 'date_format:Y-m-d', 'after_or_equal:data.attributes.startsOn'],
                    'attributes.observation' => ['sometimes', 'nullable', 'string', 'max:1000'],
                ]);
            default:
                return [];
        }
    }
}
