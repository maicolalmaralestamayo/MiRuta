<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Viajes (uno por sentido: ida o regreso) y su tiempo real (docs/11 §11.42 a
 * §11.47): estados de los trabajadores, informes de los teléfonos sensores
 * sobre el vehículo y paso por las paradas.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('trips', function (Blueprint $table) {
            $table->id();
            $table->foreignId('itinerary_id')->constrained()->cascadeOnDelete();
            $table->enum('direction', ['ida', 'regreso']);
            $table->date('date');
            $table->char('departure_time', 5)->comment('HH:MM (24 h)');
            $table->dateTime('departs_at');
            $table->foreignId('vehicle_type_id')->constrained();
            $table->text('observation')->nullable();
            $table->enum('status', ['planificado', 'en_ejecucion', 'terminado', 'cancelado']);
            $table->dateTime('status_changed_at')->comment('Último cambio de estado');
            $table->string('finish_reason', 30)->nullable()->comment('manual, llegada, espera_cierre, duracion_maxima');
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->text('route')->nullable()->comment('Ids de las paradas en el orden del recorrido, fijados al empezar');
            // Vehículo (lo deciden los sensores por mayoría)
            $table->enum('vehicle_state', ['detenido', 'en_movimiento'])->nullable();
            $table->dateTime('vehicle_state_since')->nullable();
            $table->boolean('vehicle_at_stop')->default(false)->comment('Detenido en el radio de la próxima parada');
            $table->unsignedSmallInteger('next_stop_index')->default(0)->comment('Posición en el recorrido de la próxima parada');
            $table->foreignId('detention_cause_id')->nullable()->constrained();
            $table->dateTime('long_detention_notified_at')->nullable();
            $table->dateTime('arrived_at')->nullable()->comment('Llegó a la parada final');
            $table->timestamps();
            $table->unique(['itinerary_id', 'direction', 'date']);
            $table->index(['status', 'departs_at']);
        });

        Schema::create('trip_passengers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('stop_id')->nullable()->comment('Su parada (Dejado: donde se bajó)')->constrained()->nullOnDelete();
            $table->enum('state', ['de_camino', 'en_parada', 'viajando', 'dejado', 'recogido', 'botado', 'dormido', 'no_voy']);
            $table->dateTime('state_at')->comment('Hora del servidor en que lo alcanzó');
            $table->dateTime('reported_at')->comment('Hora del teléfono del último informe aplicado');
            $table->unsignedTinyInteger('children_count')->default(0);
            $table->string('child_ids', 200)->nullable()->comment('Hijos que suben con él, separados por comas');
            $table->dateTime('last_seen_at')->nullable()->comment('Último envío del teléfono (sensor activo)');
            $table->timestamps();
            $table->unique(['trip_id', 'user_id']);
        });

        Schema::create('trip_vehicle_reports', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->enum('vehicle_state', ['detenido', 'en_movimiento']);
            $table->boolean('at_stop')->default(false);
            $table->unsignedSmallInteger('next_stop_index');
            $table->dateTime('reported_at');
            $table->timestamps();
            $table->unique(['trip_id', 'user_id']);
        });

        Schema::create('trip_stop_passes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_id')->constrained()->cascadeOnDelete();
            $table->foreignId('stop_id')->nullable()->constrained()->nullOnDelete();
            $table->unsignedSmallInteger('route_index');
            $table->dateTime('passed_at');
            $table->timestamps();
            $table->unique(['trip_id', 'route_index']);
        });
    }

    public function down(): void
    {
        foreach (['trip_stop_passes', 'trip_vehicle_reports', 'trip_passengers', 'trips'] as $name) {
            Schema::dropIfExists($name);
        }
    }
};
