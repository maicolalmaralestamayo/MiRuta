<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\EntitySetting;
use App\Models\Itinerary;
use App\Models\ItinerarySetting;
use App\Models\ItineraryStop;
use App\Models\ItineraryStopSetting;
use App\Models\Setting;
use App\Models\SettingDefinition;
use App\Models\UserSetting;
use App\Models\User;

/**
 * Valor efectivo y validación de los ajustes (docs/07-algoritmos.md §7.5).
 *
 * Niveles (docs/11 §11.17), gana el más concreto: usuario (los que puede
 * cambiar) → parada del itinerario (stop_level) → itinerario
 * (itinerary_level) → Entidad (nivel Entidad) → app → valor por defecto.
 */
class Settings
{
    /** @var array [clave => SettingDefinition] */
    private $definitions;

    /** @var array [id de definición => valor global] */
    private $globals;

    /** @var array [id de Entidad => [id de definición => valor]] */
    private $entityValues = [];

    /** @var array [id de itinerario => [id de definición => valor]] */
    private $itineraryValues = [];

    /** @var array ["itinerario-parada" => [id de definición => valor]] */
    private $stopValues = [];

    /**
     * Valor efectivo convertido a su tipo (ver los niveles arriba); nunca
     * menor que su ajuste mínimo. Sin $entityId se usa la del itinerario o,
     * si la persona pertenece a una sola Entidad, la suya.
     */
    public function get(string $key, ?User $user = null, ?int $entityId = null, ?int $itineraryId = null, ?int $stopId = null)
    {
        $definition = $this->definition($key);

        return $this->cast($definition, $this->effectiveRaw($definition, $user, $entityId, $itineraryId, $stopId));
    }

    public function int(string $key, ?User $user = null, ?int $entityId = null, ?int $itineraryId = null, ?int $stopId = null): int
    {
        return (int) $this->get($key, $user, $entityId, $itineraryId, $stopId);
    }

    /**
     * Valor de un ajuste de nivel Entidad para una Entidad.
     */
    public function forEntity(string $key, ?int $entityId)
    {
        return $this->get($key, null, $entityId);
    }

    /**
     * Valor sin convertir, ya ajustado al mínimo (como se envía en la API).
     */
    public function effectiveRaw(SettingDefinition $definition, ?User $user = null, ?int $entityId = null, ?int $itineraryId = null, ?int $stopId = null): string
    {
        if ($entityId === null && $itineraryId !== null) {
            $entityId = $this->entityOfItinerary($itineraryId);
        }

        if ($entityId === null && $user) {
            $entityId = $user->singleEntityId();
        }

        return $this->applyMinimum($definition, $this->rawValue($definition, $user, $entityId, $itineraryId, $stopId));
    }

    /**
     * Valor por encima del usuario: el de la parada, el del itinerario, el de
     * la Entidad o el de la app.
     */
    public function inheritedRaw(SettingDefinition $definition, ?int $entityId, ?int $itineraryId = null, ?int $stopId = null): string
    {
        if ($entityId === null && $itineraryId !== null) {
            $entityId = $this->entityOfItinerary($itineraryId);
        }

        return $this->applyMinimum($definition, $this->rawValue($definition, null, $entityId, $itineraryId, $stopId));
    }

    public function definition(string $key): SettingDefinition
    {
        $definitions = $this->definitions();

        if (! isset($definitions[$key])) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', "No existe el ajuste \"{$key}\".");
        }

