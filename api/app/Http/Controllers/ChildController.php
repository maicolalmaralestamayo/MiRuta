<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Child;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

/**
 * Hijos. Se ven los declarados de la Entidad (los nombres son públicos) y,
 * además, los pendientes propios. Se crean y quitan mediante solicitudes.
 */
class ChildController extends Controller
{
    const SORTABLE = ['firstName' => 'first_name', 'firstSurname' => 'first_surname', 'secondSurname' => 'second_surname', 'id' => 'id'];

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, self::SORTABLE, ['worker'], ['worker'], 'firstSurname,secondSurname,firstName');
        $query = $this->visible($request);

        if ($worker = $parameters->filter('worker')) {
            $query->where('worker_id', $worker);
        }

        $paginator = $parameters->applySort($query, self::SORTABLE)
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator, $parameters->includes()));
    }

    public function show(Request $request, $id)
    {
        $child = $this->visible($request)->findOrFail($id);

        return JsonApiResponse::make((new Document($request))->resource($child, QueryParameters::readIncludes($request, ['worker'])));
    }

    private function visible(Request $request): Builder
    {
        $user = $request->user();

        $query = Child::query()->where(function (Builder $query) use ($user) {
            $query->declared()->orWhere('worker_id', (int) $user->workerId());
        });

        return $user->isAdmin() ? $query : $query->whereHas('worker', function (Builder $query) use ($user) {
            $query->where('entity_id', $user->entityId());
        });
    }
}
