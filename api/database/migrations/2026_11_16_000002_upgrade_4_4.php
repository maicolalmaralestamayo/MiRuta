<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Versión 4.4.0 (docs/11 §11.65). Se aplica igual en una instalación nueva y
 * con «Actualizar base de datos» sobre una 4.3.0 (sin perder datos). Todo es
 * compatible con MariaDB 10.3:
 *
 * - Estados del trabajador: «botado» pasa a «no_recogido» y «dormido» a
 *   «retrasado» (registros guardados y tipo de la columna). trip_passengers
 *   recuerda si el estado lo puso el servidor (set_by_server).
 * - Ajustes: «Frecuencia ventana» y «Frecuencia fuera ventana» pasan a
 *   «Frecuencia corta» (frecuencia_corta) y «Frecuencia larga»
 *   (frecuencia_larga), con su valor guardado.
 * - Motivos de rechazo separados para solicitudes de Entidad e itinerario
 *   (tablas entity_denial_reasons e itinerary_denial_reasons): se crean con
 *   las listas acordadas; los motivos de la 4.3.0 que no estén en ellas se
 *   copian a las dos; las solicitudes rechazadas conservan su motivo.
 * - «Un viaje por itinerario, sentido y fecha» ya no es un índice único (no
 *   cuenta los cancelados): lo comprueba la API.
 * - Registro de cambios (change_log) para la caché del teléfono.
 * - Pasos por parada por hora de captura de cada sensor (trip_stop_votes).
 */
