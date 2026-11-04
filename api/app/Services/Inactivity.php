<?php

namespace App\Services;

use App\Models\Absence;
use App\Models\Itinerary;
use App\Models\Notice;
use App\Models\Trip;
use App\Models\Worker;
use Carbon\Carbon;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;

/**
 * Baja automática por inactividad (docs/07-algoritmos.md §7.26).
 */
class Inactivity
{
    /** @var Settings */
    private $settings;

    /** @var Notices */
    private $notices;

    public function __construct(Settings $settings, Notices $notices)
    {
        $this->settings = $settings;
        $this->notices = $notices;
    }

    /**
     * @return array [avisados, dados de baja]
     */
    public function run(): array
    {
        $warned = 0;
        $removed = 0;

        foreach (Worker::whereNotNull('itinerary_id')->get() as $worker) {
            // Los plazos son los de su itinerario (o su Entidad).
            $limit = $this->settings->int('inactivity_days', null, (int) $worker->entity_id, (int) $worker->itinerary_id);
            $warningDays = $this->settings->int('inactivity_warning_days', null, (int) $worker->entity_id, (int) $worker->itinerary_id);
            $since = $this->since($worker);
            $counted = $this->countedDays($worker, $since);

            if ($counted >= $limit) {
                $this->remove($worker);
                $removed++;
            } elseif ($warningDays > 0 && $counted === $limit - $warningDays && ! $this->alreadyWarned($worker, $since)) {
                $this->notices->send([(int) $worker->user_id], Notice::TYPE_INACTIVITY_WARNING, null, null, null, $this->payload($worker));
                $warned++;
            }
        }

        return [$warned, $removed];
    }

    /**
     * Días contados desde $since: días en que el itinerario tuvo viajes
     * realizados y el trabajador no tenía una ausencia declarada.
     */
    public function countedDays(Worker $worker, CarbonImmutable $since): int
    {
        $days = Trip::where('itinerary_id', $worker->itinerary_id)
            ->where('status', Trip::STATUS_COMPLETED)
            ->where('departs_at', '>', $since)
            ->where('departs_at', '<=', Carbon::now())
            ->get(['departs_at'])
            ->map(function (Trip $trip) {
                return $trip->departs_at->toDateString();
            })
            ->unique()
            ->values()
            ->all();

        $absences = Absence::where('worker_id', $worker->id)->get();

        // Los días en que condujo un viaje realizado tampoco cuentan.
        $driven = $this->drivenDays($worker, $since);

        return count(array_filter($days, function (string $day) use ($absences, $driven) {
            if (in_array($day, $driven, true)) {
                return false;
            }

            foreach ($absences as $absence) {
                if ($absence->covers($day)) {
                    return false;
                }
            }

            return true;
        }));
    }

    /**
     * La más reciente entre su última subida en un viaje realizado de su
     * itinerario y la fecha en que entró en él.
     */
    public function since(Worker $worker): CarbonImmutable
    {
        $lastBoarding = DB::table('trip_boardings')
            ->join('trip_legs', 'trip_legs.id', '=', 'trip_boardings.trip_leg_id')
            ->join('trips', 'trips.id', '=', 'trip_legs.trip_id')
            ->where('trip_boardings.worker_id', $worker->id)
            ->where('trips.itinerary_id', $worker->itinerary_id)
            ->where('trips.status', Trip::STATUS_COMPLETED)
            ->max('trips.departs_at');

        $joined = $worker->itinerary_assigned_at ? (string) $worker->itinerary_assigned_at : null;

        // Conducir un viaje realizado también es actividad.
        $lastDriven = DB::table('trips')
            ->where('trips.driver_id', $worker->id)
            ->where('trips.status', Trip::STATUS_COMPLETED)
            ->where('trips.departs_at', '<=', Carbon::now())
            ->max('trips.departs_at');

        $candidates = array_filter([$lastBoarding, $lastDriven, $joined, (string) $worker->created_at]);

        return CarbonImmutable::parse(max($candidates));
    }

    /**
     * @return string[] días (Y-m-d) en que condujo un viaje realizado
     */
    private function drivenDays(Worker $worker, CarbonImmutable $since): array
    {
        return DB::table('trips')
            ->where('trips.driver_id', $worker->id)
            ->where('trips.status', Trip::STATUS_COMPLETED)
            ->where('trips.departs_at', '>', $since)
            ->pluck('trips.departs_at')
            ->map(function ($date) {
                return Carbon::parse($date)->toDateString();
            })->unique()->values()->all();
    }

    private function alreadyWarned(Worker $worker, CarbonImmutable $since): bool
    {
        return Notice::where('user_id', $worker->user_id)
            ->where('type', Notice::TYPE_INACTIVITY_WARNING)
            ->where('created_at', '>', $since)
            ->exists();
    }

    private function remove(Worker $worker): void
    {
        DB::transaction(function () use ($worker) {
            $payload = $this->payload($worker) + ['person' => $worker->fullName()];
            $itineraryId = (int) $worker->itinerary_id;

            $worker->forceFill(['itinerary_id' => null, 'stop_id' => null, 'itinerary_assigned_at' => null])->save();
            app(Permissions::class)->flush((int) $worker->user_id);

            $this->notices->send(
                array_merge([(int) $worker->user_id], app(Permissions::class)->userIdsWith('members.approve', (int) $worker->entity_id, $itineraryId, false)),
                Notice::TYPE_INACTIVITY_REMOVAL,
                null,
                null,
                null,
                $payload
            );
        });
    }

    private function payload(Worker $worker): array
    {
        $itinerary = $worker->itinerary_id ? Itinerary::withTrashed()->find($worker->itinerary_id) : null;

        return ['itinerary' => $itinerary ? $itinerary->name : null, 'entity' => $worker->entity ? $worker->entity->abbreviation : null];
    }
}
