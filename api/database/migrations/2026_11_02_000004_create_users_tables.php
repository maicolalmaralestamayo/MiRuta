<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateUsersTables extends Migration
{
    /**
     * Personas (docs/11 §11.2 y §11.6). La cuenta es de la persona y se
     * identifica por su carné de identidad, único en toda la app; en cada
     * Entidad tiene una pertenencia (workers).
     *
     * @return void
     */
    public function up()
    {
        Schema::create('users', function (Blueprint $table) {
            $table->id();
            $table->string('username', 50)->unique()->comment('En minúsculas');
            $table->string('password')->comment('Hash bcrypt');
            $table->dateTime('password_changed_at')->nullable()->comment('Para la caducidad anual');
            $table->boolean('must_change_password')->default(false);
            $table->string('first_name', 50);
            $table->string('middle_name', 50)->nullable();
            $table->string('first_surname', 50);
            $table->string('second_surname', 50);
            $table->text('identity_card_encrypted')->comment('Carné de identidad cifrado (Crypt)');
            $table->char('identity_card_hash', 64)->unique()->comment('HMAC del carné: para buscarlo y que no se repita');
            $table->enum('sex', ['F', 'M'])->comment('Sale del carné');
            $table->date('birth_date')->comment('Sale del carné');
            $table->string('photo_path')->nullable();
            $table->boolean('is_admin')->default(false);
            $table->boolean('has_phone')->default(true)->comment('Sin teléfono usa el QR impreso');
            $table->unsignedInteger('printed_qr_version')->default(1)->comment('Subirla anula el QR impreso');
            $table->unsignedInteger('app_version_code')->nullable()->comment('Versión de la app instalada (la envía la app en cada petición)');
            $table->timestamps();
            $table->softDeletes();
        });

        Schema::create('password_histories', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained();
            $table->string('password_hash')->comment('Hash bcrypt de una contraseña anterior');
            $table->timestamps();
            $table->softDeletes();
            $table->index(['user_id', 'created_at']);
        });

        Schema::create('released_usernames', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->comment('Quien lo usaba')->constrained();
            $table->string('username', 50);
            $table->dateTime('released_at')->comment('Bloqueado para los demás durante username_reuse_block_days');
            $table->timestamps();
            $table->softDeletes();
            $table->index(['username', 'released_at']);
        });

        Schema::create('user_settings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained();
            $table->foreignId('setting_definition_id')->constrained();
            $table->string('value', 1000);
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['user_id', 'setting_definition_id']);
        });

        Schema::create('refresh_tokens', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained();
            $table->char('token_hash', 64)->unique()->comment('SHA-256 del jti');
            $table->string('device_name', 100)->nullable();
            $table->dateTime('expires_at');
            $table->dateTime('revoked_at')->nullable();
            $table->foreignId('replaced_by_id')->nullable()->constrained('refresh_tokens');
            $table->timestamps();
            $table->softDeletes();
        });

        Schema::create('installations', function (Blueprint $table) {
            $table->id();
            $table->char('secret_hash', 64)->comment('SHA-256 del secreto que guarda la app');
            $table->string('device_model', 100)->nullable();
            $table->string('android_version', 20)->nullable();
            $table->unsignedInteger('app_version_code')->nullable();
            $table->foreignId('user_id')->nullable()->comment('Última cuenta que entró desde esta instalación')->constrained();
            $table->dateTime('blocked_at')->nullable()->comment('Bloqueada por el Administrador: no puede escribir sin cuenta ni pedir recuperación');
            $table->timestamps();
            $table->softDeletes();
        });
    }

    /**
     * @return void
     */
    public function down()
    {
        foreach (['installations', 'refresh_tokens', 'user_settings', 'released_usernames', 'password_histories', 'users'] as $name) {
            Schema::dropIfExists($name);
        }
    }
}
