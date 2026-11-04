<?php

namespace App\Services;

use App\Models\Child;
use App\Models\ChildParent;
use App\Models\Worker;
use Carbon\CarbonImmutable;

/**
 * Derecho a viajar de un hijo (docs/07-algoritmos.md §7.9 y docs/11 §11.11):
 * hasta el 31 de agosto siguiente al cumpleaños en que cumple la edad máxima
 * (child_max_age). La edad máxima es la de la Entidad de sus padres o, si
 * pertenecen a varias (o a ninguna), la de la app.
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
     * Último día con derecho a viajar.
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

    /**
     * Entidad con la que se calcula: la única de sus padres, o null (la app).
     *
     * @param int[] $parentIds
     */
    public function entityForParents(array $parentIds): ?int
    {
        if (! $parentIds) {
            return null;
        }

        $entities = Worker::whereIn('user_id', $parentIds)->distinct()->pluck('entity_id')->all();

        return count($entities) === 1 ? (int) $entities[0] : null;
    }

    public function childEntityId(Child $child): ?int
    {
        return $this->entityForParents($child->parentIds());
    }

    public function isChildEligible(Child $child, ?CarbonImmutable $date = null): bool
    {
        return $this->isEligible($child->birth_date, $this->childEntityId($child), $date);
    }

    public function childEligibleUntil(Child $child): CarbonImmutable
    {
        return $this->eligibleUntil($child->birth_date, $this->childEntityId($child));
    }

    /**
     * Hijos activos con derecho a viajar de esa persona.
     *
     * @return \Illuminate\Support\Collection|Child[]
     */
    public function eligibleChildrenOf(int $userId, ?CarbonImmutable $date = null)
    {
        return Child::ofParent($userId)->where('active', true)->get()->filter(function (Child $child) use ($date) {
            return $this->isChildEligible($child, $date);
        })->values();
    }

    /**
     * Hijos con derecho de la persona de la pertenencia.
     */
    public function eligibleCount(Worker $worker, ?CarbonImmutable $date = null): int
    {
        return $this->eligibleChildrenOf((int) $worker->user_id, $date)->count();
    }

    /**
     * @param int[] $workerIds
     * @return array [id de pertenencia => hijos con derecho]
     */
    public function eligibleCountsByWorker(array $workerIds, ?CarbonImmutable $date = null): array
    {
        $counts = array_fill_keys($workerIds, 0);

        if (! $workerIds) {
            return $counts;
        }

        $users = Worker::withTrashed()->whereIn('id', $workerIds)->pluck('user_id', 'id')->all();
        $byUser = [];

        foreach (array_unique($users) as $userId) {
            $byUser[$userId] = $this->eligibleChildrenOf((int) $userId, $date)->count();
        }

        foreach ($users as $workerId => $userId) {
            $counts[$workerId] = $byUser[$userId];
        }

        return $counts;
    }

    /**
     * Ids de las personas que tienen declarado al niño.
     *
     * @return int[]
     */
    public function parentIds(Child $child): array
    {
        return array_map('intval', ChildParent::where('child_id', $child->id)->pluck('user_id')->all());
    }
}
