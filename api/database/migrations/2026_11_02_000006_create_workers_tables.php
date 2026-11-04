<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateWorkersTables extends Migration
{
    /**
     * Pertenencias persona–Entidad (workers), sus roles y sus ausencias
     * (docs/11 §11.6, §11.12 y §11.16).
     *
     * @return void
     */
    public function up()
    {
        Schema::create('workers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained();
            $table->foreignId('entity_id')->constrained();
            $table->unsignedBigInteger('itinerary_id')->nullable()->comment('Siempre junto con la parada');
            $table->unsignedBigInteger('stop_id')->nullable();
            $table->dateTime('itinerary_assigned_at')->nullable()->comment('Desde cuándo está en su itinerario (inactividad)');
            $table->timestamps();
            $table->softDeletes()->comment('Baja de la Entidad o pertenencia desactivada');

            // Una sola pertenencia por persona y Entidad: al volver se restaura la misma fila.
            $table->unique(['user_id', 'entity_id']);
            $table->index(['itinerary_id', 'stop_id']);
            // La parada tiene que pertenecer al itinerario.
            $table->foreign(['itinerary_id', 'stop_id'])->references(['itinerary_id', 'stop_id'])->on('itinerary_stop');
        });

        Schema::create('worker_roles', function (Blueprint $table) {
            $table->id();
            $table->foreignId('worker_id')->comment('Pertenencia: el rol es por Entidad')->constrained();
            $table->foreignId('role_id')->constrained();
            $table->foreignId('itinerary_id')->nullable()->comment('Solo si el rol es por itinerario')->constrained();
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['worker_id', 'role_id']);
        });

        Schema::create('absences', function (Blueprint $table) {
            $table->id();
            $table->foreignId('worker_id')->constrained();
            $table->foreignId('absence_type_id')->constrained();
            $table->date('starts_on');
            $table->date('ends_on')->nullable()->comment('NULL = indefinida');
            $table->boolean('indefinite')->default(false);
            $table->text('note')->nullable();
            $table->timestamps();
            $table->softDeletes();
            $table->index(['worker_id', 'starts_on', 'ends_on']);
        });
    }

    /**
     * @return void
     */
    public function down()
    {
        foreach (['absences', 'worker_roles', 'workers'] as $name) {
            Schema::dropIfExists($name);
        }
    }
}
