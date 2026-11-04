<?php

use App\Models\ConversationTopic;
use App\Models\Role;
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

        $this->assertSame(['Chofer', 'Jefe de Transporte', 'Jefe de itinerario', 'Trabajador'], Role::pluck('name')->sort()->values()->all());
        $this->assertSame('Trabajador', Role::where('is_default', true)->value('name'));
        $this->assertTrue((bool) Role::where('name', 'Jefe de itinerario')->value('itinerary_scoped'));
        $this->assertFalse((bool) Role::where('name', 'Trabajador')->value('requestable'));
        // El Chofer lo aprueba el Jefe de Transporte (y el Administrador, siempre).
        $driver = Role::where('name', 'Chofer')->first();
        $this->assertSame([Role::where('name', 'Jefe de Transporte')->value('id')], $driver->approverRoleIds());
        $this->assertSame([], Role::where('name', 'Jefe de itinerario')->first()->approverRoleIds());
        $this->assertSame('entity', $driver->permissions()->where('operation', 'tracking.drive')->value('scope'));
        $this->assertSame('itinerary', Role::where('name', 'Jefe de itinerario')->first()->permissions()->where('operation', 'workers.view_identity_card')->value('scope'));
        $this->assertTrue((bool) SettingDefinition::where('key', 'trip_delay_tolerance_minutes')->value('itinerary_level'));
        $this->assertTrue((bool) SettingDefinition::where('key', 'stop_min_dwell_seconds')->value('stop_level'));
        $this->assertFalse((bool) SettingDefinition::where('key', 'child_max_age')->value('itinerary_level'));
        $this->assertSame(9, ConversationTopic::count());
        $this->assertSame('16', SettingDefinition::where('key', 'child_max_age')->value('default_value'));
        $this->assertSame('entity', SettingDefinition::where('key', 'child_max_age')->value('level'));
        $this->assertSame('app', SettingDefinition::where('key', 'conversation_retention_days')->value('level'));
        $this->assertSame('365', SettingDefinition::where('key', 'password_expiry_days')->value('default_value'));
        $this->assertSame('5', SettingDefinition::where('key', 'password_history_count')->value('default_value'));
    }

    public function testLosSeedersSePuedenRepetir()
    {
        $this->artisan('db:seed');
        $counts = [Role::count(), DB::table('role_permissions')->count(), ConversationTopic::count(), SettingDefinition::count(), DB::table('setting_options')->count()];

        $this->artisan('db:seed');

        $this->assertSame($counts, [Role::count(), DB::table('role_permissions')->count(), ConversationTopic::count(), SettingDefinition::count(), DB::table('setting_options')->count()]);
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
