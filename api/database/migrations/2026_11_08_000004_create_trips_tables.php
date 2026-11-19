<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Viajes (uno por sentido: ida o regreso) y su tiempo real (docs/11 §11.42 a
 * §11.47, §11.65 y §11.67): estados de los trabajadores, informes de los
 * teléfonos sensores sobre el vehículo y estado de cada parada.
 *
 * Versión 5.0.0 (instalación nueva): estados del trabajador de la «versión
 * definitiva» y estados de las paradas (En espera, Recogida, Volada, Omitida).
 * Compatible con MariaDB 10.3 (sin índices parciales ni columnas JSON).
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
            $table->dateTime('started_at')->nullable()->comment('Salida real (En ejecución)');
            $table->string('finish_reason', 30)->nullable()->comment('manual, llegada, espera_cierre, duracion_maxima; cancelado: manual, plazo_cancelacion');
            $table->string('last_changes', 100)->nullable()->comment('Qué cambió en el último «Viaje cambiado» (fecha,hora,…), mientras siga Planificado');
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
            $table->unsignedBigInteger('simulation_id')->nullable()->index()->comment('Viaje de prueba del simulador (docs/11 §11.66)');
            $table->timestamps();
            // «Un viaje por itinerario, sentido y fecha» sin contar los cancelados: lo comprueba la API.
            $table->index(['itinerary_id', 'direction', 'date'], 'trips_itinerary_direction_date_index');
            $table->index(['status', 'departs_at']);
        });

        Schema::create('trip_passengers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('stop_id')->nullable()->comment('Parada detectada (Dejado: donde se bajó)')->constrained()->nullOnDelete();
            $table->enum('state', ['fuera_itinerario', 'acercandose', 'alejandose', 'en_parada', 'llegada_tarde', 'no_recogido',
                'viajando', 'dejado', 'no_viajare']);
            $table->dateTime('state_at')->comment('Hora de captura del estado');
            $table->dateTime('reported_at')->comment('Hora del teléfono del último informe aplicado');
            $table->boolean('manual')->default(false)->comment('Estado puesto a mano por el trabajador');
            $table->unsignedTinyInteger('children_count')->default(0);
            $table->string('child_ids', 200)->nullable()->comment('Hijos que suben con él, separados por comas');
            $table->dateTime('last_seen_at')->nullable()->comment('Último envío del teléfono (sensor activo)');
            $table->boolean('gps_ok')->nullable()->comment('El teléfono tenía posición del GPS en su último envío');
            $table->boolean('set_by_server')->default(false)->comment('No recogido / Llegada tarde puestos por el servidor (teléfono sin enviar)');
            $table->timestamps();
            $table->unique(['trip_id', 'user_id']);
        });

        Schema::create('trip_vehicle_reports', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->enum('vehicle_state', ['detenido', 'en_movimiento']);
            $table->boolean('at_stop')->default(false);
            $table->boolean('in_radius')->default(false)->comment('Dentro del radio de la próxima parada');
            $table->unsignedSmallInteger('next_stop_index');
            $table->decimal('speed', 6, 1)->nullable()->comment('km/h calculados en el teléfono');
            $table->dateTime('reported_at');
            $table->timestamps();
            $table->unique(['trip_id', 'user_id']);
        });

        // Estado de cada parada distinto de En espera (docs/11 §11.67).
        Schema::create('trip_stop_passes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_id')->constrained()->cascadeOnDelete();
            $table->foreignId('stop_id')->nullable()->constrained()->nullOnDelete();
            $table->unsignedSmallInteger('route_index');
            $table->enum('stop_state', ['recogida', 'volada', 'omitida']);
            $table->dateTime('passed_at')->comment('Cuándo dejó de estar En espera');
            $table->dateTime('left_at')->nullable()->comment('El vehículo ya la dejó atrás');
            $table->foreignId('marked_by')->nullable()->comment('Marcado a mano («Marcar paso por parada»)')->constrained('users')->nullOnDelete();
            $table->timestamps();
            $table->unique(['trip_id', 'route_index']);
        });

        // Lo que vio cada sensor de cada parada, con su hora de captura (docs/11 §11.65 y §11.67):
        // next = el vehículo ya iba hacia una parada posterior; radio = pasó dentro de su radio.
        Schema::create('trip_stop_votes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->unsignedSmallInteger('next_stop_index')->comment('Posición de la parada');
            $table->string('kind', 10)->default('next');
            $table->dateTime('voted_at')->comment('Hora de captura en el teléfono');
            $table->unique(['trip_id', 'user_id', 'next_stop_index', 'kind']);
        });
    }

    public function down(): void
    {
        foreach (['trip_stop_votes', 'trip_stop_passes', 'trip_vehicle_reports', 'trip_passengers', 'trips'] as $name) {
            Schema::dropIfExists($name);
        }
    }
};
