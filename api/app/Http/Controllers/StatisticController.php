<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\Services\Statistics;
use Illuminate\Http\Request;

class StatisticController extends Controller
{
    const FILTERS = ['from', 'to', 'dates', 'last', 'entity', 'itinerary', 'vehicle', 'driver', 'stop', 'worker', 'trip', 'by', 'level'];

    public function show(Request $request, Statistics $statistics, string $name)
    {
        $filters = $request->query('filter', []);

        if (! is_array($filters)) {
            throw JsonApiException::badRequest('Los filtros deben usarse como filter[nombre]=valor.', 'filter');
        }

        foreach (array_keys($filters) as $filter) {
            if (! in_array($filter, self::FILTERS, true)) {
                throw JsonApiException::badRequest("No existe el filtro \"{$filter}\".", "filter[{$filter}]");
            }
        }

        $result = $statistics->compute($name, $request->user(), array_filter($filters, function ($value) {
            return $value !== '' && $value !== null;
        }));

        return JsonApiResponse::make(Document::fromArray([
            'type' => 'statistics',
            'id' => $name,
            'attributes' => ['columns' => $result['columns'], 'rows' => $result['rows']],
            'meta' => ['period' => $result['period']],
        ]));
    }
}
