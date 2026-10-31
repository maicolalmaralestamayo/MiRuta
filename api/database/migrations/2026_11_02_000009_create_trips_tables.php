<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class CreateTripsTables extends Migration
{
    /**
     * Viajes. La Entidad es la de su itinerario.
     *
     * @return void
     */
    public function up()
    {
        Schema::create('trips', function (Blueprint $table) {
            $table->id();
            $table->foreignId('itinerary_id')->constrained();
            $table->foreignId('vehicle_id')->constrained();
            $table->foreignId('driver_id')->constrained();
            $table->dateTime('departs_at');
            $table->dateTime('returns_at');
            $table->enum('status', ['unconfirmed', 'confirmed', 'completed', 'cancelled']);
            $table->foreignId('created_by')->constrained('users');
            $table->timestamps();
            $table->softDeletes();
            $table->index(['vehicle_id', 'status', 'departs_at', 'returns_at']);
            $table->index(['driver_id', 'status', 'departs_at', 'returns_at']);
            $table->index(['itinerary_id', 'departs_at']);
            $table->index('updated_at');
        });
        DB::statement('ALTER TABLE trips ADD CONSTRAINT trips_returns_after_departs CHECK (returns_at > departs_at)');

        Schema::create('trip_completions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_id')->constrained();
            $table->foreignId('user_id')->nullable()->comment('NULL = el sistema')->constrained();
            $table->enum('role', ['driver', 'itinerary_chief', 'transport_chief', 'administrator', 'system']);
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['trip_id', 'user_id']);
        });
    }

    /**
     * @return void
     */
    public function down()
    {
        Schema::dropIfExists('trip_completions');
        Schema::dropIfExists('trips');
    }
}
