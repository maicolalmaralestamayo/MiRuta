<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Versión 4.5.0 (docs/11 §11.66): simulador de trabajadores. Se aplica igual
 * en una instalación nueva y con «Actualizar base de datos» sobre una 4.4.0
 * (sin perder datos). Compatible con MariaDB 10.3 (solo tablas y columnas
 * nuevas, sin índices parciales ni columnas JSON).
 *
 * - simulations: la simulación en curso (una a la vez), sus parámetros y su
 *   plan (texto JSON, determinista a partir de la semilla).
 * - simulation_id en users, workers, worker_itineraries y trips: lo creado por
 *   la simulación (trabajadores simulados, la pertenencia del Administrador al
 *   itinerario si no la tenía y el viaje de prueba). Sin clave foránea: lo
 *   borra «Eliminar Simulación».
 */
return new class extends Migration
{
    private const TABLES = ['users', 'workers', 'worker_itineraries', 'trips'];

    public function up(): void
    {
        if (! Schema::hasTable('simulations')) {
            Schema::create('simulations', function (Blueprint $table) {
                $table->id();
                $table->foreignId('itinerary_id')->constrained()->cascadeOnDelete();
                $table->unsignedBigInteger('trip_id')->nullable()->comment('Viaje de prueba');
                $table->foreignId('created_by')->comment('Administrador que la inició')->constrained('users')->cascadeOnDelete();
                $table->string('direction', 10);
                $table->string('vehicle_mode', 10)->comment('simulado o real');
                $table->unsignedSmallInteger('workers_count');
                $table->unsignedTinyInteger('pct_normal');
                $table->unsignedTinyInteger('pct_late');
                $table->unsignedTinyInteger('pct_left_behind');
                $table->unsignedTinyInteger('pct_not_going');
                $table->unsignedTinyInteger('speed_factor')->default(1);
                $table->unsignedSmallInteger('vehicle_speed_kmh')->default(30);
                $table->unsignedInteger('seed');
                $table->longText('plan')->nullable()->comment('Plan en JSON');
                $table->string('status', 12)->default('en_curso');
                $table->dateTime('started_at');
                $table->dateTime('last_tick_at')->nullable();
                $table->dateTime('finished_at')->nullable();
                $table->timestamps();
            });
        }

        foreach (self::TABLES as $name) {
            if (Schema::hasTable($name) && ! Schema::hasColumn($name, 'simulation_id')) {
                Schema::table($name, function (Blueprint $table) {
                    $table->unsignedBigInteger('simulation_id')->nullable()->index()->comment('Creado por el simulador (docs/11 §11.66)');
                });
            }
        }
    }

    public function down(): void
    {
        foreach (self::TABLES as $name) {
            if (Schema::hasTable($name) && Schema::hasColumn($name, 'simulation_id')) {
                Schema::table($name, function (Blueprint $table) {
                    $table->dropIndex(['simulation_id']);
                    $table->dropColumn('simulation_id');
                });
            }
        }

        Schema::dropIfExists('simulations');
    }
};
