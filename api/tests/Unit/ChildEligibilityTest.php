<?php

use App\Services\ChildEligibility;
use App\Support\CardNumber;
use Carbon\CarbonImmutable;
use Laravel\Lumen\Testing\DatabaseMigrations;

class ChildEligibilityTest extends TestCase
{
    use DatabaseMigrations;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed', ['--class' => \Database\Seeders\SettingDefinitionSeeder::class]);
    }

    /**
     * @dataProvider cases
     */
    public function testHastaEl31DeAgostoSiguienteAlCumpleanos(string $card, string $until)
    {
        $eligibility = app(ChildEligibility::class);

        $this->assertSame($until, $eligibility->eligibleUntil(CardNumber::tryParse($card))->toDateString());
    }

    public function cases(): array
    {
        return [
            'cumple 16 en marzo: hasta agosto de ese año' => ['11031060011', '2027-08-31'],
            'cumple 16 en octubre: hasta agosto del año siguiente' => ['11101560011', '2028-08-31'],
            'cumple 16 el 31 de agosto: ese mismo día' => ['11083160011', '2027-08-31'],
            'cumple 16 el 1 de septiembre: año siguiente' => ['11090160011', '2028-08-31'],
            '29 de febrero, año límite bisiesto' => ['12022960011', '2028-08-31'],
        ];
    }

    public function testDerechoEnUnaFecha()
    {
        $eligibility = app(ChildEligibility::class);
        $card = CardNumber::tryParse('11031060011');

        $this->assertTrue($eligibility->isEligible($card, CarbonImmutable::create(2027, 8, 31)));
        $this->assertFalse($eligibility->isEligible($card, CarbonImmutable::create(2027, 9, 1)));
    }
}
