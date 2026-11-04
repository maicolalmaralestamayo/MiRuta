<?php

use App\Services\ScheduledTasks;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Lumen\Testing\DatabaseMigrations;

/**
 * Mantenimiento del servidor desde la app (hospedaje sin SSH) y tareas
 * programadas sin cron.
 */
class MaintenanceTest extends TestCase
{
    use DatabaseMigrations;

    private const KEY = 'clave-de-mantenimiento-0123456789';

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
        config(['mitransporte.maintenance_key' => self::KEY]);
        @unlink(app(ScheduledTasks::class)->statePath());
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        @unlink(app(ScheduledTasks::class)->statePath());
        parent::tearDown();
    }

    public function test_status_with_the_maintenance_key()
    {
        $this->jsonApi('GET', '/api/v1/server-status', null, ['X-Maintenance-Key' => self::KEY]);

        $this->seeStatusCode(200);
        $attributes = json_decode($this->response->getContent(), true)['data']['attributes'];
        $this->assertSame(PHP_VERSION, $attributes['phpVersion']);
        $this->assertTrue($attributes['database']['connected']);
        $this->assertTrue($attributes['database']['installed']);
        $this->assertSame([], $attributes['database']['pendingMigrations']);
        $this->assertTrue($attributes['storage']['writable']);
        $this->assertCount(count(ScheduledTasks::TASKS), $attributes['tasks']['list']);
    }

    public function test_wrong_key_short_key_and_non_admins_are_rejected()
    {
        $this->jsonApi('GET', '/api/v1/server-status', null, ['X-Maintenance-Key' => 'otra-clave-cualquiera-123456']);
        $this->seeStatusCode(403);
        $this->seeJson(['code' => 'MAINTENANCE_KEY_INVALID']);

        config(['mitransporte.maintenance_key' => 'corta']);
        $this->jsonApi('GET', '/api/v1/server-status', null, ['X-Maintenance-Key' => 'corta']);
        $this->seeStatusCode(403);

        $this->jsonApi('GET', '/api/v1/server-status');
        $this->seeStatusCode(401);

        $this->jsonApiAs($this->createUser(), 'GET', '/api/v1/server-status');
        $this->seeStatusCode(403);
        $this->seeJson(['code' => 'FORBIDDEN']);

        $this->jsonApiAs($this->createAdmin(), 'GET', '/api/v1/server-status');
        $this->seeStatusCode(200);
    }

    public function test_only_listed_commands_run()
    {
        $this->run_('composer install');
        $this->seeStatusCode(422);
    }

    public function test_install_refuses_an_installed_database_and_migrate_updates_it()
    {
        $this->run_('install');
        $this->seeStatusCode(409);
        $this->seeJson(['code' => 'ALREADY_INSTALLED']);

        DB::table('setting_definitions')->where('key', 'route_deviation_m')->delete();
        $this->run_('migrate');
        $this->seeStatusCode(201);
        $this->seeJson(['command' => 'migrate', 'ok' => true]);
        $this->assertTrue(DB::table('setting_definitions')->where('key', 'route_deviation_m')->exists());
    }

    public function test_install_on_an_empty_database()
    {
        Schema::dropAllTables();

        $this->jsonApi('GET', '/api/v1/server-status', null, ['X-Maintenance-Key' => self::KEY]);
        $attributes = json_decode($this->response->getContent(), true)['data']['attributes'];
        $this->assertFalse($attributes['database']['installed']);
        $this->assertNotEmpty($attributes['database']['pendingMigrations']);

        $this->run_('install');
        $this->seeStatusCode(201);
        $this->seeJson(['ok' => true]);
        $this->assertTrue(Schema::hasTable('users'));
        $this->assertTrue(DB::table('roles')->exists());
        $this->assertTrue(DB::table('setting_definitions')->exists());
    }

    public function test_run_tasks_clear_cache_and_log()
    {
        $this->run_('run-tasks');
        $this->seeStatusCode(201);
        $this->seeJson(['ok' => true]);
        $output = json_decode($this->response->getContent(), true)['data']['attributes']['output'];
        $this->assertStringContainsString('trips:auto-complete: bien', $output);

        // En el mismo minuto ya no queda nada pendiente.
        $this->run_('run-tasks');
        $this->seeJson(['output' => 'No había tareas pendientes.']);

        $this->run_('clear-cache');
        $this->seeJson(['ok' => true]);

        $this->run_('log');
        $this->seeStatusCode(201);
    }

    public function test_due_rules_catch_up_missed_daily_and_hourly_tasks()
    {
        $tasks = app(ScheduledTasks::class);
        $now = Carbon::create(2026, 11, 2, 9, 30, 20);

        $this->assertTrue($tasks->isDue('minute', null, $now));
        $this->assertFalse($tasks->isDue('minute', Carbon::create(2026, 11, 2, 9, 30, 1), $now));
        $this->assertTrue($tasks->isDue('minute', Carbon::create(2026, 11, 2, 9, 29, 59), $now));

        $this->assertFalse($tasks->isDue('hour', Carbon::create(2026, 11, 2, 9, 0, 5), $now));
        $this->assertTrue($tasks->isDue('hour', Carbon::create(2026, 11, 2, 8, 59), $now));

        // Diaria a las 02:10: nadie usó la app de madrugada; se ejecuta en la
        // primera petición posterior, y una sola vez.
        $this->assertTrue($tasks->isDue('02:10', Carbon::create(2026, 11, 1, 2, 10), $now));
        $this->assertFalse($tasks->isDue('02:10', Carbon::create(2026, 11, 2, 8, 0), $now));
        // Diaria a las 23:00: la de hoy aún no toca.
        $this->assertFalse($tasks->isDue('23:00', Carbon::create(2026, 11, 1, 23, 5), $now));
        $this->assertTrue($tasks->isDue('23:00', Carbon::create(2026, 11, 1, 22, 0), $now));
    }

    public function test_tasks_run_after_requests_when_there_is_no_cron()
    {
        $tasks = app(ScheduledTasks::class);
        Carbon::setTestNow(Carbon::create(2026, 11, 2, 9, 30, 0));

        $this->assertNotEmpty($tasks->runDue(true));
        $this->assertSame([], $tasks->runDue(true));

        Carbon::setTestNow(Carbon::create(2026, 11, 2, 9, 31, 0));
        $ran = $tasks->runDue(true);
        $this->assertArrayHasKey('trips:notify-delays', $ran);
        $this->assertArrayNotHasKey('chats:purge-expired', $ran);
    }

    public function test_a_failed_task_is_retried_next_minute()
    {
        $tasks = app(ScheduledTasks::class);
        Carbon::setTestNow(Carbon::create(2026, 11, 2, 9, 30, 0));
        DB::table('setting_definitions')->where('key', 'conversation_retention_days')->delete();

        $ran = $tasks->runDue(true);
        $this->assertFalse($ran['chats:purge-expired']['ok']);

        $this->artisan('db:seed', ['--class' => 'Database\\Seeders\\SettingDefinitionSeeder']);
        Carbon::setTestNow(Carbon::create(2026, 11, 2, 9, 31, 0));
        $ran = $tasks->runDue(true);
        $this->assertTrue($ran['chats:purge-expired']['ok']);

        Carbon::setTestNow(Carbon::create(2026, 11, 2, 9, 32, 0));
        $this->assertArrayNotHasKey('chats:purge-expired', $tasks->runDue(true));
    }

    public function test_no_tasks_run_without_a_database()
    {
        Schema::dropAllTables();

        $this->assertSame([], app(ScheduledTasks::class)->runDue());

        // Para que DatabaseMigrations pueda deshacer al terminar.
        $this->artisan('migrate');
    }

    private function run_(string $command)
    {
        return $this->jsonApi('POST', '/api/v1/maintenance-runs', ['data' => [
            'type' => 'maintenance-runs',
            'attributes' => ['command' => $command],
        ]], ['X-Maintenance-Key' => self::KEY]);
    }
}
