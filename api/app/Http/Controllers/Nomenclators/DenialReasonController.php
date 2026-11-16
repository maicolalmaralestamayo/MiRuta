<?php

namespace App\Http\Controllers\Nomenclators;

use App\Http\Controllers\NomenclatorController;
use App\JsonApi\JsonApiException;
use App\JsonApi\QueryParameters;
use App\Models\EntityDenialReason;
use App\Models\ItineraryDenialReason;
use Illuminate\Http\Request;

/**
 * «denial-reasons» de la 4.3.0, solo para consultar (docs/11 §11.65): desde
 * la 4.4.0 los motivos de rechazo están separados en entity-denial-reasons e
 * itinerary-denial-reasons. Con filter[applicationType]=entidad devuelve los
 * de Entidad; si no, los de itinerario. Al rechazar con un «denial-reasons»,
 * el id se busca en la tabla del tipo de la solicitud.
 */
class DenialReasonController extends NomenclatorController
{
    protected string $type = 'itinerary-denial-reasons';

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, self::SORTABLE, ['active', 'search', 'applicationType'], [], 'name');
        $this->type = $parameters->filter('applicationType') === 'entidad' ? 'entity-denial-reasons' : 'itinerary-denial-reasons';

        return parent::index($request);
    }

    public function show(Request $request, $id)
    {
        $item = ItineraryDenialReason::find($id) ?? EntityDenialReason::findOrFail($id);

        return $this->respond($request, $item);
    }

    public function store(Request $request)
    {
        throw self::moved();
    }

    public function update(Request $request, $id)
    {
        throw self::moved();
    }

    public function destroy(Request $request, $id)
    {
        throw self::moved();
    }

    private static function moved(): JsonApiException
    {
        return JsonApiException::conflict('APP_UPDATE_NEEDED',
            'Los motivos de rechazo ahora están separados para solicitudes de Entidad y de itinerario: actualice MiRuta a la 4.4.0 para gestionarlos.');
    }
}
