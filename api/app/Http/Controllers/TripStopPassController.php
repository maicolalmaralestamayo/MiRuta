<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\TripStopPass;
use Illuminate\Http\Request;

class TripStopPassController extends TrackingController
{
    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, ['passedAt' => 'passed_at'], ['tripLeg'], ['stop'], 'passedAt');

        if (! $parameters->filter('tripLeg')) {
            throw JsonApiException::badRequest('Hay que indicar filter[tripLeg].', 'filter[tripLeg]');
        }

        $leg = $this->findLeg($request, $parameters->filter('tripLeg'));
        $paginator = $parameters->applySort(TripStopPass::where('trip_leg_id', $leg->id), ['passedAt' => 'passed_at'])
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator, $parameters->includes()));
    }
}
