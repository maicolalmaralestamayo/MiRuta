<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Child;
use App\Models\Entity;
use App\Models\Itinerary;
use App\Models\QrNonce;
use App\Models\Stop;
use App\Models\TripBoarding;
use App\Models\TripLeg;
use App\Models\User;
use App\Models\Worker;
use Carbon\Carbon;
use Carbon\CarbonImmutable;
use Carbon\CarbonInterface;
use Illuminate\Support\Facades\DB;

/**
 * Usos del QR de la persona (docs/11 §11.8): subida al transporte y alta
 * directa en un itinerario, en línea o sincronizando lo escaneado sin conexión.
 */
class QrScans
{
    const PURPOSE_BOARDING = 'boarding';
    const PURPOSE_ITINERARY_ASSIGNMENT = 'itinerary_assignment';

    /** @var QrCodes */
    private $codes;

    /** @var Boardings */
    private $boardings;

    /** @var Permissions */
    private $permissions;

    public function __construct(QrCodes $codes, Boardings $boardings, Permissions $permissions)
    {
        $this->codes = $codes;
        $this->boardings = $boardings;
        $this->permissions = $permissions;
    }

    /**
     * Subida con el QR. Devuelve ['boarding', 'created', 'repeated'].
     */
    public function board(TripLeg $leg, string $qr, User $scanner, ?CarbonInterface $scannedAt, ?array $childIds, bool $allowOutsider, string $pointer = '/data/attributes/qr'): array
    {
        $this->ensureCanScan($leg, $scanner);
        $verified = $this->codes->verify($qr, $scannedAt, $pointer);

        // Reintento de una sincronización: el código ya registró esta subida.
        if ($repeated = $this->repeatedUse($verified, self::PURPOSE_BOARDING, function (QrNonce $nonce) use ($leg) {
            return TripBoarding::withTrashed()->whereKey($nonce->reference_id)->where('trip_leg_id', $leg->id)->exists();
        })) {
            return ['boarding' => TripBoarding::withTrashed()->find($repeated->reference_id), 'created' => false, 'repeated' => true];
        }

        $result = $this->boardings->register($leg, $verified['user'], TripBoarding::METHOD_QR, [
            'scanner' => $scanner,
            'at' => $scannedAt,
            'childIds' => $childIds,
            'allowOutsider' => $allowOutsider,
            'qrKind' => $verified['kind'],
            'afterSave' => function (TripBoarding $boarding) use ($verified) {
                $nonce = $this->codes->consume($verified, self::PURPOSE_BOARDING);

                if ($nonce) {
                    $nonce->forceFill(['reference_id' => $boarding->id])->save();
                }
            },
        ]);

        return $result + ['repeated' => false];
    }

