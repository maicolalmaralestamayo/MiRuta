<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Absence;
use App\Models\Worker;
use App\Services\Permissions;
use Carbon\Carbon;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

/**
 * Ausencias sin aprobación (docs/11 §11.12): las declara, edita y quita la
 * propia persona (en cada pertenencia), o quien tenga absences.manage. Las
 * de otros se consultan con absences.view.
 *
 * Atributos: startsOn, endsOn (o indefinite), note; relaciones: worker
 * (si pertenece a varias Entidades) y absenceType.
 */
class AbsenceController extends Controller
{
    const SORTABLE = ['startsOn' => 'starts_on', 'createdAt' => 'created_at', 'id' => 'id'];

    const INCLUDABLE = ['worker', 'worker.user', 'absenceType'];

    /** @var Permissions */
    private $permissions;

    public function __construct(Permissions $permissions)
    {
        $this->permissions = $permissions;
    }

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, self::SORTABLE, ['worker', 'entity', 'itinerary', 'user', 'mine', 'on'], self::INCLUDABLE, '-startsOn');
        $query = $this->visible($request);

        if ($worker = $parameters->filter('worker')) {
            $query->where('worker_id', $worker);
        }

        foreach (['entity' => 'entity_id', 'itinerary' => 'itinerary_id', 'user' => 'user_id'] as $filter => $column) {
            if ($value = $parameters->filter($filter)) {
                $query->whereIn('worker_id', Worker::withTrashed()->where($column, $value)->select('id'));
            }
        }

        if ($parameters->filter('mine') === 'true') {
            $query->whereIn('worker_id', Worker::withTrashed()->where('user_id', $request->user()->id)->select('id'));
        }

        if ($on = $parameters->filter('on')) {
            $query->covering(Carbon::parse($on));
        }

        $paginator = $parameters->applySort($query, self::SORTABLE)
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator, $parameters->includes()));
    }

    public function show(Request $request, $id)
    {
        return JsonApiResponse::make((new Document($request))->resource($this->visible($request)->findOrFail($id), QueryParameters::readIncludes($request, self::INCLUDABLE)));
    }

    public function store(Request $request)
    {
        $data = $this->validateResource($request, 'absences', $this->rules(true));
        $worker = $this->workerFor($request, $data);
        $this->authorizeManage($request, $worker);
        $absence = new Absence(['worker_id' => $worker->id]);
        $this->fill($absence, $data, true);
        $absence->save();

        return JsonApiResponse::make((new Document($request))->resource($absence->fresh()), 201, ['Location' => url('api/v1/absences/'.$absence->id)]);
    }

    public function update(Request $request, $id)
    {
        $absence = Absence::findOrFail($id);
        $this->authorizeManage($request, Worker::withTrashed()->findOrFail($absence->worker_id));
        $data = $this->validateResource($request, 'absences', $this->rules(false));
        $this->fill($absence, $data, false);
        $absence->save();

        return JsonApiResponse::make((new Document($request))->resource($absence->fresh()));
    }

    public function destroy(Request $request, $id)
    {
        $absence = Absence::findOrFail($id);
        $this->authorizeManage($request, Worker::withTrashed()->findOrFail($absence->worker_id));
        $absence->delete();

        return response('', 204);
    }

    private function rules(bool $creating): array
    {
        $presence = $creating ? 'required' : 'sometimes';

        return [
            'attributes.startsOn' => ['sometimes', 'nullable', 'date_format:Y-m-d'],
            'attributes.endsOn' => ['sometimes', 'nullable', 'date_format:Y-m-d'],
            'attributes.indefinite' => ['sometimes', 'boolean'],
            'attributes.note' => ['sometimes', 'nullable', 'string', 'max:1000'],
            'relationships.worker.data.type' => ['sometimes', 'in:workers'],
            'relationships.worker.data.id' => ['sometimes', 'integer'],
            'relationships.absenceType.data.type' => [$presence, 'in:absence-types'],
            'relationships.absenceType.data.id' => [$presence, 'exists:absence_types,id,deleted_at,NULL'],
        ];
    }

    private function fill(Absence $absence, array $data, bool $creating): void
    {
        $attributes = isset($data['attributes']) ? $data['attributes'] : [];

        if (isset($data['relationships']['absenceType']['data']['id'])) {
            $absence->absence_type_id = (int) $data['relationships']['absenceType']['data']['id'];
        }

        if (array_key_exists('indefinite', $attributes)) {
            $absence->indefinite = (bool) $attributes['indefinite'];
        }

        if (array_key_exists('startsOn', $attributes) && $attributes['startsOn'] !== null) {
            $absence->starts_on = $attributes['startsOn'];
        } elseif ($creating) {
            $absence->starts_on = Carbon::today()->toDateString();
        }

        if (array_key_exists('endsOn', $attributes)) {
            $absence->ends_on = $attributes['endsOn'];
        }

        if ($absence->indefinite) {
            $absence->ends_on = null;
        } elseif ($absence->ends_on === null) {
            // Sin fecha de fin, es indefinida.
            $absence->indefinite = true;
        }

        if (array_key_exists('note', $attributes)) {
            $absence->note = $attributes['note'];
        }

        if ($absence->ends_on !== null && Carbon::parse($absence->ends_on)->lt(Carbon::parse($absence->starts_on))) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Fechas no válidas', 'La fecha de fin no puede ser anterior a la de inicio.', ['pointer' => '/data/attributes/endsOn']);
        }
    }

    /**
     * La pertenencia indicada o, si pertenece a una sola Entidad, la suya.
     */
    private function workerFor(Request $request, array $data): Worker
    {
        $user = $request->user();

        if (isset($data['relationships']['worker']['data']['id'])) {
            $worker = Worker::find($data['relationships']['worker']['data']['id']);
        } else {
            $workers = $user->activeWorkers();
            $worker = $workers->count() === 1 ? $workers->first() : null;
        }

        if (! $worker) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Falta la pertenencia', 'Indique en qué Entidad declara la ausencia (relationships.worker).', ['pointer' => '/data/relationships/worker']);
        }

        return $worker;
    }

    private function authorizeManage(Request $request, Worker $worker): void
    {
        $user = $request->user();

        if ((int) $worker->user_id !== (int) $user->id) {
            $this->permissions->authorize($user, 'absences.manage', (int) $worker->entity_id, $worker->itinerary_id ? (int) $worker->itinerary_id : null);
        }
    }

    private function visible(Request $request): Builder
    {
        $user = $request->user();
        $query = Absence::query();
        $view = $this->permissions->scope($user, 'absences.view');
        $manage = $this->permissions->scope($user, 'absences.manage');

        if ($view['all'] || $manage['all']) {
            return $query;
        }

        $entities = array_merge($view['entities'], $manage['entities']);
        $itineraries = array_merge($view['itineraries'], $manage['itineraries']);
        $workers = Worker::withTrashed()->select('id')->where(function ($query) use ($user, $entities, $itineraries) {
            $query->where('user_id', $user->id)
                ->orWhereIn('entity_id', $entities ?: [0])
                ->orWhereIn('itinerary_id', $itineraries ?: [0]);
        });

        return $query->whereIn('worker_id', $workers);
    }
}
