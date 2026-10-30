<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Child;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

/**
 * Hijos. Se ven los declarados de todos (nombre y apellidos son públicos) y,
 * además, los pendientes propios. Se crean y quitan mediante solicitudes.
 */
class ChildController extends Controller
{
    const SORTABLE = ['firstName' => 'first_name', 'lastName' => 'last_name', 'id' => 'id'];

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, self::SORTABLE, ['worker'], ['worker'], 'lastName,firstName');
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

        return Child::query()->where(function (Builder $query) use ($user) {
            $query->declared()->orWhere('worker_id', $user->id);
        });
    }
}
