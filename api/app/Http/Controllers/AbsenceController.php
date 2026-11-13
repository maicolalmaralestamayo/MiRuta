<?php

namespace App\Http\Controllers;

use App\JsonApi\JsonApiException;
use App\JsonApi\QueryParameters;
use App\Models\Absence;
use App\Models\AbsenceType;
use App\Models\User;
use App\Models\Worker;
use App\Models\WorkerItinerary;
use App\Services\Access;
use Carbon\Carbon;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

/**
 * Ausencias, sin aprobación (docs/11 §11.12): las declara la propia persona
 * (en una de sus Entidades), con su tipo y fechas, o indefinida. Durante la
 * ausencia no cuenta como pasajero esperado. El Administrador y el Jefe (de su
 * itinerario) las ven y también pueden declararlas.
 */
class AbsenceController extends Controller
{
    public const SORTABLE = ['id' => 'id', 'startsOn' => 'starts_on'];
    public const INCLUDABLE = ['worker', 'absenceType'];

    public function __construct(private Access $access)
    {
    }

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, self::SORTABLE, ['worker', 'current'], self::INCLUDABLE, '-startsOn');
        $query = $this->visible($request->user());

        if ($worker = $parameters->filter('worker')) {
            $query->where('worker_id', (int) $worker);
        }

        if ($parameters->filter('current') === 'true') {
            $query->where(fn ($q) => $q->whereNull('ends_on')->orWhere('ends_on', '>=', Carbon::today()->toDateString()));
        }

        return $this->paginate($request, $query, $parameters, self::SORTABLE);
    }

    public function show(Request $request, $id)
    {
        return $this->respond($request, $this->visible($request->user())->findOrFail($id), QueryParameters::readIncludes($request, self::INCLUDABLE));
    }

    public function store(Request $request)
    {
        $data = $this->validateResource($request, 'absences', $this->rules(true)
            + $this->relationshipRules('worker', 'workers', 'workers', true)
            + $this->relationshipRules('absenceType', 'absence-types', 'absence_types', true));
        $worker = Worker::findOrFail($this->relationshipId($data, 'worker'));
        $this->authorizeFor($request->user(), $worker);
        $absence = new Absence(['worker_id' => $worker->id]);
        $this->fill($absence, $data);
        $absence->save();

        return $this->created($request, $absence->fresh(), 'absences');
    }

    public function update(Request $request, $id)
    {
        $absence = $this->visible($request->user())->findOrFail($id);
        $this->authorizeFor($request->user(), Worker::findOrFail($absence->worker_id));
        $data = $this->validateResource($request, 'absences', $this->rules(false)
            + $this->relationshipRules('absenceType', 'absence-types', 'absence_types', false));
        $this->fill($absence, $data);
        $absence->save();

        return $this->respond($request, $absence->fresh());
    }

    public function destroy(Request $request, $id)
    {
        $absence = $this->visible($request->user())->findOrFail($id);
        $this->authorizeFor($request->user(), Worker::findOrFail($absence->worker_id));
        $absence->delete();

        return $this->noContent();
    }

    private function rules(bool $creating): array
    {
        return [
            'attributes.startsOn' => [$creating ? 'required' : 'sometimes', 'date_format:Y-m-d'],
            'attributes.endsOn' => ['sometimes', 'nullable', 'date_format:Y-m-d'],
            'attributes.note' => ['sometimes', 'nullable', 'string', 'max:1000'],
        ];
    }

    private function fill(Absence $absence, array $data): void
    {
        $attributes = $data['attributes'] ?? [];

        foreach (['startsOn' => 'starts_on', 'endsOn' => 'ends_on'] as $attribute => $column) {
            if (array_key_exists($attribute, $attributes)) {
                $absence->{$column} = $attributes[$attribute];
            }
        }

        if (array_key_exists('note', $attributes)) {
            $absence->note = self::text($attributes['note']);
        }

        if (($typeId = $this->relationshipId($data, 'absenceType')) !== null) {
            if (! AbsenceType::where('id', $typeId)->where('active', true)->exists()) {
                throw new JsonApiException(422, 'ABSENCE_TYPE_INVALID', 'Tipo no válido', 'Elija un tipo de ausencia activo.', ['pointer' => '/data/relationships/absenceType']);
            }
            $absence->absence_type_id = $typeId;
        }

        if ($absence->ends_on && $absence->starts_on && $absence->ends_on->lt($absence->starts_on)) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Fechas no válidas', 'La fecha final no puede ser anterior a la inicial.', ['pointer' => '/data/attributes/endsOn']);
        }
    }

    private function authorizeFor(User $actor, Worker $worker): void
    {
        $allowed = (int) $worker->user_id === (int) $actor->id
            || $this->access->isAdmin($actor)
            || $this->chiefOfWorker($actor, $worker);

        if (! $allowed) {
            throw Access::forbidden('Cada uno declara sus ausencias (o el Administrador, o el Jefe de su itinerario).');
        }
    }

    /**
     * El actor es Jefe de alguno de los itinerarios de esa persona en esa Entidad.
     */
    private function chiefOfWorker(User $actor, Worker $worker): bool
    {
        $chiefOf = $this->access->chiefItineraryId($actor);

        return $chiefOf !== null && WorkerItinerary::where('worker_id', $worker->id)->where('itinerary_id', $chiefOf)->exists();
    }

    private function visible(User $user): Builder
    {
        $query = Absence::query();

        if ($this->access->isAdmin($user)) {
            return $query;
        }

        $chiefOf = $this->access->chiefItineraryId($user);

        return $query->where(fn ($q) => $q->whereIn('worker_id', Worker::where('user_id', $user->id)->select('id'))
            ->when($chiefOf !== null, fn ($q) => $q->orWhereIn('worker_id', WorkerItinerary::where('itinerary_id', $chiefOf)->select('worker_id'))));
    }
}