        return $definitions[$key];
    }

    /**
     * @return SettingDefinition[] [clave => definición]
     */
    public function definitions(): array
    {
        if ($this->definitions === null) {
            $this->definitions = SettingDefinition::with('options', 'minSettingDefinition', 'maxSettingDefinition')->orderBy('key')->get()->keyBy('key')->all();
        }

        return $this->definitions;
    }

    /**
     * Comprueba un valor nuevo y lo devuelve normalizado como texto.
     * Si el valor no es válido lanza SETTING_OUT_OF_RANGE.
     */
    public function normalize(SettingDefinition $definition, $value, string $pointer = '/data/attributes/value'): string
    {
        $fail = function (string $detail) use ($pointer) {
            return new JsonApiException(422, 'SETTING_OUT_OF_RANGE', 'Valor no válido', $detail, ['pointer' => $pointer]);
        };

        switch ($definition->value_type) {
            case SettingDefinition::TYPE_INTEGER:
                if (is_string($value) && preg_match('/^-?\d+$/', $value)) {
                    $value = (int) $value;
                }
                if (! is_int($value)) {
                    throw $fail('El valor debe ser un número entero.');
                }
                $min = $definition->min_value;
                if ($definition->minSettingDefinition) {
                    $globalMin = $this->int($definition->minSettingDefinition->key);
                    $min = $min === null ? $globalMin : max($min, $globalMin);
                }
                if ($min !== null && $value < $min) {
                    throw $fail("El valor no puede ser menor que {$min}.");
                }
                $max = $definition->max_value;
                if ($definition->maxSettingDefinition) {
                    $globalMax = $this->int($definition->maxSettingDefinition->key);
                    $max = $max === null ? $globalMax : min($max, $globalMax);
                }
                if ($max !== null && $value > $max) {
                    throw $fail("El valor no puede ser mayor que {$max}.");
                }

                return (string) $value;

            case SettingDefinition::TYPE_BOOLEAN:
                if (in_array($value, [true, 1, '1', 'true'], true)) {
                    return '1';
                }
                if (in_array($value, [false, 0, '0', 'false'], true)) {
                    return '0';
                }
                throw $fail('El valor debe ser verdadero o falso.');

            case SettingDefinition::TYPE_TIME:
                if (! is_string($value) || ! preg_match('/^([01]\d|2[0-3]):[0-5]\d$/', $value)) {
                    throw $fail('El valor debe ser una hora con el formato HH:MM.');
                }

                return $value;

            case SettingDefinition::TYPE_OPTION:
                if (! is_string($value) || ! $definition->options->contains('value', $value)) {
                    throw $fail('El valor debe ser una de las opciones: '.$definition->options->pluck('value')->implode(', ').'.');
                }

                return $value;

            default:
                if (! is_string($value)) {
                    throw $fail('El valor debe ser texto.');
                }
                $length = mb_strlen($value);
                if ($definition->min_value !== null && $length < $definition->min_value) {
                    throw $fail("El texto debe tener al menos {$definition->min_value} caracteres.");
                }
                if ($definition->max_value !== null && $length > $definition->max_value) {
                    throw $fail("El texto no puede tener más de {$definition->max_value} caracteres.");
                }

                return $value;
        }
    }

    /**
     * Convierte el texto guardado al tipo del ajuste.
     */
    public function cast(SettingDefinition $definition, string $raw)
    {
        switch ($definition->value_type) {
            case SettingDefinition::TYPE_INTEGER:
                return (int) $raw;
            case SettingDefinition::TYPE_BOOLEAN:
                return $raw === '1';
            default:
                return $raw;
        }
    }

    /**
     * Olvida los valores leídos (tras modificar un ajuste).
     */
    public function flush(): void
    {
        $this->definitions = null;
        $this->globals = null;
        $this->entityValues = [];
        $this->itineraryValues = [];
        $this->stopValues = [];
    }

    private function rawValue(SettingDefinition $definition, ?User $user, ?int $entityId, ?int $itineraryId = null, ?int $stopId = null): string
    {
        if ($user && $definition->user_overridable) {
            $userValue = UserSetting::where('user_id', $user->id)
                ->where('setting_definition_id', $definition->id)
                ->value('value');

            if ($userValue !== null) {
                return $userValue;
            }
        }

        if ($itineraryId !== null && $stopId !== null && $definition->stop_level) {
            $key = $itineraryId.'-'.$stopId;

            if (! isset($this->stopValues[$key])) {
                $itineraryStopId = ItineraryStop::where('itinerary_id', $itineraryId)->where('stop_id', $stopId)->value('id');
                $this->stopValues[$key] = $itineraryStopId
                    ? ItineraryStopSetting::where('itinerary_stop_id', $itineraryStopId)->pluck('value', 'setting_definition_id')->all()
                    : [];
            }

            if (isset($this->stopValues[$key][$definition->id])) {
                return $this->stopValues[$key][$definition->id];
            }
        }

        if ($itineraryId !== null && $definition->itinerary_level) {
            if (! isset($this->itineraryValues[$itineraryId])) {
                $this->itineraryValues[$itineraryId] = ItinerarySetting::where('itinerary_id', $itineraryId)->pluck('value', 'setting_definition_id')->all();
            }

            if (isset($this->itineraryValues[$itineraryId][$definition->id])) {
                return $this->itineraryValues[$itineraryId][$definition->id];
            }
        }

        if ($entityId !== null && $definition->level === SettingDefinition::LEVEL_ENTITY) {
            if (! isset($this->entityValues[$entityId])) {
                $this->entityValues[$entityId] = EntitySetting::where('entity_id', $entityId)->pluck('value', 'setting_definition_id')->all();
            }

            if (isset($this->entityValues[$entityId][$definition->id])) {
                return $this->entityValues[$entityId][$definition->id];
            }
        }

        $globals = $this->globals();

        return isset($globals[$definition->id]) ? $globals[$definition->id] : $definition->default_value;
    }

    private function applyMinimum(SettingDefinition $definition, string $raw): string
    {
        if ($definition->value_type !== SettingDefinition::TYPE_INTEGER) {
            return $raw;
        }
        $value = (int) $raw;
        if ($definition->minSettingDefinition) {
            $value = max($value, $this->int($definition->minSettingDefinition->key));
        }
        if ($definition->maxSettingDefinition) {
            $value = min($value, $this->int($definition->maxSettingDefinition->key));
        }

        return (string) $value;
    }

    private function entityOfItinerary(int $itineraryId): ?int
    {
        $entityId = Itinerary::withTrashed()->whereKey($itineraryId)->value('entity_id');

        return $entityId === null ? null : (int) $entityId;
    }

    private function globals(): array
    {
        if ($this->globals === null) {
            $this->globals = Setting::pluck('value', 'setting_definition_id')->all();
        }

        return $this->globals;
    }
}
