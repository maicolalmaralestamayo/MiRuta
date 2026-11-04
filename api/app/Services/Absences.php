<?php

namespace App\Services;

use App\Models\Absence;
use Carbon\CarbonInterface;

/**
 * Ausencias declaradas (sin aprobación, docs/11 §11.12).
 */
class Absences
{
    /**
     * Pertenencias con una ausencia que incluye la fecha.
     *
     * @param int[]|null $workerIds para limitar la búsqueda
     * @return int[]
     */
    public function absentOn(CarbonInterface $date, ?array $workerIds = null): array
    {
        $query = Absence::covering($date);

        if ($workerIds !== null) {
            $query->whereIn('worker_id', $workerIds);
        }

        return array_map('intval', $query->distinct()->pluck('worker_id')->all());
    }

    public function isAbsent(int $workerId, CarbonInterface $date): bool
    {
        return in_array($workerId, $this->absentOn($date, [$workerId]), true);
    }
}
