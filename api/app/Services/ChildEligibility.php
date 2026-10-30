<?php

namespace App\Services;

use App\Models\Child;
use App\Models\Worker;
use App\Support\CardNumber;
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

    public function eligibleUntil(CardNumber $card): CarbonImmutable
    {
        $birth = $card->birthDate();
        $limitYear = $birth->year + $this->settings->int('child_max_age');

        // 29 de febrero en un año no bisiesto → 28 de febrero
        $limit = $birth->month === 2 && $birth->day === 29 && ! checkdate(2, 29, $limitYear)
            ? CarbonImmutable::create($limitYear, 2, 28)
            : CarbonImmutable::create($limitYear, $birth->month, $birth->day);

        $endOfCourse = CarbonImmutable::create($limit->year, 8, 31);

        return $limit->lessThanOrEqualTo($endOfCourse) ? $endOfCourse : $endOfCourse->addYear();
    }

    public function isEligible(CardNumber $card, ?CarbonImmutable $date = null): bool
    {
        $date = $date ?: CarbonImmutable::today();

        return $date->startOfDay()->lessThanOrEqualTo($this->eligibleUntil($card));
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

        foreach (Child::declared()->whereIn('worker_id', $workerIds)->get() as $child) {
            if ($this->isEligible($child->cardNumber(), $date)) {
                $counts[$child->worker_id]++;
            }
        }

        return $counts;
    }
}
