<?php

namespace App\Services;

use App\Models\Application;
use Carbon\CarbonInterface;
use Illuminate\Support\Facades\DB;

/**
 * Ausencias aprobadas.
 */
class Absences
{
    /**
     * Trabajadores con una ausencia aprobada que incluye la fecha.
     *
     * @param int[]|null $workerIds para limitar la búsqueda
     * @return int[]
     */
    public function absentOn(CarbonInterface $date, ?array $workerIds = null): array
    {
        $query = DB::table('absence_applications')
            ->join('applications', 'applications.id', '=', 'absence_applications.application_id')
            ->where('applications.type', Application::TYPE_ABSENCE)
            ->where('applications.status', Application::STATUS_APPROVED)
            ->whereNull('applications.deleted_at')
            ->where('absence_applications.starts_on', '<=', $date->toDateString())
            ->where('absence_applications.ends_on', '>=', $date->toDateString());

        if ($workerIds !== null) {
            $query->whereIn('applications.worker_id', $workerIds);
        }

        return array_map('intval', $query->distinct()->pluck('applications.worker_id')->all());
    }

    public function isAbsent(int $workerId, CarbonInterface $date): bool
    {
        return in_array($workerId, $this->absentOn($date, [$workerId]), true);
    }
}
