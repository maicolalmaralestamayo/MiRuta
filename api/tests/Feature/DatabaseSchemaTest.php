<?php

use App\Models\ConversationTopic;
use App\Models\Rank;
use App\Models\SettingDefinition;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Lumen\Testing\DatabaseMigrations;

class DatabaseSchemaTest extends TestCase
{
    use DatabaseMigrations;

    public function testTodasLasTablasTienenFechasYBorradoLogico()
    {
        $tables = array_map(function ($row) {
            return array_values((array) $row)[0];
        }, DB::select('SHOW TABLES'));

        $tables = array_diff($tables, ['migrations']);
        $this->assertNotEmpty($tables);

        foreach ($tables as $table) {
            foreach (['created_at', 'updated_at', 'deleted_at'] as $column) {
                $this->assertTrue(Schema::hasColumn($table, $column), "Falta {$table}.{$column}");
            }
        }
    }

    public function testSeedersCarganLosDatosDeReferencia()
    {
        $this->artisan('db:seed');

        $this->assertSame(18, Rank::count());
        $this->assertSame('Coronel', Rank::where('precedence', 1)->value('name'));
        $this->assertSame('Funcionarios', Rank::where('precedence', 4)->value('name'));
        $this->assertSame('Otra categoría', Rank::where('precedence', 18)->value('name'));
        $this->assertSame(9, ConversationTopic::count());
        $this->assertSame('16', SettingDefinition::where('key', 'child_max_age')->value('default_value'));
        $this->assertSame('transport_chief', SettingDefinition::where('key', 'child_max_age')->value('editable_by'));
    }

    public function testLosSeedersSePuedenRepetir()
    {
        $this->artisan('db:seed');
        $counts = [Rank::count(), ConversationTopic::count(), SettingDefinition::count(), DB::table('setting_options')->count()];

        $this->artisan('db:seed');

        $this->assertSame($counts, [Rank::count(), ConversationTopic::count(), SettingDefinition::count(), DB::table('setting_options')->count()]);
    }

    public function testAjustesDeUsuarioConMinimoGlobalYOpciones()
    {
        $this->artisan('db:seed');

        $setting = SettingDefinition::where('key', 'trips_poll_background_minutes')->first();
        $this->assertTrue($setting->user_overridable);
        $this->assertSame('min_background_poll_minutes', $setting->minSettingDefinition->key);

        $scope = SettingDefinition::where('key', 'stop_notice_scope')->first();
        $this->assertSame(['all', 'none', 'previous'], $scope->options()->orderBy('value')->pluck('value')->all());
        $this->assertSame('previous', $scope->default_value);

        foreach (SettingDefinition::where('value_type', 'option')->get() as $option) {
            $this->assertTrue(
                $option->options()->where('value', $option->default_value)->exists(),
                "El valor por defecto de {$option->key} no está entre sus opciones"
            );
        }
    }
}
