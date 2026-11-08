<?php

namespace App\Http\Controllers;

use App\Http\Middleware\RequireCurrentAppVersion;
use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\Models\AppVersion;
use App\Models\Notification;
use App\Models\Trip;
use App\Services\Applications;
use App\Services\Conversations;
use App\Services\Notifier;
use App\Services\Settings;
use App\Services\Trips;
use Carbon\Carbon;
use Illuminate\Http\Request;

/**
 * Sincronización (docs/11 §11.44 «Frecuencias de consulta» y §11.47). No hay
 * servicio de envío: la app consulta GET /sync?cursor=N cada cierto tiempo (o
 * con el botón Actualizar) y muestra como notificaciones del teléfono las que
 * llegan en data. Si no hay novedades, data va vacío y meta es pequeño.
 *
 * - Sin cursor: no devuelve notificaciones antiguas, solo el cursor actual.
 * - meta.cursor: el que hay que enviar en la siguiente consulta.
 * - meta.changed: qué datos cambiaron (trips, applications, conversations…)
 *   para recargarlos.
 * - meta.counters: solicitudes por resolver (Administrador y Jefe), resueltas
 *   sin ver y conversaciones sin leer.
 * - meta.latestAppVersion: última versión publicada (notificación de
 *   actualización disponible; obligatoria según la cabecera X-App-Version).
 * - meta.nextTrip: el viaje en ejecución o el próximo planificado (para la
 *   frecuencia de consulta y el recordatorio de activar la ubicación).
 */
class SyncController extends Controller
{
    public const LIMIT = 100;

    public function show(Request $request, Applications $applications, Conversations $conversations, Settings $settings, Trips $trips)
    {
        $user = $request->user();
        $cursor = $request->query('cursor');

        if ($cursor !== null && ! ctype_digit((string) $cursor)) {
            throw JsonApiException::badRequest('cursor debe ser un número entero.', 'cursor');
        }

        $data = [];
        $changed = [];

        if ($cursor === null) {
            $next = (int) Notification::where('user_id', $user->id)->max('id');
            $more = false;
        } else {
            $items = Notification::where('user_id', $user->id)->where('id', '>', (int) $cursor)->orderBy('id')->limit(self::LIMIT + 1)->get();
            $more = $items->count() > self::LIMIT;
            $items = $items->take(self::LIMIT);
            $next = $items->isEmpty() ? (int) $cursor : (int) $items->last()->id;

            foreach ($items as $item) {
                $data[] = [
                    'type' => 'notifications',
                    'id' => (string) $item->id,
                    'attributes' => [
                        'kind' => $item->kind,
                        'title' => $item->title,
                        'body' => $item->body,
                        'data' => (object) $item->dataArray(),
                        'createdAt' => $item->created_at->toIso8601String(),
                    ],
                ];
                $changed[Notifier::CHANGES[$item->kind] ?? 'other'] = true;
            }
        }

        $installed = RequireCurrentAppVersion::versionCode($request);
        $latest = AppVersion::latest();
        $nextTrip = $trips->visibleQuery($user)->whereIn('status', [Trip::PLANNED, Trip::RUNNING])
            ->where('date', '>=', Carbon::today()->toDateString())
            ->orderByRaw("case when status = 'en_ejecucion' then 0 else 1 end")->orderBy('departs_at')->first();

        return JsonApiResponse::make(Document::fromArray($data, [
            'cursor' => (string) $next,
            'more' => $more,
            'changed' => array_keys($changed),
            'counters' => [
                'applicationsToResolve' => $applications->pendingToResolve($user),
                'applicationsResolvedUnseen' => $applications->unseenResolved($user),
                'conversationsUnread' => $conversations->unreadCount($user),
            ],
            'latestAppVersion' => $latest ? [
                'id' => (string) $latest->id,
                'versionCode' => $latest->version_code,
                'versionName' => $latest->version_name,
                'updateAvailable' => $installed !== null && $latest->version_code > $installed,
                'mandatory' => $installed !== null && AppVersion::isMandatoryAfter($installed),
            ] : null,
            'nextTrip' => $nextTrip ? [
                'id' => (string) $nextTrip->id,
                'direction' => $nextTrip->direction,
                'status' => $nextTrip->status,
                'departsAt' => $nextTrip->departs_at->toIso8601String(),
                'today' => $nextTrip->date->isToday(),
            ] : null,
            'settingsVersion' => $settings->version(),
            'serverTime' => Carbon::now()->toIso8601String(),
        ]));
    }
}
