<?php

namespace App\Http\Controllers;

use App\JsonApi\JsonApiResponse;
use App\Models\Stop;
use App\Services\Settings;
use Illuminate\Http\Request;

/**
 * Mapa propio (docs/09-repaso-pantallas.md, Mapas): el servidor sirve las
 * imágenes del mapa de Cuba con un estilo sencillo; la app las pide aquí,
 * no sale de Cuba y puede descargar la zona de su Entidad.
 */
class MapController extends Controller
{
    /** Límites de Cuba (con la Isla de la Juventud y los cayos). */
    const BOUNDS = ['south' => 19.6, 'west' => -85.2, 'north' => 23.45, 'east' => -73.9];

    /** Margen alrededor de las paradas de la Entidad para la descarga (grados ≈ 2 km). */
    const AREA_MARGIN = 0.02;

    public function show(Request $request, Settings $settings)
    {
        $user = $request->user();
        $query = Stop::query();

        if ($entity = $request->input('filter.entity')) {
            $query->where('entity_id', (int) $entity);
        } elseif (! $user->isAdmin()) {
            $query->whereIn('entity_id', $user->entityIds() ?: [0]);
        }

        $box = $query->selectRaw('MIN(latitude) AS south, MIN(longitude) AS west, MAX(latitude) AS north, MAX(longitude) AS east')->first();
        $area = $box && $box->south !== null ? [
            'south' => max(self::BOUNDS['south'], (float) $box->south - self::AREA_MARGIN),
            'west' => max(self::BOUNDS['west'], (float) $box->west - self::AREA_MARGIN),
            'north' => min(self::BOUNDS['north'], (float) $box->north + self::AREA_MARGIN),
            'east' => min(self::BOUNDS['east'], (float) $box->east + self::AREA_MARGIN),
        ] : null;

        return JsonApiResponse::make(['data' => [
            'type' => 'map-configs',
            'id' => 'current',
            'attributes' => [
                'tilesUrl' => (string) $settings->get('map_tiles_url'),
                'minZoom' => 7,
                'maxZoom' => 17,
                'downloadMinZoom' => 12,
                'downloadMaxZoom' => 17,
                'bounds' => self::BOUNDS,
                'area' => $area,
            ],
        ]]);
    }
}
