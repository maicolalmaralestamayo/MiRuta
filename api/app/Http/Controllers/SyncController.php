<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiResponse;
use App\Services\SyncFeed;
use Illuminate\Http\Request;

/**
 * Sincronización (docs/11 §11.44, §11.47 y §11.62). No hay servicio de envío:
 * la app consulta GET /sync?cursor=N cada «Frecuencia fuera ventana» (o con el
 * botón Actualizar) y muestra como notificaciones del teléfono las que llegan
 * en data. Dentro de la ventana de viaje lo mismo llega en
 * POST trips/{id}/reports?cursor=N (meta.sync). Detalle en App\Services\SyncFeed.
 *
 * - Sin cursor: no devuelve notificaciones antiguas, solo el cursor actual.
 * - meta.changed: qué datos cambiaron según las notificaciones.
 * - meta.versions: huella de cada grupo de datos (caché de la app).
 * - meta.myTrips: viajes en que viaja (ventana de viaje).
 */
class SyncController extends Controller
{
    public function show(Request $request, SyncFeed $feed)
    {
        [$data, $meta] = $feed->build($request->user(), $request->query('cursor'), $request);

        return JsonApiResponse::make(Document::fromArray($data, $meta));
    }
}
