<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateItinerariesTables extends Migration
{
    /**
     * Itinerarios y paradas, de una Entidad cada uno. Dos Entidades pueden
     * tener una parada en el mismo lugar, pero cada una registra la suya.
     *
     * @return void
     */
    public function up()
    {
        Schema::create('itineraries', function (Blueprint $table) {
            $table->id();
            $table->foreignId('entity_id')->constrained();
            $table->string('name', 100);
            $table->text('description')->nullable();
            $table->text('observation')->nullable();
            $table->string('image_path')->nullable()->comment('Imagen opcional');
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['entity_id', 'name']);
        });

        Schema::create('stops', function (Blueprint $table) {
            $table->id();
            $table->foreignId('entity_id')->constrained();
            $table->string('landmark')->comment('Punto de referencia');
            $table->string('street');
            $table->string('cross_street_1')->nullable();
            $table->string('cross_street_2')->nullable();
            $table->decimal('latitude', 10, 7);
            $table->decimal('longitude', 10, 7);
            $table->string('image_path')->nullable()->comment('Imagen opcional');
            $table->timestamps();
            $table->softDeletes();
        });

        Schema::create('itinerary_stop', function (Blueprint $table) {
            $table->id();
            $table->foreignId('itinerary_id')->constrained();
            $table->foreignId('stop_id')->constrained();
            $table->unsignedSmallInteger('position')->nullable()
                ->comment('1 = punto de salida; la última = punto de regreso; NULL si se quitó (borrada)');
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['itinerary_id', 'stop_id']);
            $table->unique(['itinerary_id', 'position']);
        });

        // Ajustes por itinerario y por parada del itinerario (docs/11 §11.17).
        Schema::create('itinerary_settings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('itinerary_id')->constrained();
            $table->foreignId('setting_definition_id')->constrained();
            $table->string('value', 1000);
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['itinerary_id', 'setting_definition_id']);
        });

        Schema::create('itinerary_stop_settings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('itinerary_stop_id')->constrained('itinerary_stop');
            $table->foreignId('setting_definition_id')->constrained();
            $table->string('value', 1000);
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['itinerary_stop_id', 'setting_definition_id'], 'itinerary_stop_settings_unique');
        });
    }

    /**
     * @return void
     */
    public function down()
    {
        foreach (['itinerary_stop_settings', 'itinerary_settings', 'itinerary_stop', 'stops', 'itineraries'] as $name) {
            Schema::dropIfExists($name);
        }
    }
}
