<?php

namespace Tests\Unit;

use App\Support\IdentityCard;
use Carbon\CarbonImmutable;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase as PlainTestCase;

/**
 * Carné de identidad (docs/11 §11.2).
 */
class IdentityCardTest extends PlainTestCase
{
    #[DataProvider('cards')]
    public function testFechaDeNacimientoYSexo(string $card, string $birthDate, string $sex)
    {
        $this->assertNull(IdentityCard::error($card));
        $this->assertSame($birthDate, IdentityCard::birthDate($card)->toDateString());
        $this->assertSame($sex, IdentityCard::sex($card));
    }

    public static function cards(): array
    {
        return [
            'siglo 9 → 1800' => ['95061292531', '1895-06-12', 'F'],
            'siglo 0 → 1900' => ['85032002345', '1985-03-20', 'M'],
            'siglo 5 → 1900' => ['70010152391', '1970-01-01', 'F'],
            'siglo 6 → 2000' => ['10123164521', '2010-12-31', 'M'],
            'siglo 8 → 2000' => ['00022985671', '2000-02-29', 'F'],
        ];
    }

    #[DataProvider('invalid')]
    public function testNoValidos(string $card)
    {
        $this->assertNotNull(IdentityCard::error($card));
    }

    public static function invalid(): array
    {
        return [
            'diez dígitos' => ['8503200234'],
            'doce dígitos' => ['850320023456'],
            'letras' => ['85032A02345'],
            'mes 0' => ['85002002345'],
            '29 de febrero no bisiesto' => ['01022962345'],
            'futuro' => ['30010182345'],
        ];
    }

    public function testEspaciosYHuella()
    {
        $this->assertTrue(IdentityCard::isValid(' 85032 002345 '));
        $this->assertSame('85032002345', IdentityCard::normalize(' 85032 002345 '));
    }

    public function testConstruirParaPruebas()
    {
        $card = IdentityCard::make('1999-07-04', 'F', 3);

        $this->assertNull(IdentityCard::error($card));
        $this->assertSame('1999-07-04', IdentityCard::birthDate($card)->toDateString());
        $this->assertSame('F', IdentityCard::sex($card));
        $this->assertSame('M', IdentityCard::sex(IdentityCard::make('2005-01-31', 'M', 7)));
        $this->assertSame('2005-01-31', IdentityCard::birthDate(IdentityCard::make('2005-01-31', 'M', 7))->toDateString());
        $this->assertTrue(CarbonImmutable::parse('1895-01-01')->equalTo(IdentityCard::birthDate(IdentityCard::make('1895-01-01', 'F', 1))));
    }
}
