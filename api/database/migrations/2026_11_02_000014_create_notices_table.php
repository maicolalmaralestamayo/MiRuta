<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateNoticesTable extends Migration
{
    const TYPES = [
        'application_received', 'application_resolved', 'role_assigned', 'role_removed', 'resignation',
        'inactivity_warning', 'inactivity_removal', 'trip_needs_reassignment',
        'access_recovery_requested', 'password_expiring', 'trip_started', 'trip_delayed', 'trip_incident',
    ];

    /**
     * Avisos del servidor a una cuenta.
     *
     * @return void
     */
    public function up()
    {
        Schema::create('notices', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->comment('Destinatario')->constrained();
            $table->enum('type', self::TYPES);
            $table->foreignId('application_id')->nullable()->constrained();
            $table->foreignId('trip_id')->nullable()->constrained();
            $table->foreignId('access_recovery_id')->nullable()->constrained();
            $table->text('payload')->nullable()->comment('Datos del aviso en JSON (p. ej. sentido del viaje, minutos de atraso, parada)');
            $table->dateTime('read_at')->nullable();
            $table->timestamps();
            $table->softDeletes();
            $table->index(['user_id', 'read_at']);
        });
    }

    /**
     * @return void
     */
    public function down()
    {
        Schema::dropIfExists('notices');
    }
}
