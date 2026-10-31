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
            $table->dateTime('passed_at');
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['trip_leg_id', 'stop_id']);
        });

        Schema::create('trip_boardings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_leg_id')->constrained();
            $table->foreignId('worker_id')->comment('Quien sube')->constrained();
            $table->enum('method', ['automatic', 'self', 'qr', 'manual']);
            $table->foreignId('marked_by')->nullable()->constrained('users');
            $table->unsignedTinyInteger('children_count');
            $table->dateTime('boarded_at');
            $table->timestamps();
            $table->softDeletes();
            $table->index(['trip_leg_id', 'worker_id']);
        });
    }

    /**
     * @return void
     */
    public function down()
    {
        foreach (['trip_boardings', 'trip_stop_passes', 'trip_positions', 'trip_legs'] as $name) {
            Schema::dropIfExists($name);
        }
    }
}
