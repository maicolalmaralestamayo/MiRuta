<?php

namespace App\Services;

use App\Models\Application;
use App\Models\Child;
use Illuminate\Database\Eloquent\Builder;

/**
 * Hijos sin carné: el posible duplicado se avisa a quien aprueba, sin
 * bloquear (docs/08-version-2.md §8.8).
 */
class Children
{
    /**
     * En la misma Entidad hay otro niño (declarado o pendiente) con la misma
     * fecha de nacimiento, primer nombre y primer apellido.
     */
    public function hasPossibleDuplicate(Child $child): bool
    {
        $entityId = $child->worker ? (int) $child->worker->entity_id : null;

        return Child::where('id', '<>', $child->id)
            ->whereDate('birth_date', $child->birth_date->toDateString())
            ->whereRaw('LOWER(first_name) = ?', [mb_strtolower($child->first_name, 'UTF-8')])
            ->whereRaw('LOWER(first_surname) = ?', [mb_strtolower($child->first_surname, 'UTF-8')])
            ->whereHas('worker', function (Builder $query) use ($entityId) {
                $query->where('entity_id', $entityId);
            })
            ->whereHas('childApplications.application', function (Builder $query) {
                $query->where('type', Application::TYPE_CHILD_ADDITION)
                    ->whereIn('status', [Application::STATUS_PENDING, Application::STATUS_APPROVED]);
            })
            ->exists();
    }
}
