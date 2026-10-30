<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Rank;
use Illuminate\Http\Request;

class RankController extends Controller
{
    const SORTABLE = [
        'name' => 'name',
        'precedence' => 'precedence',
    ];

    const FILTERABLE = ['name'];

    /**
     * Lista pública: la pantalla de registro la necesita antes de iniciar sesión.
     */
    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, self::SORTABLE, self::FILTERABLE, [], 'precedence');

        $query = Rank::query();

        if ($name = $parameters->filter('name')) {
            $query->where('name', 'like', '%'.$name.'%');
        }

        $paginator = $parameters->applySort($query, self::SORTABLE)
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator, $parameters->includes()));
    }
}
