<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateQrTables extends Migration
{
    /**
     * Código QR de la persona (docs/11 §11.8 y §11.9): clave del servidor
     * (ECDSA P-256) y códigos dinámicos ya usados (un solo uso).
     *
     * @return void
     */
    public function up()
    {
        Schema::create('server_keys', function (Blueprint $table) {
            $table->id();
            $table->string('purpose', 30)->default('qr')->unique();
            $table->text('public_key')->comment('SPKI DER en base64');
            $table->text('private_key_encrypted')->comment('Cifrada con Crypt (APP_KEY)');
            $table->timestamps();
            $table->softDeletes();
        });

        Schema::create('qr_nonces', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained();
            $table->char('nonce', 16)->comment('8 bytes en hexadecimal');
            $table->dateTime('expires_at');
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['user_id', 'nonce']);
            $table->index('expires_at');
        });
    }

    /**
     * @return void
     */
    public function down()
    {
        Schema::dropIfExists('qr_nonces');
        Schema::dropIfExists('server_keys');
    }
}
