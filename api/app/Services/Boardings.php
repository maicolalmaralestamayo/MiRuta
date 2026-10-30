<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\TripBoarding;
use App\Models\TripLeg;
use App\Models\Worker;
use App\Support\ExpiredJwtException;
use App\Support\Jwt;
use Carbon\Carbon;
use Carbon\CarbonImmutable;
use UnexpectedValueException;

/**
 * Registro de subida (7.22) y tokens del código QR de subida.
 */
class Boardings
{
    const PASS_TYPE = 'boarding';

    /** @var Settings */
    private $settings;

    /** @var ChildEligibility */
    private $childEligibility;

    public function __construct(Settings $settings, ChildEligibility $childEligibility)
    {
        $this->settings = $settings;
        $this->childEligibility = $childEligibility;
    }

    /**
     * Registra la subida. $children null = todos los que tiene con derecho.
     */
    public function board(TripLeg $leg, Worker $worker, string $method, ?int $children, ?Worker $markedBy): TripBoarding
    {
        if (! $leg->isActive()) {
            throw JsonApiException::conflict('LEG_NOT_ACTIVE', 'El trayecto no está en curso.');
        }

        $trip = $leg->trip;

        if (! app(Trips::class)->expectedPassengers($trip)->contains('id', $worker->id)) {
            throw new JsonApiException(422, 'NOT_A_PASSENGER', 'No es pasajero', 'El trabajador no es pasajero esperado de este viaje.', ['pointer' => '/data/relationships/worker']);
        }

        $maximum = $this->childEligibility->eligibleCount($worker, CarbonImmutable::instance($trip->departs_at));

        if ($children === null) {
            $children = $maximum;
        } elseif ($children > $maximum) {
            throw new JsonApiException(422, 'CHILDREN_COUNT_EXCEEDED', 'Demasiados niños',
                "Solo tiene {$maximum} hijo(s) con derecho a viajar.", ['pointer' => '/data/attributes/childrenCount']);
        }

        return TripBoarding::create([
            'trip_leg_id' => $leg->id,
            'worker_id' => $worker->id,
            'method' => $method,
            'marked_by' => $markedBy ? $markedBy->id : null,
            'children_count' => $children,
            'boarded_at' => Carbon::now(),
        ]);
    }

    /**
     * Último registro de subida de cada trabajador en el trayecto del viaje.
     *
     * @return array [id de trabajador => TripBoarding]
     */
    public function latestByWorker(int $tripId, string $direction): array
    {
        $legId = TripLeg::where('trip_id', $tripId)->where('direction', $direction)->value('id');

        if (! $legId) {
            return [];
        }

        $latest = [];

        foreach (TripBoarding::where('trip_leg_id', $legId)->orderBy('boarded_at')->orderBy('id')->get() as $boarding) {
            $latest[$boarding->worker_id] = $boarding;
        }

        return $latest;
    }

    /**
     * Token firmado para el QR: identifica al trabajador en ese trayecto sin
     * revelar su carné. No se guarda en la base de datos.
     *
     * @return array [token, expiresAt]
     */
    public function issuePass(TripLeg $leg, Worker $worker): array
    {
        $now = Carbon::now();
        $expires = $now->copy()->addSeconds($this->settings->int('boarding_pass_ttl_seconds'));

        $token = Jwt::encode([
            'sub' => $worker->id,
            'leg' => $leg->id,
            'typ' => self::PASS_TYPE,
            'iat' => $now->getTimestamp(),
            'exp' => $expires->getTimestamp(),
        ], config('mitransporte.jwt.secret'));

        return ['token' => $token, 'expiresAt' => $expires];
    }

    /**
     * Comprueba el token del QR y devuelve el trabajador.
     */
    public function verifyPass(string $token, TripLeg $leg): Worker
    {
        $invalid = new JsonApiException(422, 'BOARDING_PASS_INVALID', 'Código QR no válido',
            'El código QR caducó o es de otro recorrido.', ['pointer' => '/data/attributes/boardingPassToken']);

        try {
            $claims = Jwt::decode($token, config('mitransporte.jwt.secret'));
        } catch (ExpiredJwtException $exception) {
            throw $invalid;
        } catch (UnexpectedValueException $exception) {
            throw $invalid;
        }

        if (! isset($claims['typ'], $claims['leg'], $claims['sub']) || $claims['typ'] !== self::PASS_TYPE || (int) $claims['leg'] !== (int) $leg->id) {
            throw $invalid;
        }

        $worker = Worker::find($claims['sub']);

        if (! $worker) {
            throw $invalid;
        }

        return $worker;
    }
}
