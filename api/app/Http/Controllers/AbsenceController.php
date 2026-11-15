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
use Illuminate\Support\Facades\DB;

/**
 * Ausencias, sin aprobación (docs/11 §11.12 y §11.61): las declara la propia
 * persona para uno o varios de sus itinerarios (de cualquiera de sus
 * Entidades), con su tipo y fechas; sin fecha final es indefinida y dura hasta
 * que la termine («Terminar ausencia»: PATCH con endsOn). Durante la ausencia
 * no cuenta como pasajero esperado en los viajes de esos itinerarios. El
 * Administrador (y el Jefe, en su itinerario) las ven y también pueden
 * declararlas.
 *
 * - relationships.user: la persona (por omisión, quien la declara).
 * - relationships.itineraries: [{type: itineraries, id}, …] (por omisión,
 *   todos sus itinerarios).
 * - relationships.worker (4.1.0): todos sus itinerarios en esa Entidad.
 */
class AbsenceController extends Controller
{
    public const SORTABLE = ['id' => 'id', 'startsOn' => 'starts_on'];
    public const INCLUDABLE = ['user', 'absenceType'];

    public function __construct(private Access $access)
    {
    }

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, self::SORTABLE, ['worker', 'user', 'itinerary', 'current'], self::INCLUDABLE, '-startsOn');
        $query = $this->visible($request->user());

        if ($worker = $parameters->filter('worker')) {
            $query->where('worker_id', (int) $worker);
        }

        if ($user = $parameters->filter('user')) {
            $query->where('user_id', (int) $user);
        }

        if ($itinerary = $parameters->filter('itinerary')) {
            $query->whereIn('id', DB::table('absence_itinerary')->where('itinerary_id', (int) $itinerary)->select('absence_id'));
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
            + $this->relationshipRules('user', 'users', 'users', false)
            + $this->relationshipRules('worker', 'workers', 'workers', false)
            + $this->relationshipRules('absenceType', 'absence-types', 'absence_types', true)
            + $this->itineraryRules());
        $actor = $request->user();
        $workerId = $this->relationshipId($data, 'worker');
        $userId = $this->relationshipId($data, 'user') ?? ($workerId ? (int) Worker::findOrFail($workerId)->user_id : (int) $actor->id);
        $itineraryIds = $this->requestedItineraries($data, $userId, $workerId) ?? $this->itinerariesOf($userId);
        $this->checkItineraries($actor, $userId, $itineraryIds);

        $absence = new Absence(['user_id' => $userId]);
        $this->fill($absence, $data);

        DB::transaction(function () use ($absence, $itineraryIds) {
            $absence->save();
            $absence->itineraries()->sync($itineraryIds);
        });

        return $this->created($request, $absence->fresh(), 'absences');
    }

    public function update(Request $request, $id)
    {
        $absence = $this->visible($request->user())->findOrFail($id);
        $actor = $request->user();
        $this->checkItineraries($actor, (int) $absence->user_id, $absence->itineraryIds(), false);
        $data = $this->validateResource($request, 'absences', $this->rules(false)
            + $this->relationshipRules('absenceType', 'absence-types', 'absence_types', false)
            + $this->itineraryRules());
        $itineraryIds = $this->requestedItineraries($data, (int) $absence->user_id, null);

        if ($itineraryIds !== null) {
            $this->checkItineraries($actor, (int) $absence->user_id, $itineraryIds);
        }

        $this->fill($absence, $data);

        DB::transaction(function () use ($absence, $itineraryIds) {
            $absence->save();

            if ($itineraryIds !== null) {
                $absence->itineraries()->sync($itineraryIds);
            }
        });

        return $this->respond($request, $absence->fresh());
    }

    public function destroy(Request $request, $id)
    {
        $absence = $this->visible($request->user())->findOrFail($id);
        $this->checkItineraries($request->user(), (int) $absence->user_id, $absence->itineraryIds(), false);
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

    private function itineraryRules(): array
    {
        return [
            'relationships.itineraries' => ['sometimes', 'array'],
            'relationships.itineraries.data' => ['present_with:data.relationships.itineraries', 'array'],
            'relationships.itineraries.data.*.type' => ['required', 'in:itineraries'],
            'relationships.itineraries.data.*.id' => ['required', 'exists:itineraries,id'],
        ];
    }

    /**
     * Itinerarios pedidos (null si no se indican). Con la pertenencia de la
     * 4.1.0 (worker), todos sus itinerarios en esa Entidad.
     *
     * @return int[]|null
     */
    private function requestedItineraries(array $data, int $userId, ?int $workerId): ?array
    {
        if (isset($data['relationships']['itineraries']['data'])) {
            return array_values(array_unique(array_map(fn ($r) => (int) $r['id'], $data['relationships']['itineraries']['data'])));
        }

        if ($workerId !== null) {
            return WorkerItinerary::where('worker_id', $workerId)->where('user_id', $userId)->pluck('itinerary_id')->map(fn ($id) => (int) $id)->all();
        }

        return null;
    }

    /** @return int[] */
    private function itinerariesOf(int $userId): array
    {
        return WorkerItinerary::where('user_id', $userId)->pluck('itinerary_id')->map(fn ($id) => (int) $id)->all();
    }

    /**
     * Itinerarios de la persona y permiso de quien declara: la propia persona,
     * el Administrador o el Jefe (solo en su itinerario).
     *
     * @param int[] $itineraryIds
     */
    private function checkItineraries(User $actor, int $userId, array $itineraryIds, bool $validate = true): void
    {
        if ($validate) {
            if (! $itineraryIds) {
                throw new JsonApiException(422, 'ABSENCE_WITHOUT_ITINERARY', 'Sin itinerarios', 'Marque al menos uno de sus itinerarios.', ['pointer' => '/data/relationships/itineraries']);
            }

            $mine = $this->itinerariesOf($userId);

            if (array_diff($itineraryIds, $mine)) {
                throw new JsonApiException(422, 'ITINERARY_NOT_MINE', 'Itinerario no válido', 'Solo se declaran ausencias en los itinerarios de la persona.', ['pointer' => '/data/relationships/itineraries']);
            }
        }

        if ($userId === (int) $actor->id || $this->access->isAdmin($actor)) {
            return;
        }

        $chiefOf = $this->access->chiefItineraryId($actor);

        if ($chiefOf === null || ! in_array($chiefOf, $itineraryIds, true) || ($validate && array_diff($itineraryIds, [$chiefOf]))) {
            throw Access::forbidden('Cada uno declara sus ausencias (o el Administrador, o el Jefe en su itinerario).');
        }
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

        if (! $absence->absence_type_id) {
            throw new JsonApiException(422, 'ABSENCE_TYPE_INVALID', 'Tipo no válido', 'Elija un tipo de ausencia activo.', ['pointer' => '/data/relationships/absenceType']);
        }

        if ($absence->ends_on && $absence->starts_on && Carbon::parse($absence->ends_on)->lt(Carbon::parse($absence->starts_on))) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Fechas no válidas', 'La fecha final no puede ser anterior a la inicial.', ['pointer' => '/data/attributes/endsOn']);
        }
    }

    private function visible(User $user): Builder
    {
        $query = Absence::query();

        if ($this->access->isAdmin($user)) {
            return $query;
        }

        $chiefOf = $this->access->chiefItineraryId($user);

        return $query->where(fn ($q) => $q->where('user_id', $user->id)
            ->when($chiefOf !== null, fn ($q) => $q->orWhereIn('id', DB::table('absence_itinerary')->where('itinerary_id', $chiefOf)->select('absence_id'))));
    }
}
