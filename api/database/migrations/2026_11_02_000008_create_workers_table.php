<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateWorkersTable extends Migration
{
    /**
     * Run the migrations.
     *
     * @return void
     */
    public function up()
    {
        Schema::create('workers', function (Blueprint $table) {
            $table->id();
            $table->text('card_number_encrypted')->comment('Carné cifrado; solo lo ven el trabajador y el Administrador');
            $table->char('card_number_hash', 64)->unique()->comment('HMAC-SHA256 del carné; único también entre inactivos');
            $table->string('first_name', 100);
            $table->string('last_name', 150);
            $table->enum('sex', ['F', 'M'])->comment('Calculado a partir del carné');
            $table->string('password');
            $table->foreignId('rank_id')->constrained();
            // La clave foránea compuesta (itinerary_id, stop_id) → itinerary_stop
            // se añade en la migración que crea itinerary_stop (sprint 5).
            $table->unsignedBigInteger('itinerary_id')->nullable();
            $table->unsignedBigInteger('stop_id')->nullable();
            $table->string('photo_path')->nullable();
            $table->boolean('is_admin')->default(false);
            $table->timestamps();
            $table->softDeletes();

            $table->index(['itinerary_id', 'stop_id']);
        });
    }

    /**
     * Reverse the migrations.
     *
     * @return void
     */
    public function down()
    {
        Schema::dropIfExists('workers');
    }
}
