<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateAccessRecoveriesTable extends Migration
{
    /**
     * "No puedo entrar" (docs/08-version-2.md §8.6): usuario, contraseña o
     * los dos. La aprueba el Administrador y solo vale en la instalación
     * desde la que se pidió.
     *
     * @return void
     */
    public function up()
    {
        Schema::create('access_recoveries', function (Blueprint $table) {
            $table->id();
            $table->foreignId('installation_id')->constrained();
            $table->boolean('forgot_username');
            $table->boolean('forgot_password');
            $table->string('entity_abbreviation', 15)->comment('Tal como la escribió');
            $table->unsignedInteger('pass')->comment('Tal como lo escribió');
            $table->text('phone_encrypted')->nullable()->comment('Se borra al cerrar la solicitud');
            $table->foreignId('worker_id')->nullable()->comment('Trabajador que coincide con la Entidad y el Pase')->constrained();
            $table->enum('status', ['pending', 'approved', 'rejected', 'completed', 'expired']);
            $table->foreignId('resolved_by')->nullable()->constrained('users');
            $table->dateTime('resolved_at')->nullable();
            $table->char('password_token_hash', 64)->nullable()->comment('Para elegir la contraseña nueva tras la aprobación');
            $table->dateTime('expires_at');
            $table->dateTime('completed_at')->nullable();
            $table->timestamps();
            $table->softDeletes();
            $table->index(['installation_id', 'created_at']);
            $table->index('status');
        });
    }

    /**
     * @return void
     */
    public function down()
    {
        Schema::dropIfExists('access_recoveries');
    }
}
