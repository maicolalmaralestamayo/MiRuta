<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateAccessRecoveriesTable extends Migration
{
    /**
     * «Olvidé algo» (docs/11 §11.7): usuario, contraseña o los dos, con el
     * carné y un teléfono. La aprueba el Administrador; al aprobarla se
     * propone una contraseña nueva que hay que cambiar al entrar.
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
            $table->text('identity_card_encrypted')->nullable()->comment('Tal como lo escribió; se borra al cerrar la solicitud');
            $table->char('identity_card_hash', 64)->comment('HMAC del carné escrito');
            $table->text('phone_encrypted')->nullable()->comment('Se borra al cerrar la solicitud');
            $table->foreignId('user_id')->nullable()->comment('Persona con ese carné')->constrained();
            $table->enum('status', ['pending', 'approved', 'rejected', 'completed', 'expired']);
            $table->foreignId('resolved_by')->nullable()->constrained('users');
            $table->dateTime('resolved_at')->nullable();
            $table->text('password_encrypted')->nullable()->comment('Contraseña propuesta al aprobar; se borra al cerrar la solicitud');
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
