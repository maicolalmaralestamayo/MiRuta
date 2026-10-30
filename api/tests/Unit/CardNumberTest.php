<?php

use App\Support\CardNumber;
use Carbon\CarbonImmutable;

class CardNumberTest extends TestCase
{
    protected function tearDown(): void
    {
        CarbonImmutable::setTestNow();
        parent::tearDown();
    }

    public function testEjemploDeLaDocumentacion()
    {
        $card = CardNumber::tryParse('92071648863');

        $this->assertNotNull($card);
        $this->assertSame('1992-07-16', $card->birthDate()->toDateString());
        $this->assertSame('M', $card->sex(), 'El penúltimo dígito (6) es par');
    }

    /**
     * @dataProvider centuries
     */
    public function testElSeptimoDigitoIndicaElSiglo(string $card, string $birthDate)
    {
        $this->assertSame($birthDate, CardNumber::tryParse($card)->birthDate()->toDateString());
    }

    public function centuries(): array
    {
        return [
            'dígito 9 → 1800' => ['99123190011', '1899-12-31'],
            'dígito 0 → 1900' => ['85010100011', '1985-01-01'],
            'dígito 5 → 1900' => ['85010150011', '1985-01-01'],
            'dígito 6 → 2000' => ['05031560011', '2005-03-15'],
            'dígito 8 → 2000' => ['05031580011', '2005-03-15'],
        ];
    }

    public function testPenultimoDigitoImparEsFemenino()
    {
        $this->assertSame('F', CardNumber::tryParse('92071648873')->sex());
    }

    public function testFebrero29SoloEnAnosBisiestos()
    {
        $this->assertNotNull(CardNumber::tryParse('00022960011'), '2000 es bisiesto');
        $this->assertNull(CardNumber::tryParse('01022960011'), '2001 no es bisiesto');
    }

    /**
     * @dataProvider invalidCards
     */
    public function testCarnesInvalidos($card)
    {
        $this->assertNull(CardNumber::tryParse($card));
        $this->assertFalse(CardNumber::isValid($card));
    }

    public function invalidCards(): array
    {
        return [
            'vacío' => [''],
            'diez dígitos' => ['9207164886'],
            'doce dígitos' => ['920716488631'],
            'con letras' => ['9207164886A'],
            'con espacios' => ['92071 648863'],
            'no es texto' => [92071648863],
            'mes 13' => ['92131648863'],
            '30 de febrero' => ['92023048863'],
            'día 0' => ['92070048863'],
        ];
    }

    public function testFechaFuturaEsInvalida()
    {
        CarbonImmutable::setTestNow(CarbonImmutable::create(2026, 11, 2));

        $this->assertNull(CardNumber::tryParse('26110360011'), '3 de noviembre de 2026 es mañana');
        $this->assertNotNull(CardNumber::tryParse('26110260011'), 'hoy es válido');
    }

    public function testHuellaDeterministaYCifradoReversible()
    {
        $card = CardNumber::tryParse('92071648863');

        $this->assertSame($card->hash(), CardNumber::hashOf('92071648863'));
        $this->assertSame(64, strlen($card->hash()));
        $this->assertNotSame($card->hash(), CardNumber::hashOf('92071648873'));

        $encrypted = $card->encrypt();
        $this->assertStringNotContainsString('92071648863', $encrypted);
        $this->assertSame('92071648863', \Illuminate\Support\Facades\Crypt::decryptString($encrypted));
    }
}
