<?php

namespace Tests\Feature;

use App\Models\Trip;
use App\Services\ScheduledTasks;
use Carbon\Carbon;
use Tests\TestCase;

/**
 * Mantenimiento del servidor por la API (docs/11 §11.55): sin SSH ni cron.
 */
class MaintenanceTest extends TestCase
{
    protected function tearDown(): void
    {
        @unlink(app(ScheduledTasks::class)->statePath());
        parent::tearDown();
    }

    public function test_con_la_clave_de_mantenimiento_o_como_administrador(): void
    {
        $this->jsonApi('GET', '/api/v1/server-status')->assertStatus(401);
        $this->jsonApi('GET', '/api/v1/server-status', null, ['X-Maintenance-Key' => 'mala-clave-de-mantenimiento'])
            ->assertForbidden()->assertJsonPath('errors.0.code', 'MAINTENANCE_KEY_INVALID');
        $this->jsonApiAs($this->createUser(), 'GET', '/api/v1/server-status')->assertForbidden();

        $status = $this->jsonApi('GET', '/api/v1/server-status', null, ['X-Maintenance-Key' => 'clave-de-mantenimiento-pruebas'])
            ->assertOk()->json('data.attributes');
        $this->assertTrue($status['phpSupported']);
        $this->assertTrue($status['database']['connected']);
        $this->assertTrue($status['database']['installed']);
        $this->assertSame([], $status['database']['pendingMigrations']);
        $this->assertContains('run-tasks', $status['commands']);

        $this->jsonApiAs($this->createAdmin(), 'GET', '/api/v1/server-status')->assertOk();
    }

    public function test_ordenes_migrate_install_tareas_y_registro(): void
    {
        $key = ['X-Maintenance-Key' => 'clave-de-mantenimiento-pruebas'];
        $run = fn (string $command) => $this->jsonApi('POST', '/api/v1/maintenance-runs', self::resource('maintenance-runs', ['command' => $command]), $key);

        $run('migrate')->assertCreated()->assertJsonPath('data.attributes.ok', true);
        $run('install')->assertStatus(409)->assertJsonPath('errors.0.code', 'ALREADY_INSTALLED');
        $run('borrar-todo')->assertStatus(422);
        $run('log')->assertCreated();

        // Las tareas programadas revisan los viajes (sin cron).
        $itinerary = $this->createItinerary($this->createEntity());
        $trip = Trip::create(['itinerary_id' => $itinerary->id, 'direction' => 'ida', 'date' => Carbon::today(), 'departure_time' => '00:00',
            'departs_at' => Carbon::now()->subHours(6), 'vehicle_type_id' => $this->vehicleType()->id,
            'status' => Trip::PLANNED, 'status_changed_at' => Carbon::now()->subHours(6)]);
        $output = $run('run-tasks')->assertCreated()->assertJsonPath('data.attributes.ok', true)->json('data.attributes.output');
        $this->assertStringContainsString('viajes:revisar: bien', $output);
        $this->assertNull(Trip::find($trip->id));
        $this->assertSame('No había tareas pendientes.', $run('run-tasks')->json('data.attributes.output'));
    }

    public function test_frecuencias_de_las_tareas(): void
    {
        $tasks = app(ScheduledTasks::class);
        $now = Carbon::create(2026, 11, 9, 10, 30);

        $this->assertTrue($tasks->isDue('minute', null, $now));
        $this->assertFalse($tasks->isDue('minute', $now->copy(), $now));
        $this->assertTrue($tasks->isDue('hour', $now->copy()->subHour(), $now));
        $this->assertTrue($tasks->isDue('02:10', $now->copy()->subDay(), $now));
        $this->assertFalse($tasks->isDue('02:10', $now->copy()->setTime(3, 0), $now));
    }
}
