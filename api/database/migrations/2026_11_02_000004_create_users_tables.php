<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateUsersTables extends Migration
{
    /**
     * Cuentas de la app (docs/08-version-2.md §8.3). El Administrador es una
     * cuenta sin trabajador. Un trabajador registrado por un superior tiene
     * cuenta sin usuario ni contraseña hasta que la activa.
     *
     * @return void
     */
    public function up()
    {
        Schema::create('users', function (Blueprint $table) {
            $table->id();
            $table->string('username', 20)->nullable()->unique()->comment('En minúsculas; NULL hasta activar la cuenta');
            $table->string('password')->nullable()->comment('Hash bcrypt; NULL hasta activar la cuenta');
            $table->dateTime('password_changed_at')->nullable()->comment('Para la caducidad anual');
            $table->boolean('must_change_password')->default(false);
            $table->string('first_name', 50);
            $table->string('middle_name', 50);
            $table->string('first_surname', 50);
            $table->string('second_surname', 50);
            $table->string('photo_path')->nullable();
            $table->boolean('is_admin')->default(false);
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
            $table->string('username', 20);
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
