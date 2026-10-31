<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateVehiclesTable extends Migration
{
    /**
     * @return void
     */
    public function up()
    {
        Schema::create('vehicles', function (Blueprint $table) {
            $table->id();
            $table->foreignId('entity_id')->constrained();
            $table->foreignId('vehicle_type_id')->constrained();
            $table->string('plate', 20)->comment('Matrícula');
            $table->unsignedSmallInteger('seats')->comment('Sin contar el del chofer');
            $table->unsignedSmallInteger('standing_capacity');
            $table->foreignId('driver_id')->nullable()->comment('Chofer habitual')->constrained();
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['entity_id', 'plate']);
        });
    }

    /**
     * @return void
     */
    public function down()
    {
        Schema::dropIfExists('vehicles');
    }
}
