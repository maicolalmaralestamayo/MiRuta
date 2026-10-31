<?php

namespace App\Services;

use App\Models\Child;
use App\Models\Worker;
use Carbon\CarbonImmutable;

/**
 * Derecho a viajar de un hijo (docs/07-algoritmos.md §7.9): hasta el 31 de
 * agosto siguiente al día en que cumple la edad máxima.
 */
class ChildEligibility
{
    /** @var Settings */
    private $settings;

    public function __construct(Settings $settings)
    {
        $this->settings = $settings;
    }

    /**
     * Último día con derecho a viajar: el 31 de agosto siguiente a cumplir
     * la edad máxima de su Entidad (child_max_age).
     */
    public function eligibleUntil($birthDate, ?int $entityId): CarbonImmutable
    {
        $birth = CarbonImmutable::parse($birthDate)->startOfDay();
        $limitYear = $birth->year + $this->settings->int('child_max_age', null, $entityId);

        // 29 de febrero en un año no bisiesto → 28 de febrero
        $limit = $birth->month === 2 && $birth->day === 29 && ! checkdate(2, 29, $limitYear)
            ? CarbonImmutable::create($limitYear, 2, 28)
            : CarbonImmutable::create($limitYear, $birth->month, $birth->day);

        $endOfCourse = CarbonImmutable::create($limit->year, 8, 31);

        return $limit->lessThanOrEqualTo($endOfCourse) ? $endOfCourse : $endOfCourse->addYear();
    }

    public function isEligible($birthDate, ?int $entityId, ?CarbonImmutable $date = null): bool
    {
        $date = $date ?: CarbonImmutable::today();

        return $date->startOfDay()->lessThanOrEqualTo($this->eligibleUntil($birthDate, $entityId));
    }

    public function isChildEligible(Child $child, ?CarbonImmutable $date = null): bool
    {
        return $this->isEligible($child->birth_date, $this->entityOf($child->worker_id), $date);
    }

    public function childEligibleUntil(Child $child): CarbonImmutable
    {
        return $this->eligibleUntil($child->birth_date, $this->entityOf($child->worker_id));
    }

    /**
     * Hijos declarados con derecho a viajar en la fecha indicada.
     */
    public function eligibleCount(Worker $worker, ?CarbonImmutable $date = null): int
    {
        return $this->eligibleCountsByWorker([$worker->id], $date)[$worker->id] ?? 0;
    }

    /**
     * @param int[] $workerIds
     * @return array [id de trabajador => hijos con derecho]
     */
    public function eligibleCountsByWorker(array $workerIds, ?CarbonImmutable $date = null): array
    {
        $counts = array_fill_keys($workerIds, 0);

        if (! $workerIds) {
            return $counts;
        }

        $entities = Worker::withTrashed()->whereIn('id', $workerIds)->pluck('entity_id', 'id')->all();

        foreach (Child::declared()->whereIn('worker_id', $workerIds)->get() as $child) {
            $entityId = isset($entities[$child->worker_id]) ? (int) $entities[$child->worker_id] : null;

            if ($this->isEligible($child->birth_date, $entityId, $date)) {
                $counts[$child->worker_id]++;
            }
        }

        return $counts;
    }

    private function entityOf($workerId): ?int
    {
        $entityId = Worker::withTrashed()->whereKey($workerId)->value('entity_id');

        return $entityId === null ? null : (int) $entityId;
    }
}
