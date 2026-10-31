<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateWorkersTables extends Migration
{
    /**
     * Trabajadores (de una Entidad), códigos de activación y roles.
     *
     * @return void
     */
    public function up()
    {
        Schema::create('workers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->unique()->constrained();
            $table->foreignId('entity_id')->constrained();
            $table->unsignedInteger('pass')->comment('Pase: número del trabajador dentro de su Entidad');
            $table->enum('sex', ['F', 'M']);
            $table->foreignId('rank_id')->constrained();
            $table->unsignedBigInteger('itinerary_id')->nullable();
            $table->unsignedBigInteger('stop_id')->nullable();
            $table->timestamps();
            $table->softDeletes();

            $table->unique(['entity_id', 'pass'], 'workers_entity_pass_unique');
            $table->index(['itinerary_id', 'stop_id']);
            // La parada del trabajador tiene que pertenecer a su itinerario.
            $table->foreign(['itinerary_id', 'stop_id'])->references(['itinerary_id', 'stop_id'])->on('itinerary_stop');
        });

        Schema::create('activation_codes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->comment('Cuenta que se activará')->constrained();
            $table->char('code_hash', 64);
            $table->unsignedTinyInteger('failed_attempts')->default(0);
            $table->dateTime('expires_at');
            $table->foreignId('created_by')->constrained('users');
            $table->dateTime('used_at')->nullable();
            $table->timestamps();
            $table->softDeletes();
            $table->index(['user_id', 'used_at']);
        });

        Schema::create('itinerary_chiefs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('itinerary_id')->constrained();
            $table->foreignId('worker_id')->constrained();
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['itinerary_id', 'worker_id']);
        });

        foreach (['drivers', 'transport_chiefs'] as $name) {
            Schema::create($name, function (Blueprint $table) {
                $table->id();
                $table->foreignId('worker_id')->unique()->constrained();
                $table->timestamps();
                $table->softDeletes();
            });
        }
    }

    /**
     * @return void
     */
    public function down()
    {
        foreach (['transport_chiefs', 'drivers', 'itinerary_chiefs', 'activation_codes', 'workers'] as $name) {
            Schema::dropIfExists($name);
        }
    }
}
