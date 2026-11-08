<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiResponse;
use App\Services\QrCodes;
use App\Services\QrInclusions;
use Carbon\Carbon;
use Illuminate\Http\Request;

/**
 * Código QR de la persona e «Incluir por QR» (docs/11 §11.19 y §11.27).
 */
class QrController extends Controller
{
    public function __construct(private QrCodes $codes, private QrInclusions $inclusions)
    {
    }

    /**
     * GET qr-public-key (público): clave del servidor para comprobar sin conexión.
     */
    public function publicKey()
    {
        return JsonApiResponse::make(Document::fromArray([
            'type' => 'qr-public-keys',
            'id' => 'current',
            'attributes' => [
                'publicKey' => $this->codes->publicKey(),
                'algorithm' => 'ES256',
                'curve' => 'P-256',
                'format' => 'SPKI DER (base64)',
                'signatureFormat' => 'DER',
                'clockSkewSeconds' => QrCodes::CLOCK_SKEW_SECONDS,
                'certificateDays' => QrCodes::CERTIFICATE_DAYS,
                'refreshSeconds' => 15,
            ],
        ]));
    }

    /**
     * POST me/qr-devices: certifica la clave del teléfono (30 días).
     */
    public function storeDevice(Request $request)
    {
        $data = $this->validateResource($request, 'qr-devices', [
            'attributes.publicKey' => ['required', 'string', 'max:400'],
        ]);
        $user = $request->user();
        $issued = $this->codes->issueCertificate($user, $data['attributes']['publicKey']);

        return JsonApiResponse::make(Document::fromArray([
            'type' => 'qr-devices',
            'id' => substr(hash('sha256', $issued['publicKey']), 0, 16),
            'attributes' => [
                'publicKey' => $issued['publicKey'],
                'certificate' => $issued['certificate'],
                'expiresAt' => $issued['expiresAt']->toIso8601String(),
                'userId' => (string) $user->id,
                'serverPublicKey' => $this->codes->publicKey(),
            ],
        ]), 201);
    }

    /**
     * POST qr-scans: comprueba el QR (sin gastarlo) y dice quién es y dónde está ya.
     */
    public function scan(Request $request)
    {
        $data = $this->validateResource($request, 'qr-scans', [
            'attributes.qr' => ['required', 'string', 'max:2000'],
            'attributes.scannedAt' => ['sometimes', 'nullable', 'date'],
        ]);

        return JsonApiResponse::make(Document::fromArray(
            $this->inclusions->describe($data['attributes']['qr'], $request->user(), $this->scannedAt($data['attributes']))
        ));
    }

    /**
     * POST qr-inclusions: incluye a la persona del QR en una Entidad, un
     * itinerario o una parada (relationships entity, itinerary y stop). Un
     * reintento de la misma inclusión responde 200 con meta.repeated.
     */
    public function include(Request $request)
    {
        $data = $this->validateResource($request, 'qr-inclusions', [
            'attributes.qr' => ['required', 'string', 'max:2000'],
            'attributes.scannedAt' => ['sometimes', 'nullable', 'date'],
        ] + $this->relationshipRules('entity', 'entities', 'entities', false)
          + $this->relationshipRules('itinerary', 'itineraries', 'itineraries', false)
          + $this->relationshipRules('stop', 'stops', 'stops', false));

        $result = $this->inclusions->include($data['attributes']['qr'], $request->user(), $this->scannedAt($data['attributes']),
            $this->relationshipId($data, 'entity'), $this->relationshipId($data, 'itinerary'), $this->relationshipId($data, 'stop'));
        $worker = $result['worker'];

        return JsonApiResponse::make(Document::fromArray([
            'type' => 'qr-inclusions',
            'id' => (string) $worker->id,
            'attributes' => [
                'fullName' => $worker->user->fullName(),
                'previous' => $result['previous'],
            ],
            'relationships' => [
                'worker' => ['data' => ['type' => 'workers', 'id' => (string) $worker->id]],
                'user' => ['data' => ['type' => 'users', 'id' => (string) $worker->user_id]],
                'entity' => ['data' => ['type' => 'entities', 'id' => (string) $worker->entity_id]],
                'itinerary' => ['data' => $worker->itinerary_id ? ['type' => 'itineraries', 'id' => (string) $worker->itinerary_id] : null],
                'stop' => ['data' => $worker->stop_id ? ['type' => 'stops', 'id' => (string) $worker->stop_id] : null],
            ],
        ], $result['repeated'] ? ['repeated' => true] : []), $result['repeated'] ? 200 : 201);
    }

    private function scannedAt(array $attributes): ?Carbon
    {
        return ! empty($attributes['scannedAt']) ? Carbon::parse($attributes['scannedAt'])->setTimezone(config('app.timezone')) : null;
    }
}
