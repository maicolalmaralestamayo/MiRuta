<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Setting;
use App\Support\SettingCatalog;
use App\Support\Units;
use Illuminate\Support\Facades\Schema;

/**
 * Valores de los ajustes de la app (un solo nivel, docs/11 §11.38). El valor
 * guardado es el texto con unidades («10min»); el servidor lo interpreta.
 */
class Settings
{
    /** @var array<string, string>|null [clave => valor guardado] */
    private ?array $stored = null;

    /**
     * Texto del valor actual (el guardado o el de por omisión).
     */
    public function raw(string $key): string
    {
        $this->ensureExists($key);
        $stored = $this->stored();

        return isset($stored[$key]) ? $stored[$key] : (string) SettingCatalog::SETTINGS[$key][3];
    }

    /**
     * Valor en la unidad base: segundos, metros, metros por segundo o entero.
     */
    public function value(string $key)
    {
        $type = SettingCatalog::SETTINGS[$key][2] ?? null;
        $value = SettingCatalog::base((string) $type, $this->raw($key));

        // Un valor guardado que ya no se entiende: vale el de por omisión.
        return $value ?? SettingCatalog::base($type, SettingCatalog::SETTINGS[$key][3]);
    }

    public function int(string $key): int
    {
        return (int) $this->value($key);
    }

    public function seconds(string $key): int
    {
        return (int) $this->value($key);
    }

    public function meters(string $key): int
    {
        return (int) $this->value($key);
    }

    public function metersPerSecond(string $key): float
    {
        return (float) $this->value($key);
    }

    /**
     * Comprueba un valor nuevo (tipo, mínimo y máximo) y lo devuelve normalizado.
     */
    public function normalize(string $key, $value, string $pointer = '/data/attributes/value'): string
    {
        $definition = SettingCatalog::definition($key);
        $type = $definition['type'];
        $fail = fn (string $detail) => new JsonApiException(422, 'SETTING_INVALID', 'Valor no válido', $detail, ['pointer' => $pointer]);

        if ($type === SettingCatalog::TYPE_INTEGER && is_int($value)) {
            $value = (string) $value;
        }

        if (! is_string($value)) {
            throw $fail('El valor debe ser texto, por ejemplo «'.$definition['default'].'».');
        }

        $value = $type === SettingCatalog::TYPE_INTEGER ? trim($value) : Units::clean($value);
        $base = SettingCatalog::base($type, $value);

        if ($base === null) {
            throw $fail(match ($type) {
                SettingCatalog::TYPE_DURATION => 'Escriba un tiempo con sus unidades (seg, min, hor, dia, sem, mes, ano), por ejemplo «10min» o «12hor30min».',
                SettingCatalog::TYPE_DISTANCE => 'Escriba una distancia con sus unidades (m, km), por ejemplo «100m» o «1km200m».',
                SettingCatalog::TYPE_SPEED => 'Escriba una velocidad como distancia/tiempo, por ejemplo «10km/hor» o «200m/min».',
                default => 'El valor debe ser un número entero.',
            });
        }

        $min = SettingCatalog::base($type, $definition['min']);
        $max = SettingCatalog::base($type, $definition['max']);

        if ($base < $min) {
            throw $fail("El valor no puede ser menor que {$definition['min']}.");
        }

        if ($base > $max) {
            throw $fail("El valor no puede ser mayor que {$definition['max']}.");
        }

        return $value;
    }

    public function set(string $key, string $value): void
    {
        Setting::updateOrCreate(['key' => $key], ['value' => $value]);
        $this->flush();
    }

    /**
     * Fecha del último cambio de un ajuste (para que la app sepa si recargarlos).
     */
    public function version(): ?string
    {
        $date = Setting::max('updated_at');

        return $date ? (string) \Carbon\Carbon::parse($date)->toIso8601String() : null;
    }

    public function flush(): void
    {
        $this->stored = null;
    }

    private function ensureExists(string $key): void
    {
        if (! SettingCatalog::has($key)) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', "No existe el ajuste \"{$key}\".");
        }
    }

    private function stored(): array
    {
        if ($this->stored === null) {
            try {
                $this->stored = Setting::pluck('value', 'key')->all();
            } catch (\Throwable $e) {
                // Sin base de datos instalada valen los de por omisión.
                $this->stored = [];
            }
        }

        return $this->stored;
    }
}
