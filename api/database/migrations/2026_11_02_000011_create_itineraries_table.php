<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateItinerariesTable extends Migration
{
    /**
     * Run the migrations.
     *
     * @return void
     */
    public function up()
    {
        Schema::create('itineraries', function (Blueprint $table) {
            $table->id();
            $table->string('name', 100)->unique();
            $table->text('description')->nullable();
            $table->text('observation')->nullable();
            $table->timestamps();
            $table->softDeletes();
        });

        Schema::create('stops', function (Blueprint $table) {
            $table->id();
            $table->string('landmark')->comment('Punto de referencia');
            $table->string('street');
            $table->string('cross_street_1')->nullable();
            $table->string('cross_street_2')->nullable();
            $table->decimal('latitude', 10, 7);
            $table->decimal('longitude', 10, 7);
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

        // La parada del trabajador tiene que pertenecer a su itinerario.
        Schema::table('workers', function (Blueprint $table) {
            $table->foreign(['itinerary_id', 'stop_id'])->references(['itinerary_id', 'stop_id'])->on('itinerary_stop');
        });
    }

    /**
     * Reverse the migrations.
     *
     * @return void
     */
    public function down()
    {
        Schema::table('workers', function (Blueprint $table) {
            $table->dropForeign(['itinerary_id', 'stop_id']);
        });

        Schema::dropIfExists('itinerary_stop');
        Schema::dropIfExists('stops');
        Schema::dropIfExists('itineraries');
    }
}
