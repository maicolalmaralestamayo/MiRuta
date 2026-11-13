<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Paso de una base de datos 4.0.0 ya instalada a la 4.1.0 (docs/11 §11.58),
 * con «Actualizar base de datos». En una instalación nueva no hace nada: la
 * migración de las tablas de organización ya crea el esquema de la 4.1.0.
 *
 * - itineraries.entity_id pasa a ser opcional (al eliminar la Entidad, el
 *   itinerario queda sin Entidad).
 * - El itinerario, la parada y la jefatura de cada pertenencia pasan de
 *   workers a worker_itineraries (varios itinerarios por Entidad).
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('workers', 'itinerary_id')) {
            return;
        }

        if (! Schema::hasTable('worker_itineraries')) {
            Schema::create('worker_itineraries', function (Blueprint $table) {
                $table->id();
                $table->foreignId('worker_id')->comment('Su pertenencia a la Entidad del itinerario')->constrained()->cascadeOnDelete();
                $table->foreignId('user_id')->constrained()->cascadeOnDelete();
                $table->foreignId('itinerary_id')->constrained()->cascadeOnDelete();
                $table->foreignId('stop_id')->nullable()->constrained()->nullOnDelete();
                $table->boolean('is_chief')->default(false)->comment('Jefe de este itinerario (de uno solo por persona)');
                $table->timestamps();
                $table->unique(['user_id', 'itinerary_id']);
                $table->index(['itinerary_id', 'stop_id']);
            });
        }

        $now = now();

        foreach (DB::table('workers')->whereNotNull('itinerary_id')->get() as $worker) {
            DB::table('worker_itineraries')->insertOrIgnore([
                'worker_id' => $worker->id, 'user_id' => $worker->user_id, 'itinerary_id' => $worker->itinerary_id,
                'stop_id' => $worker->stop_id, 'is_chief' => (bool) $worker->is_chief, 'created_at' => $now, 'updated_at' => $now,
            ]);
        }

        Schema::table('workers', function (Blueprint $table) {
            $table->dropForeign(['itinerary_id']);
            $table->dropForeign(['stop_id']);
        });
        Schema::table('workers', function (Blueprint $table) {
            $table->dropIndex(['itinerary_id', 'stop_id']);
        });
        Schema::table('workers', function (Blueprint $table) {
            $table->dropColumn(['itinerary_id', 'stop_id', 'is_chief']);
        });

        Schema::table('itineraries', function (Blueprint $table) {
            $table->dropForeign(['entity_id']);
        });
        Schema::table('itineraries', function (Blueprint $table) {
            $table->unsignedBigInteger('entity_id')->nullable()->comment('NULL = sin Entidad')->change();
            $table->foreign('entity_id')->references('id')->on('entities')->nullOnDelete();
        });
    }

    public function down(): void
    {
        // Sin vuelta atrás: la 4.0.0 admitía un solo itinerario por Entidad.
    }
};
