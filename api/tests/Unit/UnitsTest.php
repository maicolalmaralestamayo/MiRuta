<?php

namespace Tests\Unit;

use App\Support\SettingCatalog;
use App\Support\Units;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

/**
 * Valores con unidades de los ajustes (docs/11 §11.40 y §11.43).
 */
class UnitsTest extends TestCase
{
    public static function durations(): array
    {
        return [
            ['10seg', 10],
            ['10min', 600],
            ['5hor', 18000],
            ['12hor30min', 45000],
            ['12hor30min30seg', 45030],
            ['1dia', 86400],
            ['2sem3dia', 17 * 86400],
            ['1mes', 30 * 86400],
            ['1ano', 365 * 86400],
            ['1ano6mes', 545 * 86400],
            ['1año', 365 * 86400],
            [' 1 HOR ', 3600],
            ['0seg', 0],
        ];
    }

    #[DataProvider('durations')]
    public function test_tiempos(string $text, int $seconds): void
    {
        $this->assertSame($seconds, Units::seconds($text));
    }

    public static function invalidDurations(): array
    {
        return [[''], ['10'], ['10m'], ['min'], ['10min10min'], ['10horas'], ['1,5hor'], ['-1min'], ['10km']];
    }

    #[DataProvider('invalidDurations')]
    public function test_tiempos_no_validos(string $text): void
    {
        $this->assertNull(Units::seconds($text));
    }

    public function test_distancias(): void
    {
        $this->assertSame(100, Units::meters('100m'));
        $this->assertSame(1000, Units::meters('1km'));
        $this->assertSame(1200, Units::meters('1km200m'));
        $this->assertNull(Units::meters('1km1km'));
        $this->assertNull(Units::meters('100'));
        $this->assertNull(Units::meters('10min'));
    }

    public function test_velocidades(): void
    {
        $this->assertEqualsWithDelta(10000 / 3600, Units::metersPerSecond('10km/hor'), 0.0001);
        $this->assertEqualsWithDelta(200 / 60, Units::metersPerSecond('200m/min'), 0.0001);
        $this->assertEqualsWithDelta(1.0, Units::metersPerSecond('120m/2min'), 0.0001);
        $this->assertNull(Units::metersPerSecond('10km'));
        $this->assertNull(Units::metersPerSecond('10km/'));
        $this->assertNull(Units::metersPerSecond('10min/hor'));
    }

    public function test_formato_mas_corto(): void
    {
        $this->assertSame('1hor', Units::formatSeconds(3600));
        $this->assertSame('12hor30min', Units::formatSeconds(45000));
        $this->assertSame('1km200m', Units::formatMeters(1200));
    }

    public function test_los_valores_por_omision_del_catalogo_son_validos_y_estan_en_rango(): void
    {
        foreach (SettingCatalog::SETTINGS as $key => $setting) {
            $definition = SettingCatalog::definition($key);
            $value = SettingCatalog::base($definition['type'], $definition['default']);
            $this->assertNotNull($value, $key);
            $this->assertGreaterThanOrEqual(SettingCatalog::base($definition['type'], $definition['min']), $value, $key);
            $this->assertLessThanOrEqual(SettingCatalog::base($definition['type'], $definition['max']), $value, $key);
        }
    }
}
