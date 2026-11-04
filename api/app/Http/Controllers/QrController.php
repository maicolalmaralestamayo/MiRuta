<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\Models\Entity;
use App\Models\TripLeg;
use App\Models\User;
use App\Models\Worker;
use App\Services\Permissions;
use App\Services\QrCodes;
use App\Services\QrScans;
use App\Services\Trips;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

/**
 * Código QR de la persona (docs/11 §11.8 y §11.9; docs/07-algoritmos.md §7.31).
 */
class QrController extends Controller
{
    const MAX_OFFLINE_SCANS = 200;

    /** @var QrCodes */
    private $codes;

    /** @var QrScans */
    private $scans;

    public function __construct(QrCodes $codes, QrScans $scans)
    {
        $this->codes = $codes;
        $this->scans = $scans;
    }

    /**
     * GET /qr-public-key (público): clave del servidor para comprobar sin conexión.
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
            ],
        ]));
    }

    /**
     * POST /me/qr-devices: certifica la clave del teléfono (30 días).
     */
    public function storeDevice(Request $request)
    {
        $data = $this->validateResource($request, 'qr-devices', [
            'attributes.publicKey' => ['required', 'string', 'max:400'],
        ]);
        $user = $request->user();
        // Si usa la app en su teléfono, su QR impreso deja de valer.
        $this->codes->switchToPhone($user);
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
     * GET /workers/{id}/printed-qr (workers.printed_qr).
     */
    public function printed(Request $request, $id)
    {
        $user = $this->printedOwner($request, $id);

        return JsonApiResponse::make(Document::fromArray($this->printedResource($user)));
    }

    /**
     * POST /workers/{id}/printed-qr/revoke: anula el impreso y genera uno nuevo.
     */
    public function revokePrinted(Request $request, $id)
    {
        $user = $this->codes->revokePrinted($this->printedOwner($request, $id));

        return JsonApiResponse::make(Document::fromArray($this->printedResource($user)));
    }

    /**
     * POST /qr-scans: comprueba un QR y devuelve la tarjeta de la persona.
     */
    public function scan(Request $request, Trips $trips)
    {
        $data = $this->validateResource($request, 'qr-scans', [
            'attributes.qr' => ['required', 'string', 'max:2000'],
            'attributes.purpose' => ['required', 'in:boarding,itinerary_assignment'],
            'attributes.scannedAt' => ['sometimes', 'nullable', 'date'],
            'relationships.tripLeg.data.type' => ['sometimes', 'in:trip-legs'],
            'relationships.tripLeg.data.id' => ['sometimes', 'integer'],
        ]);
        $attributes = $data['attributes'];
        $legId = isset($data['relationships']['tripLeg']['data']['id']) ? $data['relationships']['tripLeg']['data']['id'] : null;
        $leg = $legId !== null ? $this->findLeg($request, $trips, $legId) : null;

        return JsonApiResponse::make(Document::fromArray($this->scans->describe(
            $attributes['qr'], $attributes['purpose'], $leg, $request->user(), $this->scannedAt($attributes)
        )));
    }

    /**
     * GET /entities/{id}/scan-roster: trabajadores e hijos con derecho para escanear sin conexión.
     */
    public function roster(Request $request, $id)
    {
        $entity = Entity::find($id);

        if (! $entity) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'La Entidad no existe.');
        }

