<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Versión 4.2.0 (docs/11 §11.61 y §11.62). Se aplica igual en una instalación
 * nueva y con «Actualizar base de datos» sobre una 4.1.0 (sin perder datos):
 *
 * - Ausencias por itinerario: la ausencia es de la persona (absences.user_id)
 *   y cubre uno o varios de sus itinerarios (tabla absence_itinerary). Las
 *   ausencias de la 4.1.0 (de una Entidad) pasan a cubrir los itinerarios que
 *   la persona tenía en esa Entidad.
 * - Tiempo real: si el teléfono tiene GPS (trip_passengers.gps_ok) y quién
 *   marcó a mano el paso por una parada (trip_stop_passes.marked_by).
 * - Ajustes: desaparece «Frecuencia día viaje» y «Frecuencia fuera ventana»
 *   (antes «Frecuencia reposo») no admite menos de 15 min.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('absences', 'user_id')) {
            Schema::table('absences', function (Blueprint $table) {
                $table->foreignId('user_id')->nullable()->after('id')->comment('La persona ausente')->constrained()->cascadeOnDelete();
            });

            foreach (DB::table('absences')->get(['id', 'worker_id']) as $absence) {
                $userId = DB::table('workers')->where('id', $absence->worker_id)->value('user_id');
                DB::table('absences')->where('id', $absence->id)->update(['user_id' => $userId]);
            }

            Schema::table('absences', function (Blueprint $table) {
                $table->dropForeign(['worker_id']);
            });
            Schema::table('absences', function (Blueprint $table) {
                $table->unsignedBigInteger('worker_id')->nullable()->comment('Solo ausencias de la 4.1.0 (Entidad)')->change();
                $table->foreign('worker_id')->references('id')->on('workers')->nullOnDelete();
            });
        }

        if (! Schema::hasTable('absence_itinerary')) {
            Schema::create('absence_itinerary', function (Blueprint $table) {
                $table->id();
                $table->foreignId('absence_id')->constrained()->cascadeOnDelete();
                $table->foreignId('itinerary_id')->constrained()->cascadeOnDelete();
                $table->unique(['absence_id', 'itinerary_id']);
                $table->index('itinerary_id');
            });

            foreach (DB::table('absences')->whereNotNull('worker_id')->get(['id', 'worker_id']) as $absence) {
                foreach (DB::table('worker_itineraries')->where('worker_id', $absence->worker_id)->pluck('itinerary_id') as $itineraryId) {
                    DB::table('absence_itinerary')->insertOrIgnore(['absence_id' => $absence->id, 'itinerary_id' => $itineraryId]);
                }
            }
        }

        if (! Schema::hasColumn('trip_passengers', 'gps_ok')) {
            Schema::table('trip_passengers', function (Blueprint $table) {
                $table->boolean('gps_ok')->nullable()->comment('El teléfono tenía posición del GPS en su último envío');
            });
        }

        if (! Schema::hasColumn('trip_stop_passes', 'marked_by')) {
            Schema::table('trip_stop_passes', function (Blueprint $table) {
                $table->foreignId('marked_by')->nullable()->comment('Marcado a mano («Pasó por la parada»)')->constrained('users')->nullOnDelete();
            });
        }

        if (Schema::hasTable('settings')) {
            DB::table('settings')->where('key', 'frecuencia_dia_viaje')->delete();
            $stored = DB::table('settings')->where('key', 'frecuencia_reposo')->value('value');

            if ($stored !== null && (\App\Support\Units::seconds((string) $stored) ?? 0) < 15 * 60) {
                DB::table('settings')->where('key', 'frecuencia_reposo')->delete();
            }
        }
    }

    public function down(): void
    {
        // Sin vuelta atrás: una ausencia puede cubrir itinerarios de varias Entidades.
    }
};
