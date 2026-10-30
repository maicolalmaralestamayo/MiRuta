<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateRoleTables extends Migration
{
    /**
     * Run the migrations.
     *
     * @return void
     */
    public function up()
    {
        Schema::create('itinerary_chiefs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('itinerary_id')->constrained();
            $table->foreignId('worker_id')->constrained();
            $table->timestamps();
            $table->softDeletes();

            $table->unique(['itinerary_id', 'worker_id']);
        });

        Schema::create('drivers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('worker_id')->unique()->constrained();
            $table->timestamps();
            $table->softDeletes();
        });

        Schema::create('transport_chiefs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('worker_id')->unique()->constrained();
            $table->timestamps();
            $table->softDeletes();
        });
    }

    /**
     * Reverse the migrations.
     *
     * @return void
     */
    public function down()
    {
        Schema::dropIfExists('transport_chiefs');
        Schema::dropIfExists('drivers');
        Schema::dropIfExists('itinerary_chiefs');
    }
}
