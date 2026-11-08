<?php

namespace App\Services;

use App\Models\Child;
use Carbon\CarbonImmutable;

/**
 * Derecho de los hijos a viajar (docs/11 §11.11): hasta el 31 de agosto
 * siguiente al cumpleaños en que alcanza la edad del ajuste «Edad hijos».
 */
class ChildEligibility
{
    public function __construct(private Settings $settings)
    {
    }

    /**
     * Último día con derecho a viajar.
     */
    public function eligibleUntil($birthDate): CarbonImmutable
    {
        $birth = CarbonImmutable::parse($birthDate)->startOfDay();
        $limitYear = $birth->year + $this->settings->int('edad_hijos');

        // 29 de febrero en un año no bisiesto → 28 de febrero
        $limit = $birth->month === 2 && $birth->day === 29 && ! checkdate(2, 29, $limitYear)
            ? CarbonImmutable::create($limitYear, 2, 28)
            : CarbonImmutable::create($limitYear, $birth->month, $birth->day);

        $endOfCourse = CarbonImmutable::create($limit->year, 8, 31);

        return $limit->lessThanOrEqualTo($endOfCourse) ? $endOfCourse : $endOfCourse->addYear();
    }

    public function isEligible($birthDate, ?CarbonImmutable $date = null): bool
    {
        $date = $date ?: CarbonImmutable::today();

        return $date->startOfDay()->lessThanOrEqualTo($this->eligibleUntil($birthDate));
    }

    /**
     * Hijos activos con derecho a viajar de esa persona.
     *
     * @return \Illuminate\Support\Collection<int, Child>
     */
    public function eligibleChildrenOf(int $userId, ?CarbonImmutable $date = null)
    {
        return Child::ofParent($userId)->where('active', true)->get()
            ->filter(fn (Child $child) => $this->isEligible($child->birth_date, $date))
            ->values();
    }
}