return new class extends Migration
{
    private const OLD_STATES = ['de_camino', 'en_parada', 'viajando', 'dejado', 'botado', 'dormido', 'no_voy'];

    private const STATES = ['de_camino', 'en_parada', 'viajando', 'dejado', 'no_recogido', 'retrasado', 'no_voy'];

    public const ENTITY_REASONS = ['Usted no pertenece a nuestra entidad', 'No se pudo verificar su identidad', 'Otro motivo de rechazo'];

    public const ITINERARY_REASONS = ['Usted no pertenece a este itinerario', 'No se pudo verificar su identidad', 'Usted no pertenece a esta entidad',
        'El itinerario está sobrecargado', 'Otro motivo de rechazo'];

    public function up(): void
    {
        $this->states();
        $this->settings();
        $this->denialReasons();
        $this->tripUniqueness();
        $this->changeLog();
        $this->stopVotes();
    }

    private function mysql(): bool
    {
        return in_array(DB::getDriverName(), ['mysql', 'mariadb'], true);
    }

    private function states(): void
    {
        if (! Schema::hasTable('trip_passengers')) {
            return;
        }

        if ($this->mysql()) {
            $all = array_values(array_unique(array_merge(self::OLD_STATES, self::STATES)));
            DB::statement('ALTER TABLE trip_passengers MODIFY state ENUM('.$this->list($all).') NOT NULL');
        } else {
            // SQLite (pruebas): la columna deja de tener la lista vieja.
            Schema::table('trip_passengers', function (Blueprint $table) {
                $table->string('state', 20)->change();
            });
        }

        DB::table('trip_passengers')->where('state', 'botado')->update(['state' => 'no_recogido']);
        DB::table('trip_passengers')->where('state', 'dormido')->update(['state' => 'retrasado']);

        if ($this->mysql()) {
            DB::statement('ALTER TABLE trip_passengers MODIFY state ENUM('.$this->list(self::STATES).') NOT NULL');
        }

        if (! Schema::hasColumn('trip_passengers', 'set_by_server')) {
            Schema::table('trip_passengers', function (Blueprint $table) {
                $table->boolean('set_by_server')->default(false)->comment('No recogido / Retrasado puestos por el servidor (teléfono sin enviar)');
            });
        }
    }

    private function settings(): void
    {
        if (! Schema::hasTable('settings')) {
            return;
        }

        foreach (['frecuencia_calculo' => 'frecuencia_corta', 'frecuencia_reposo' => 'frecuencia_larga'] as $old => $new) {
            $value = DB::table('settings')->where('key', $old)->value('value');

            if ($value !== null && ! DB::table('settings')->where('key', $new)->exists()) {
                DB::table('settings')->insert(['key' => $new, 'value' => $value, 'created_at' => Carbon::now(), 'updated_at' => Carbon::now()]);
            }

            DB::table('settings')->where('key', $old)->delete();
        }
    }

    private function denialReasons(): void
    {
        foreach (['entity_denial_reasons' => self::ENTITY_REASONS, 'itinerary_denial_reasons' => self::ITINERARY_REASONS] as $name => $seed) {
            if (! Schema::hasTable($name)) {
                Schema::create($name, function (Blueprint $table) {
                    $table->id();
                    $table->string('name', 100)->unique();
                    $table->text('description')->nullable();
                    $table->text('observation')->nullable();
                    $table->boolean('active')->default(true);
                    $table->timestamps();
                });
            }

            foreach ($seed as $reason) {
                if (! DB::table($name)->where('name', $reason)->exists()) {
                    DB::table($name)->insert(['name' => $reason, 'active' => true, 'created_at' => Carbon::now(), 'updated_at' => Carbon::now()]);
                }
            }

            // Los motivos de la 4.3.0 que no están en la lista se copian (a las dos tablas).
            if (Schema::hasTable('denial_reasons')) {
                foreach (DB::table('denial_reasons')->get() as $old) {
                    if (! DB::table($name)->where('name', $old->name)->exists()) {
                        DB::table($name)->insert([
                            'name' => $old->name, 'description' => $old->description, 'observation' => $old->observation,
                            'active' => $old->active, 'created_at' => $old->created_at ?? Carbon::now(), 'updated_at' => Carbon::now(),
                        ]);
                    }
                }
            }
        }

        if (Schema::hasTable('applications') && ! Schema::hasColumn('applications', 'entity_denial_reason_id')) {
            Schema::table('applications', function (Blueprint $table) {
                $table->foreignId('entity_denial_reason_id')->nullable()->comment('Motivo (solicitud de Entidad)')->constrained()->nullOnDelete();
                $table->foreignId('itinerary_denial_reason_id')->nullable()->comment('Motivo (solicitud de itinerario)')->constrained()->nullOnDelete();
            });
        }

        // Las rechazadas conservan su motivo: el de igual nombre en la tabla de su tipo.
        if (Schema::hasTable('applications') && Schema::hasTable('denial_reasons')) {
            $rejected = DB::table('applications')->whereNotNull('denial_reason_id')
                ->whereNull('entity_denial_reason_id')->whereNull('itinerary_denial_reason_id')->get(['id', 'type', 'denial_reason_id']);

            foreach ($rejected as $application) {
                $name = DB::table('denial_reasons')->where('id', $application->denial_reason_id)->value('name');

                if ($name === null) {
                    continue;
                }

                $entity = $application->type === 'entidad';
                $id = DB::table($entity ? 'entity_denial_reasons' : 'itinerary_denial_reasons')->where('name', $name)->value('id');
                DB::table('applications')->where('id', $application->id)->update([$entity ? 'entity_denial_reason_id' : 'itinerary_denial_reason_id' => $id]);
            }
        }
    }

    /**
     * El índice único de la 4.3.0 se cambia por uno normal (el de la clave
     * foránea del itinerario lo necesita): primero se crea el nuevo.
     */
    private function tripUniqueness(): void
    {
        if (! Schema::hasTable('trips')) {
            return;
        }

        $indexes = array_map(fn ($i) => $i['name'], Schema::getIndexes('trips'));

        if (! in_array('trips_itinerary_direction_date_index', $indexes, true)) {
            Schema::table('trips', function (Blueprint $table) {
                $table->index(['itinerary_id', 'direction', 'date'], 'trips_itinerary_direction_date_index');
            });
        }

        if (in_array('trips_itinerary_id_direction_date_unique', $indexes, true)) {
            Schema::table('trips', function (Blueprint $table) {
                $table->dropUnique('trips_itinerary_id_direction_date_unique');
            });
        }
    }

    private function changeLog(): void
    {
        if (Schema::hasTable('change_log')) {
            return;
        }

        Schema::create('change_log', function (Blueprint $table) {
            $table->id();
            $table->string('table_name', 64);
            $table->unsignedBigInteger('record_id');
            $table->string('operation', 10)->comment('create, update o delete');
            $table->dateTime('changed_at');
            $table->index('changed_at');
        });
    }

    private function stopVotes(): void
    {
        if (Schema::hasTable('trip_stop_votes')) {
            return;
        }

        Schema::create('trip_stop_votes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->unsignedSmallInteger('next_stop_index')->comment('El sensor vio el vehículo con esta próxima parada');
            $table->dateTime('voted_at')->comment('Hora de captura en el teléfono');
            $table->unique(['trip_id', 'user_id', 'next_stop_index']);
        });
    }

    private function list(array $values): string
    {
        return implode(',', array_map(fn ($s) => "'".$s."'", $values));
    }

    public function down(): void
    {
        // Sin vuelta atrás de los datos (estados renombrados, motivos copiados).
        Schema::dropIfExists('trip_stop_votes');
        Schema::dropIfExists('change_log');
    }
};