        return JsonApiResponse::make(Document::fromArray($this->scans->roster($entity, $request->user())));
    }

    /**
     * POST /itinerary-assignments: alta directa en un itinerario con el QR.
     */
    public function assign(Request $request)
    {
        $data = $this->validateResource($request, 'itinerary-assignments', $this->assignmentRules());
        $result = $this->assignment($data, $request->user());

        return $this->assignmentResponse($result, $result['repeated'] ? 200 : 201);
    }

    /**
     * POST /offline-scans: sincroniza lo escaneado sin conexión. Cada
     * elemento se procesa por separado; nunca falla todo el lote.
     */
    public function offline(Request $request, Trips $trips)
    {
        $items = $request->json('data');

        if (! is_array($items) || ! $items || array_keys($items) !== range(0, count($items) - 1) || count($items) > self::MAX_OFFLINE_SCANS) {
            throw new JsonApiException(400, 'BAD_REQUEST', 'Petición incorrecta',
                '"data" debe ser una lista de 1 a '.self::MAX_OFFLINE_SCANS.' escaneos.', ['pointer' => '/data']);
        }

        $user = $request->user();
        $results = [];

        foreach ($items as $index => $item) {
            $clientId = is_array($item) && isset($item['lid']) ? (string) $item['lid'] : (is_array($item) && isset($item['id']) ? (string) $item['id'] : (string) $index);
            $result = ['type' => 'offline-scans', 'id' => $clientId, 'attributes' => ['status' => 'accepted', 'code' => null, 'detail' => null]];

            try {
                $result = $this->offlineItem($item, $user, $request, $trips, $result);
            } catch (JsonApiException $exception) {
                $error = $exception->toError();
                $result['attributes'] = [
                    'status' => in_array($error['code'], ['QR_ALREADY_USED', 'ALREADY_BOARDED'], true) ? 'discarded' : 'rejected',
                    'code' => $error['code'],
                    'detail' => isset($error['detail']) ? $error['detail'] : $error['title'],
                ] + (isset($error['meta']) ? ['meta' => $error['meta']] : []);
            } catch (\Illuminate\Validation\ValidationException $exception) {
                $result['attributes'] = ['status' => 'rejected', 'code' => 'VALIDATION_ERROR', 'detail' => collect($exception->errors())->flatten()->first()];
            } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $exception) {
                $result['attributes'] = ['status' => 'rejected', 'code' => 'NOT_FOUND', 'detail' => 'No existe.'];
            }

            $results[] = $result;
        }

        return JsonApiResponse::make(Document::fromArray($results, [
            'accepted' => count(array_filter($results, function ($r) {
                return in_array($r['attributes']['status'], ['accepted', 'repeated'], true);
            })),
            'total' => count($results),
        ]));
    }

    private function offlineItem($item, User $user, Request $request, Trips $trips, array $result): array
    {
        if (! is_array($item) || ! isset($item['type']) || $item['type'] !== 'offline-scans') {
            throw JsonApiException::conflict('TYPE_MISMATCH', 'El tipo del recurso debe ser "offline-scans".', '/data/type');
        }

        $validator = Validator::make($item, [
            'attributes.purpose' => ['required', 'in:boarding,itinerary_assignment'],
            'attributes.qr' => ['required', 'string', 'max:2000'],
            'attributes.scannedAt' => ['required', 'date'],
            'attributes.childIds' => ['sometimes', 'nullable', 'array', 'max:20'],
            'attributes.childIds.*' => ['integer'],
            'attributes.allowOutsider' => ['sometimes', 'boolean'],
        ]);
        $validator->validate();
        $attributes = $item['attributes'];

        if ($attributes['purpose'] === QrScans::PURPOSE_BOARDING) {
            if (! isset($item['relationships']['tripLeg']['data']['id'])) {
                throw new JsonApiException(422, 'VALIDATION_ERROR', 'Error de validación', 'Falta el trayecto (relationships.tripLeg).');
            }

            $leg = $this->findLeg($request, $trips, $item['relationships']['tripLeg']['data']['id']);
            $outcome = $this->scans->board($leg, $attributes['qr'], $user, $this->scannedAt($attributes),
                isset($attributes['childIds']) ? $attributes['childIds'] : null, ! empty($attributes['allowOutsider']));
            $result['attributes']['status'] = $outcome['repeated'] ? 'repeated' : 'accepted';
            $result['relationships'] = ['tripBoarding' => ['data' => ['type' => 'trip-boardings', 'id' => (string) $outcome['boarding']->id]]];

            return $result;
        }

        $outcome = $this->assignment($item, $user);
        $result['attributes']['status'] = $outcome['repeated'] ? 'repeated' : 'accepted';
        $result['relationships'] = ['worker' => ['data' => ['type' => 'workers', 'id' => (string) $outcome['worker']->id]]];

        return $result;
    }

    private function assignmentRules(): array
    {
        return [
            'attributes.qr' => ['required', 'string', 'max:2000'],
            'attributes.scannedAt' => ['sometimes', 'nullable', 'date'],
            'relationships.itinerary.data.type' => ['required', 'in:itineraries'],
            'relationships.itinerary.data.id' => ['required', 'integer'],
            'relationships.stop.data.type' => ['required', 'in:stops'],
            'relationships.stop.data.id' => ['required', 'integer'],
        ];
    }

    private function assignment(array $data, User $user): array
    {
        if (! isset($data['relationships']['itinerary']['data']['id'], $data['relationships']['stop']['data']['id'])) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Error de validación', 'Hay que indicar el itinerario y la parada.', ['pointer' => '/data/relationships']);
        }

        return $this->scans->assign($data['attributes']['qr'], (int) $data['relationships']['itinerary']['data']['id'],
            (int) $data['relationships']['stop']['data']['id'], $user, $this->scannedAt($data['attributes']));
    }

    private function assignmentResponse(array $result, int $status)
    {
        $worker = $result['worker'];

        return JsonApiResponse::make(Document::fromArray([
            'type' => 'itinerary-assignments',
            'id' => (string) $worker->id,
            'attributes' => [
                'fullName' => $worker->fullName(),
                'previousItineraryId' => $result['previous'][0] !== null ? (string) $result['previous'][0] : null,
                'previousStopId' => $result['previous'][1] !== null ? (string) $result['previous'][1] : null,
                'assignedAt' => $worker->itinerary_assigned_at ? $worker->itinerary_assigned_at->toIso8601String() : null,
            ],
            'relationships' => [
                'worker' => ['data' => ['type' => 'workers', 'id' => (string) $worker->id]],
                'user' => ['data' => ['type' => 'users', 'id' => (string) $worker->user_id]],
                'itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) $worker->itinerary_id]],
                'stop' => ['data' => ['type' => 'stops', 'id' => (string) $worker->stop_id]],
            ],
        ], $result['repeated'] ? ['repeated' => true] : []), $status);
    }

    private function printedOwner(Request $request, $id): User
    {
        $worker = Worker::find($id);

        if (! $worker || ! ($user = User::find($worker->user_id))) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'El trabajador no existe.');
        }

        app(Permissions::class)->authorize($request->user(), 'workers.printed_qr', (int) $worker->entity_id,
            $worker->itinerary_id ? (int) $worker->itinerary_id : null, 'No tiene permiso para ver ni anular el QR impreso de este trabajador.');

        if ($user->has_phone) {
            throw JsonApiException::conflict('PRINTED_QR_NOT_AVAILABLE',
                'Esta persona usa la app en su teléfono: su QR cambia cada pocos segundos y no tiene QR impreso. Si ya no tiene teléfono, indíquelo en sus datos (hasPhone).');
        }

        return $user;
    }

    private function printedResource(User $user): array
    {
        return [
            'type' => 'printed-qrs',
            'id' => (string) $user->id,
            'attributes' => [
                'qr' => $this->codes->printedQr($user),
                'version' => (int) $user->printed_qr_version,
                // Lo único que va impreso junto al QR (docs/11 §11.9).
                'firstName' => $user->first_name,
                'middleName' => $user->middle_name,
                'firstSurname' => $user->first_surname,
                'secondSurname' => $user->second_surname,
                'fullName' => $user->fullName(),
                'sex' => $user->sex,
            ],
            'relationships' => [
                'user' => ['data' => ['type' => 'users', 'id' => (string) $user->id]],
            ],
        ];
    }

    private function findLeg(Request $request, Trips $trips, $id): TripLeg
    {
        $leg = TripLeg::whereIn('trip_id', $trips->visibleTo($request->user())->select('id'))->find($id);

        if (! $leg) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'El trayecto no existe o no puede verlo.', ['pointer' => '/data/relationships/tripLeg']);
        }

        return $leg;
    }

    private function scannedAt(array $attributes): ?Carbon
    {
        return ! empty($attributes['scannedAt']) ? Carbon::parse($attributes['scannedAt'])->setTimezone(config('app.timezone')) : null;
    }
}
