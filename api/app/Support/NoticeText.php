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
 * y, si se rechazó, el motivo (docs/09 §16). Los avisos sin solicitud
 * (roles, Entidades, itinerario) llevan sus datos en el payload.
 */
class NoticeText
{
    const APPLICATION_TYPES = [
        Application::TYPE_ENTITY_MEMBERSHIP => 'entrar en una Entidad',
        Application::TYPE_ITINERARY_MEMBERSHIP => 'itinerario y parada',
        Application::TYPE_ROLE => 'rol',
    ];

    const DIRECTIONS = [TripLeg::DIRECTION_OUTBOUND => 'viaje de ida', TripLeg::DIRECTION_RETURN => 'viaje de regreso'];

    public static function for(Notice $notice): string
    {
        $application = $notice->application;
        $payload = is_array($notice->payload) ? $notice->payload : [];
        $by = isset($payload['by']) && $payload['by'] ? $payload['by'] : 'Un superior';

        switch ($notice->type) {
            case Notice::TYPE_APPLICATION_RECEIVED:
                return self::applicantName($application).' envió una solicitud de '.self::describe($application).'.';

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
                return $by.' le asignó el rol '.self::role($payload).'.';

            case Notice::TYPE_ROLE_REMOVED:
                return $by.' le quitó el rol '.self::role($payload).'.';

            case Notice::TYPE_RESIGNATION:
                return (isset($payload['person']) ? $payload['person'] : 'Un trabajador').' se dio de baja del rol '.self::role($payload).'.';

            case Notice::TYPE_ENTITY_ADDED:
                return $by.' le añadió a la Entidad '.self::value($payload, 'entity').'.';

            case Notice::TYPE_ENTITY_REMOVED:
                return $by.' le dio de baja de la Entidad '.self::value($payload, 'entity').'.';

            case Notice::TYPE_ITINERARY_ASSIGNED:
                return $by.' le asignó el itinerario '.self::value($payload, 'itinerary')
                    .(isset($payload['stop']) && $payload['stop'] ? ' con la parada '.$payload['stop'] : '').'.';

            case Notice::TYPE_ITINERARY_REMOVED:
                return $by.' le dio de baja del itinerario '.self::value($payload, 'itinerary').'.';

            case Notice::TYPE_INACTIVITY_WARNING:
                return 'Lleva días sin viajar. Si no viaja pronto, saldrá de su itinerario'
                    .(isset($payload['itinerary']) && $payload['itinerary'] ? ' '.$payload['itinerary'] : '').' por inactividad.';

            case Notice::TYPE_INACTIVITY_REMOVAL:
                return (isset($payload['person']) ? $payload['person'] : 'Un trabajador').' salió del itinerario '.self::value($payload, 'itinerary').' por inactividad.';

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
     * "itinerario y parada (UMIM · Ruta Este · Parque)", "rol (UMIM · Chofer)"…
     */
    public static function describe(?Application $application): string
    {
        if (! $application) {
            return 'una solicitud';
        }

        $name = isset(self::APPLICATION_TYPES[$application->type]) ? self::APPLICATION_TYPES[$application->type] : $application->type;
        $detail = [];

        if ($entity = $application->entity) {
            $detail[] = $entity->abbreviation;
        }
        if ($role = $application->role) {
            $detail[] = $role->name;
        }
        if ($itinerary = $application->itinerary) {
            $detail[] = $itinerary->name;
        }
        if ($stop = $application->stop) {
            $detail[] = $stop->landmark;
        }

        return $detail ? $name.' ('.implode(' · ', $detail).')' : $name;
    }

    private static function applicantName(?Application $application): string
    {
        return $application && $application->user ? $application->user->fullName() : 'Un trabajador';
    }

    private static function resolverName(Application $application): string
    {
        return $application->resolver ? $application->resolver->fullName() : 'el sistema';
    }

    private static function role(array $payload): string
    {
        $text = self::value($payload, 'role');

        if (isset($payload['itinerary']) && $payload['itinerary']) {
            $text .= ' ('.$payload['itinerary'].')';
        } elseif (isset($payload['entity']) && $payload['entity']) {
            $text .= ' ('.$payload['entity'].')';
        }

        return $text;
    }

    private static function value(array $payload, string $key): string
    {
        return isset($payload[$key]) && $payload[$key] !== null ? (string) $payload[$key] : '';
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
