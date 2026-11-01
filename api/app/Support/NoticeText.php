<?php

namespace App\Support;

use App\Models\Application;
use App\Models\Notice;
use App\Models\Trip;
use App\Models\TripLeg;
use App\Models\TripLegIncident;
use App\Services\Passwords;
use Carbon\Carbon;

/**
 * Texto de cada aviso, con lo concreto: qué solicitud fue, quién la resolvió
 * y, si se rechazó, el motivo (docs/09 §16).
 */
class NoticeText
{
    const APPLICATION_TYPES = [
        Application::TYPE_ITINERARY_MEMBERSHIP => 'Itinerario y parada',
        Application::TYPE_ITINERARY_CHIEF => 'Rol de Jefe de itinerario',
        Application::TYPE_DRIVER => 'Rol de Chofer',
        Application::TYPE_TRANSPORT_CHIEF => 'Rol de Jefe de Transporte',
        Application::TYPE_CHILD_ADDITION => 'Declarar hijos',
        Application::TYPE_CHILD_REMOVAL => 'Quitar hijo',
        Application::TYPE_ABSENCE => 'Ausencia temporal',
        Application::TYPE_ITINERARY_LEAVE => 'Baja del itinerario',
        Application::TYPE_ITINERARY_CHIEF_LEAVE => 'Baja del rol de Jefe de itinerario',
        Application::TYPE_DRIVER_LEAVE => 'Baja del rol de Chofer',
        Application::TYPE_TRANSPORT_CHIEF_LEAVE => 'Baja del rol de Jefe de Transporte',
        Application::TYPE_ITINERARY_REMOVAL => 'Baja por inactividad',
    ];

    const DIRECTIONS = [TripLeg::DIRECTION_OUTBOUND => 'viaje de ida', TripLeg::DIRECTION_RETURN => 'viaje de regreso'];

    public static function for(Notice $notice): string
    {
        $application = $notice->application;
        $payload = is_array($notice->payload) ? $notice->payload : [];

        switch ($notice->type) {
            case Notice::TYPE_APPLICATION_RECEIVED:
                return self::workerName($application).' envió una solicitud de '.self::describe($application).'.';

            case Notice::TYPE_APPLICATION_RESOLVED:
                if (! $application) {
                    return 'Se resolvió una de sus solicitudes.';
                }
                if ($application->status === Application::STATUS_REJECTED) {
                    $text = 'Se rechazó su solicitud de '.self::describe($application).'. La rechazó '.self::resolverName($application).'.';

                    return $application->resolution_note ? $text.' Motivo: '.$application->resolution_note : $text;
                }

                return 'Se aprobó su solicitud de '.self::describe($application).'. La aprobó '.self::resolverName($application).'.';

            case Notice::TYPE_ROLE_ASSIGNED:
                return self::creatorName($application).' le asignó '.self::describe($application).'.';

            case Notice::TYPE_ROLE_REMOVED:
                return self::creatorName($application).' le dio de '.lcfirst(self::describe($application)).'.';

            case Notice::TYPE_RESIGNATION:
                return self::workerName($application).' se dio de '.lcfirst(self::describe($application)).'.';

            case Notice::TYPE_INACTIVITY_WARNING:
                return 'Lleva días sin viajar. Si no viaja pronto, saldrá de su itinerario por inactividad.';

            case Notice::TYPE_INACTIVITY_REMOVAL:
                return self::workerName($application).' salió del itinerario '.self::itineraryName($application).' por inactividad.';

            case Notice::TYPE_TRIP_NEEDS_REASSIGNMENT:
                return 'El viaje de '.self::tripName($notice->trip).' necesita otro chofer.';

            case Notice::TYPE_ACCESS_RECOVERY_REQUESTED:
                return 'Nueva solicitud «Olvidé algo».';

            case Notice::TYPE_PASSWORD_EXPIRING:
                $expiresAt = $notice->user ? app(Passwords::class)->expiresAt($notice->user) : null;

                return 'Su contraseña caduca el '.SpanishDate::date($expiresAt).'. Cámbiela en Mi perfil.';

            case Notice::TYPE_TRIP_STARTED:
                $delay = isset($payload['delayMinutes']) ? (int) $payload['delayMinutes'] : 0;

                return 'Comenzó el '.self::direction($payload).' de '.self::itineraryOf($notice->trip)
                    .($delay > 0 ? " ({$delay} min de atraso)." : ' a tiempo.');

            case Notice::TYPE_TRIP_DELAYED:
                $scheduled = isset($payload['scheduledAt']) ? Carbon::parse($payload['scheduledAt']) : null;

                return 'El '.self::direction($payload).' de '.self::itineraryOf($notice->trip).' está atrasado'
                    .($scheduled ? ': debía comenzar a las '.$scheduled->format('H:i').'.' : '.');

            case Notice::TYPE_TRIP_INCIDENT:
                $stop = isset($payload['stop']) ? $payload['stop'] : '';
                $what = [
                    TripLegIncident::TYPE_NOT_STOPPED => "no se detuvo en la parada {$stop}",
                    TripLegIncident::TYPE_SKIPPED => "se saltó la parada {$stop}",
                    TripLegIncident::TYPE_DEVIATION => 'se desvió del recorrido',
                ];
                $type = isset($payload['type']) ? $payload['type'] : '';

                return ucfirst(self::direction($payload)).' de '.self::itineraryOf($notice->trip).': '
                    .(isset($what[$type]) ? $what[$type] : 'incidencia').'.';
        }

        return '';
    }

