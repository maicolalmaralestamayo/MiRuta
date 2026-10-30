<?php

namespace App\Services;

use App\Models\Application;
use App\Models\ItineraryApplication;
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
        $limit = $this->settings->int('inactivity_days');
        $warningDays = $this->settings->int('inactivity_warning_days');
        $warned = 0;
        $removed = 0;

        foreach (Worker::whereNotNull('itinerary_id')->get() as $worker) {
            $since = $this->since($worker);
            $counted = $this->countedDays($worker, $since);

            if ($counted >= $limit) {
                $this->remove($worker);
                $removed++;
            } elseif ($warningDays > 0 && $counted === $limit - $warningDays && ! $this->alreadyWarned($worker, $since)) {
                $this->notices->send([$worker->id], Notice::TYPE_INACTIVITY_WARNING);
                $warned++;
            }
        }

        return [$warned, $removed];
    }

    /**
     * Días contados desde $since: días en que el itinerario tuvo viajes
     * realizados y el trabajador no tenía una ausencia aprobada.
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

        $absences = DB::table('absence_applications')
            ->join('applications', 'applications.id', '=', 'absence_applications.application_id')
            ->where('applications.worker_id', $worker->id)
            ->where('applications.type', Application::TYPE_ABSENCE)
            ->where('applications.status', Application::STATUS_APPROVED)
            ->get(['starts_on', 'ends_on']);

        return count(array_filter($days, function (string $day) use ($absences) {
            foreach ($absences as $absence) {
                if ($day >= $absence->starts_on && $day <= $absence->ends_on) {
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

        $joined = Application::where('worker_id', $worker->id)
            ->whereIn('type', [Application::TYPE_ITINERARY_MEMBERSHIP, Application::TYPE_ITINERARY_CHIEF])
            ->where('status', Application::STATUS_APPROVED)
            ->whereHas('itineraryApplication', function ($query) use ($worker) {
                $query->where('itinerary_id', $worker->itinerary_id);
            })
            ->max('resolved_at');

        $candidates = array_filter([$lastBoarding, $joined, (string) $worker->created_at]);

        return CarbonImmutable::parse(max($candidates));
    }

    private function alreadyWarned(Worker $worker, CarbonImmutable $since): bool
    {
        return Notice::where('worker_id', $worker->id)
            ->where('type', Notice::TYPE_INACTIVITY_WARNING)
            ->where('created_at', '>', $since)
            ->exists();
    }

    private function remove(Worker $worker): void
    {
        DB::transaction(function () use ($worker) {
            $itineraryId = (int) $worker->itinerary_id;
            $application = Application::create([
                'worker_id' => $worker->id,
                'type' => Application::TYPE_ITINERARY_REMOVAL,
                'status' => Application::STATUS_APPROVED,
                'resolved_at' => Carbon::now(),
            ]);
            ItineraryApplication::create(['application_id' => $application->id, 'itinerary_id' => $itineraryId, 'stop_id' => $worker->stop_id]);

            $worker->itinerary_id = null;
            $worker->stop_id = null;
            $worker->save();

            $this->notices->send(
                array_merge([(int) $worker->id], $this->notices->itineraryChiefIds($itineraryId)),
                Notice::TYPE_INACTIVITY_REMOVAL,
                $application->id
            );
        });
    }
}
