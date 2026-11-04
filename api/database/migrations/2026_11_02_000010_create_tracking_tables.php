<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateTrackingTables extends Migration
{
    /**
     * @return void
     */
    public function up()
    {
        Schema::create('trip_legs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_id')->constrained();
            $table->enum('direction', ['outbound', 'return'])->comment('outbound = salida (paradas en orden); return = regreso (orden inverso)');
            $table->dateTime('started_at');
            $table->foreignId('started_by')->constrained('users');
            $table->dateTime('ended_at')->nullable();
            $table->foreignId('ended_by')->nullable()->constrained('users');
            $table->enum('end_reason', ['last_stop', 'manual'])->nullable();
            $table->decimal('last_latitude', 10, 7)->nullable()->comment('Última posición combinada (para la velocidad y los desvíos)');
            $table->decimal('last_longitude', 10, 7)->nullable();
            $table->dateTime('last_position_at', 3)->nullable();
            $table->boolean('deviating')->default(false)->comment('Ahora mismo fuera del recorrido de referencia');
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['trip_id', 'direction']);
        });

        Schema::create('trip_positions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_leg_id')->constrained();
            $table->foreignId('worker_id')->comment('Sensor')->constrained();
            $table->decimal('latitude', 10, 7);
            $table->decimal('longitude', 10, 7);
            $table->decimal('accuracy_m', 8, 2)->nullable();
            $table->dateTime('recorded_at', 3);
            $table->timestamps();
            $table->softDeletes();
            $table->index(['trip_leg_id', 'recorded_at']);
            $table->index(['trip_leg_id', 'worker_id', 'recorded_at']);
        });

        Schema::create('trip_stop_passes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_leg_id')->constrained();
            $table->foreignId('stop_id')->constrained();
            $table->dateTime('passed_at')->comment('Llegada a la parada (o cuando se detectó que se la saltó)');
            $table->dateTime('left_at')->nullable()->comment('Salida del radio de la parada');
            $table->decimal('min_speed_kmh', 6, 2)->nullable()->comment('Velocidad mínima dentro del radio');
            $table->enum('status', ['arrived', 'stopped', 'not_stopped', 'skipped'])->default('arrived')
                ->comment('arrived = está en la parada; stopped = se detuvo; not_stopped = pasó de largo; skipped = se la saltó');
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['trip_leg_id', 'stop_id']);
        });

        Schema::create('trip_leg_incidents', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_leg_id')->constrained();
            $table->enum('type', ['not_stopped', 'skipped', 'deviation'])
                ->comment('not_stopped = pasó de largo; skipped = se saltó la parada; deviation = se desvió del recorrido de referencia');
            $table->foreignId('stop_id')->nullable()->constrained();
            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();
            $table->unsignedInteger('distance_m')->nullable()->comment('Desvío: distancia máxima al recorrido de referencia');
            $table->dateTime('started_at');
            $table->dateTime('ended_at')->nullable()->comment('Desvío: cuando volvió al recorrido');
            $table->timestamps();
            $table->softDeletes();
            $table->index(['trip_leg_id', 'type']);
        });

        // Recorrido de referencia de cada itinerario (lo marca un Jefe).
        Schema::table('itineraries', function (Blueprint $table) {
            $table->unsignedBigInteger('reference_outbound_leg_id')->nullable()->after('observation')
                ->comment('Viaje de ida realizado que sirve de recorrido de referencia');
            $table->unsignedBigInteger('reference_return_leg_id')->nullable()->after('reference_outbound_leg_id');
            $table->foreign('reference_outbound_leg_id')->references('id')->on('trip_legs');
            $table->foreign('reference_return_leg_id')->references('id')->on('trip_legs');
        });

        Schema::create('trip_boardings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_leg_id')->constrained();
            $table->foreignId('worker_id')->comment('Quien sube')->constrained();
            $table->enum('method', ['automatic', 'self', 'qr', 'manual']);
            $table->foreignId('marked_by')->nullable()->constrained('users');
            $table->unsignedTinyInteger('children_count');
            $table->enum('outsider', ['itinerary', 'entity'])->nullable()
                ->comment('Subió alguien de otro itinerario o de otra Entidad (lo permitió quien escaneó)');
            $table->dateTime('boarded_at');
            $table->timestamps();
            $table->softDeletes();
            $table->index(['trip_leg_id', 'worker_id']);
        });

        // Hijos que suben con el trabajador: cada niño cuenta una vez por trayecto.
        Schema::create('trip_boarding_children', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_boarding_id')->constrained();
            $table->foreignId('trip_leg_id')->constrained();
            $table->foreignId('child_id')->constrained('children');
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['trip_leg_id', 'child_id']);
        });
    }

    /**
     * @return void
     */
    public function down()
    {
        Schema::table('itineraries', function (Blueprint $table) {
            $table->dropForeign(['reference_outbound_leg_id']);
            $table->dropForeign(['reference_return_leg_id']);
            $table->dropColumn(['reference_outbound_leg_id', 'reference_return_leg_id']);
        });

        foreach (['trip_boarding_children', 'trip_boardings', 'trip_leg_incidents', 'trip_stop_passes', 'trip_positions', 'trip_legs'] as $name) {
            Schema::dropIfExists($name);
        }
    }
}
