<?php

namespace App\Http\Controllers;

use App\JsonApi\QueryParameters;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Roles vigentes. Se crean al aprobar solicitudes; aquí solo se consultan
 * (y se dan de baja, en los controladores concretos).
 */
abstract class RoleController extends ResourceController
{
    protected $filterable = ['worker'];

    protected $includable = ['worker'];

    protected function rules(Request $request, ?Model $model): array
    {
        return [];
    }

    protected function applyFilters(Builder $query, QueryParameters $parameters, Request $request): void
    {
        if ($worker = $parameters->filter('worker')) {
            $query->where('worker_id', $worker);
        }
    }
}
