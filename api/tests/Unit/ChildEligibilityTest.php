<?php

use App\Services\ChildEligibility;
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
    public function testHastaEl31DeAgostoSiguienteAlCumpleanos(string $birth, string $until)
    {
        $eligibility = app(ChildEligibility::class);

        $this->assertSame($until, $eligibility->eligibleUntil($birth, null)->toDateString());
    }

    public function cases(): array
    {
        return [
            'cumple 16 en marzo: hasta agosto de ese año' => ['2011-03-10', '2027-08-31'],
            'cumple 16 en octubre: hasta agosto del año siguiente' => ['2011-10-15', '2028-08-31'],
            'cumple 16 el 31 de agosto: ese mismo día' => ['2011-08-31', '2027-08-31'],
            'cumple 16 el 1 de septiembre: año siguiente' => ['2011-09-01', '2028-08-31'],
            '29 de febrero, año límite bisiesto' => ['2012-02-29', '2028-08-31'],
        ];
    }

    public function testDerechoEnUnaFecha()
    {
        $eligibility = app(ChildEligibility::class);
        $this->assertTrue($eligibility->isEligible('2011-03-10', null, CarbonImmutable::create(2027, 8, 31)));
        $this->assertFalse($eligibility->isEligible('2011-03-10', null, CarbonImmutable::create(2027, 9, 1)));
    }

    public function testEdadMaximaDeLaEntidad()
    {
        $entity = $this->defaultEntity();
        $definition = \App\Models\SettingDefinition::where('key', 'child_max_age')->first();
        \App\Models\EntitySetting::create(['entity_id' => $entity->id, 'setting_definition_id' => $definition->id, 'value' => '12']);

        $this->assertSame('2023-08-31', app(ChildEligibility::class)->eligibleUntil('2011-03-10', $entity->id)->toDateString());
        $this->assertSame('2027-08-31', app(ChildEligibility::class)->eligibleUntil('2011-03-10', null)->toDateString());
    }
}