    /**
     * Alta directa en un itinerario con el QR (members.assign_by_qr): le
     * cambia el itinerario y la parada en esa Entidad; pierde el anterior y
     * no pierde jefaturas. Devuelve ['worker', 'previous' => [itineraryId, stopId], 'repeated'].
     */
    public function assign(string $qr, int $itineraryId, int $stopId, User $scanner, ?CarbonInterface $scannedAt, string $pointer = '/data/attributes/qr'): array
    {
        $itinerary = Itinerary::find($itineraryId);

        if (! $itinerary) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'El itinerario no existe.', ['pointer' => '/data/relationships/itinerary']);
        }

        if (! $this->permissions->can($scanner, 'members.assign_by_qr', (int) $itinerary->entity_id, (int) $itinerary->id)) {
            throw Permissions::forbidden('No tiene permiso para dar de alta con el QR en este itinerario.');
        }

        $verified = $this->codes->verify($qr, $scannedAt, $pointer);
        $person = $verified['user'];
        $worker = Worker::where('user_id', $person->id)->where('entity_id', $itinerary->entity_id)->first();

        if (! $worker) {
            throw new JsonApiException(422, 'NOT_A_MEMBER', 'No pertenece a la Entidad',
                $person->fullName().' no pertenece a la Entidad de ese itinerario. Primero tiene que entrar en ella.', ['pointer' => $pointer]);
        }

        if ($this->repeatedUse($verified, self::PURPOSE_ITINERARY_ASSIGNMENT, function (QrNonce $nonce) use ($worker, $itinerary, $stopId) {
            return (int) $nonce->reference_id === (int) $worker->id
                && (int) $worker->itinerary_id === (int) $itinerary->id && (int) $worker->stop_id === $stopId;
        })) {
            return ['worker' => $worker, 'previous' => [null, null], 'repeated' => true];
        }

        $previous = [$worker->itinerary_id ? (int) $worker->itinerary_id : null, $worker->stop_id ? (int) $worker->stop_id : null];

        $worker = DB::transaction(function () use ($worker, $itinerary, $stopId, $scanner, $verified) {
            $worker = app(Memberships::class)->assignItinerary($worker, (int) $itinerary->id, $stopId, $scanner);
            $nonce = $this->codes->consume($verified, self::PURPOSE_ITINERARY_ASSIGNMENT);

            if ($nonce) {
                $nonce->forceFill(['reference_id' => $worker->id])->save();
            }

            return $worker;
        });

        return ['worker' => $worker, 'previous' => $previous, 'repeated' => false];
    }

    /**
     * Lo que ve quien escanea (POST /qr-scans). No gasta el código.
     */
    public function describe(string $qr, string $purpose, ?TripLeg $leg, User $scanner, ?CarbonInterface $scannedAt): array
    {
        if ($purpose === self::PURPOSE_BOARDING) {
            if ($leg) {
                $this->ensureCanScan($leg, $scanner);
            } elseif (! $this->permissions->canAnywhere($scanner, 'tracking.scan_boarding') && ! $this->permissions->canAnywhere($scanner, 'tracking.drive')) {
                throw Permissions::forbidden('No tiene permiso para escanear la subida.');
            }
        } elseif (! $this->permissions->canAnywhere($scanner, 'members.assign_by_qr')) {
            throw Permissions::forbidden('No tiene permiso para dar de alta con el QR.');
        }

        $verified = $this->codes->verify($qr, $scannedAt);
        $person = $verified['user'];
        $used = $verified['kind'] === QrCodes::KIND_DYNAMIC
            && QrNonce::withTrashed()->where('user_id', $person->id)->where('nonce', $verified['nonce'])->exists();

        $attributes = [
            'purpose' => $purpose,
            'kind' => $verified['kind'],
            'userId' => (string) $person->id,
            'firstName' => $person->first_name,
            'middleName' => $person->middle_name,
            'firstSurname' => $person->first_surname,
            'secondSurname' => $person->second_surname,
            'fullName' => $person->fullName(),
            'sex' => $person->sex,
            'photoUrl' => $person->photo_path ? url($person->photo_path) : null,
            'entities' => \App\Serializers\UserSerializer::entityAbbreviations($person),
            'alreadyUsed' => $used,
            'memberships' => $this->memberships($person, $scanner),
            'outsider' => null,
            'canAllowOutsider' => null,
            'alreadyBoarded' => null,
            'warning' => $used ? 'Este código QR ya se usó. Pida que lo muestre de nuevo.' : null,
            'children' => [],
        ];

        if ($purpose === self::PURPOSE_BOARDING) {
            $date = $leg ? CarbonImmutable::instance($leg->trip->departs_at) : CarbonImmutable::now();
            $boardedChildren = [];
            $ownBoarding = 0;

            if ($leg) {
                list(, $outsider) = $this->boardings->passengerOf($leg->trip, $person);
                $existing = $this->boardings->existingFor($leg, (int) $person->id);
                $attributes['outsider'] = $outsider;
                $attributes['canAllowOutsider'] = $this->boardings->canAllowOutsiders($leg->trip, $scanner);
                $attributes['alreadyBoarded'] = $existing !== null && in_array($existing->method, [TripBoarding::METHOD_QR, TripBoarding::METHOD_MANUAL], true);

                if ($attributes['alreadyBoarded']) {
                    $attributes['warning'] = $this->boardings->alreadyBoardedText($existing, $verified['kind']);
                } elseif ($outsider && ! $attributes['warning']) {
                    $attributes['warning'] = $this->boardings->outsiderText($outsider);
                }

                $boardedChildren = DB::table('trip_boarding_children')->where('trip_leg_id', $leg->id)->whereNull('deleted_at')
                    ->pluck('trip_boarding_id', 'child_id')->all();
                $ownBoarding = $existing ? (int) $existing->id : 0;
            }

            foreach (app(ChildEligibility::class)->eligibleChildrenOf((int) $person->id, $date) as $child) {
                $attributes['children'][] = [
                    'id' => (string) $child->id,
                    'fullName' => $child->fullName(),
                    'sex' => $child->sex,
                    'photoUrl' => $child->photo_path ? url($child->photo_path) : null,
                    // Ya subió con otra persona en este trayecto (no se puede volver a marcar).
                    'alreadyBoarded' => isset($boardedChildren[$child->id]) && (int) $boardedChildren[$child->id] !== $ownBoarding,
                    'boardedWithThisPerson' => isset($boardedChildren[$child->id]) && (int) $boardedChildren[$child->id] === $ownBoarding,
                ];
            }
        }

        return [
            'type' => 'qr-scans',
            'id' => $verified['kind'] === QrCodes::KIND_DYNAMIC ? $person->id.'-'.$verified['nonce'] : $person->id.'-printed-'.$person->printed_qr_version,
            'attributes' => $attributes,
            'relationships' => [
                'user' => ['data' => ['type' => 'users', 'id' => (string) $person->id]],
            ],
        ];
    }

    /**
     * Lista para escanear sin conexión en una Entidad.
     */
    public function roster(Entity $entity, User $user): array
    {
        $entityId = (int) $entity->id;

        if (! $this->permissions->canInEntity($user, 'tracking.scan_boarding', $entityId)
            && ! $this->permissions->canInEntity($user, 'members.assign_by_qr', $entityId)
            && ! $this->permissions->canInEntity($user, 'tracking.drive', $entityId)) {
            throw Permissions::forbidden('No tiene permiso para escanear en esta Entidad.');
        }

        $workers = Worker::where('entity_id', $entityId)->whereHas('user')->with('user', 'itinerary', 'stop')->orderBy('id')->get();
        $userIds = $workers->pluck('user_id')->map(function ($id) {
            return (int) $id;
        })->all();
        $eligibility = app(ChildEligibility::class);
        $children = [];

        $parents = DB::table('child_parents')->whereIn('user_id', $userIds ?: [0])->whereNull('deleted_at')->get(['child_id', 'user_id']);
        $parentsByChild = [];

        foreach ($parents as $row) {
            $parentsByChild[(int) $row->child_id][] = (string) $row->user_id;
        }

        foreach (Child::whereIn('id', array_keys($parentsByChild) ?: [0])->where('active', true)->orderBy('id')->get() as $child) {
            if (! $eligibility->isChildEligible($child)) {
                continue;
            }

            $children[] = [
                'childId' => (string) $child->id,
                'fullName' => $child->fullName(),
                'sex' => $child->sex,
                'photoUrl' => $child->photo_path ? url($child->photo_path) : null,
                'eligibleUntil' => $eligibility->childEligibleUntil($child)->toDateString(),
                'parentUserIds' => $parentsByChild[(int) $child->id],
            ];
        }

        return [
            'type' => 'scan-rosters',
            'id' => (string) $entityId,
            'attributes' => [
                'generatedAt' => Carbon::now()->toIso8601String(),
                'serverPublicKey' => $this->codes->publicKey(),
                'workers' => $workers->map(function (Worker $worker) {
                    $person = $worker->user;

                    return [
                        'workerId' => (string) $worker->id,
                        'userId' => (string) $person->id,
                        'fullName' => $person->fullName(),
                        'sex' => $person->sex,
                        'photoUrl' => $person->photo_path ? url($person->photo_path) : null,
                        'itineraryId' => $worker->itinerary_id ? (string) $worker->itinerary_id : null,
                        'itineraryName' => $worker->itinerary ? $worker->itinerary->name : null,
                        'stopId' => $worker->stop_id ? (string) $worker->stop_id : null,
                        'stopLandmark' => $worker->stop ? $worker->stop->landmark : null,
                        // null = no tiene QR impreso válido (usa el del teléfono).
                        'printedQrVersion' => $person->has_phone ? null : (int) $person->printed_qr_version,
                    ];
                })->values()->all(),
                'children' => $children,
            ],
            'relationships' => [
                'entity' => ['data' => ['type' => 'entities', 'id' => (string) $entityId]],
            ],
        ];
    }

    public function ensureCanScan(TripLeg $leg, User $scanner): void
    {
        if (! app(Tracking::class)->canScan($leg->trip, $scanner)) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'Solo el chofer y quien tenga permiso para escanear la subida pueden registrar la de otros.');
        }
    }

    /**
     * Código dinámico ya gastado: si fue en lo mismo, es un reintento
     * (devuelve el registro); si no, 409 QR_ALREADY_USED.
     */
    private function repeatedUse(array $verified, string $purpose, callable $same): ?QrNonce
    {
        if ($verified['kind'] !== QrCodes::KIND_DYNAMIC) {
            return null;
        }

        $nonce = QrNonce::withTrashed()->where('user_id', $verified['user']->id)->where('nonce', $verified['nonce'])->first();

        if (! $nonce) {
            return null;
        }

        if ($nonce->purpose === $purpose && $nonce->reference_id && $same($nonce)) {
            return $nonce;
        }

        throw JsonApiException::conflict('QR_ALREADY_USED', 'Este código QR ya se usó. Cada código vale una sola vez: pida que lo muestre de nuevo.', '/data/attributes/qr');
    }

    /**
     * Pertenencias de la persona, marcando dónde puede darle de alta quien escanea.
     */
    private function memberships(User $person, User $scanner): array
    {
        return Worker::where('user_id', $person->id)->with('entity', 'itinerary', 'stop')->orderBy('id')->get()->map(function (Worker $worker) use ($scanner) {
            return [
                'workerId' => (string) $worker->id,
                'entityId' => (string) $worker->entity_id,
                'entityAbbreviation' => $worker->entity ? $worker->entity->abbreviation : null,
                'itineraryId' => $worker->itinerary_id ? (string) $worker->itinerary_id : null,
                'itineraryName' => $worker->itinerary ? $worker->itinerary->name : null,
                'stopId' => $worker->stop_id ? (string) $worker->stop_id : null,
                'stopLandmark' => $worker->stop ? $worker->stop->landmark : null,
                'assignableByQr' => $this->permissions->canInEntity($scanner, 'members.assign_by_qr', (int) $worker->entity_id),
            ];
        })->values()->all();
    }
}