    /**
     * "Itinerario y parada (Ruta Este · Parque)", "Declarar hijos (Pepito Pérez García)"…
     */
    public static function describe(?Application $application): string
    {
        if (! $application) {
            return 'una solicitud';
        }

        $name = isset(self::APPLICATION_TYPES[$application->type]) ? self::APPLICATION_TYPES[$application->type] : $application->type;
        $detail = [];

        if ($itinerary = $application->requested_itinerary) {
            $detail[] = $itinerary->name;
        }
        if ($stop = $application->requested_stop) {
            $detail[] = $stop->landmark;
        }
        if ($child = $application->related_child) {
            $detail[] = $child->fullName();
        }
        if ($absence = $application->absenceApplication) {
            if ($type = $absence->absenceType) {
                $detail[] = $type->name;
            }
            $detail[] = $absence->starts_on
                ? SpanishDate::date($absence->starts_on).' al '.SpanishDate::date($absence->ends_on)
                : 'indefinida';
        }

        return $detail ? $name.' ('.implode(' · ', $detail).')' : $name;
    }

    private static function workerName(?Application $application): string
    {
        $user = $application && $application->worker ? $application->worker->user : null;

        return $user ? $user->fullName() : 'Un trabajador';
    }

    private static function resolverName(Application $application): string
    {
        return $application->resolver ? $application->resolver->fullName() : 'el sistema';
    }

    private static function creatorName(?Application $application): string
    {
        return $application && $application->creator ? $application->creator->fullName() : 'Un superior';
    }

    private static function itineraryName(?Application $application): string
    {
        return $application && $application->requested_itinerary ? $application->requested_itinerary->name : '';
    }

    private static function itineraryOf(?Trip $trip): string
    {
        return $trip && $trip->itinerary ? $trip->itinerary->name : '';
    }

    private static function tripName(?Trip $trip): string
    {
        return $trip ? self::itineraryOf($trip).' del '.SpanishDate::dateTime($trip->departs_at) : '';
    }

    private static function direction(array $payload): string
    {
        $direction = isset($payload['direction']) ? $payload['direction'] : '';

        return isset(self::DIRECTIONS[$direction]) ? self::DIRECTIONS[$direction] : 'viaje';
    }
}
