<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Personas, sesiones e instalaciones de la app (docs/11 §11.2 a §11.7).
 *
 * Versión 5.0.0 (docs/11 §11.67): se instala sobre una base de datos vacía.
 * Sin carné de identidad: la persona se identifica por su correo electrónico
 * (único en toda la base de datos) y el sexo se introduce a mano.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('users', function (Blueprint $table) {
            $table->id();
            $table->string('username', 50)->unique()->comment('En minúsculas');
            $table->string('password')->comment('Hash bcrypt');
            $table->dateTime('password_changed_at')->nullable()->comment('Para la caducidad');
            $table->boolean('must_change_password')->default(false)->comment('Contraseña puesta por otro');
            $table->string('first_name', 50);
            $table->string('middle_name', 50)->nullable();
            $table->string('first_surname', 50);
            $table->string('second_surname', 50);
            $table->string('email', 150)->unique()->comment('Correo electrónico, en minúsculas; único');
            $table->enum('sex', ['F', 'M'])->default('M')->comment('A mano (por omisión Masculino)');
            $table->date('birth_date')->nullable()->comment('Opcional');
            $table->string('photo_path')->nullable();
            $table->boolean('is_admin')->default(false)->comment('Administrador (rol fijo)');
            $table->unsignedInteger('app_version_code')->nullable()->comment('Versión de la app (cabecera X-App-Version)');
            $table->unsignedBigInteger('simulation_id')->nullable()->index()->comment('Creado por el simulador (docs/11 §11.66)');
            $table->timestamps();
        });

        Schema::create('password_histories', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('password_hash');
            $table->timestamps();
        });

        Schema::create('released_usernames', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->comment('Quien lo usaba')->constrained()->cascadeOnDelete();
            $table->string('username', 50);
            $table->dateTime('released_at');
            $table->timestamps();
            $table->index(['username', 'released_at']);
        });

        Schema::create('refresh_tokens', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->char('token_hash', 64)->unique()->comment('SHA-256 del jti');
            $table->string('device_name', 100)->nullable();
            $table->dateTime('expires_at');
            $table->dateTime('revoked_at')->nullable();
            $table->unsignedBigInteger('replaced_by_id')->nullable();
            $table->timestamps();
        });

        Schema::create('installations', function (Blueprint $table) {
            $table->id();
            $table->char('secret_hash', 64)->comment('SHA-256 del secreto que guarda la app');
            $table->string('device_model', 100)->nullable();
            $table->string('android_version', 20)->nullable();
            $table->unsignedInteger('app_version_code')->nullable();
            $table->foreignId('user_id')->nullable()->comment('Última cuenta que entró desde aquí')->constrained()->nullOnDelete();
            $table->dateTime('blocked_at')->nullable()->comment('Bloqueada por el Administrador');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        foreach (['installations', 'refresh_tokens', 'released_usernames', 'password_histories', 'users'] as $name) {
            Schema::dropIfExists($name);
        }
    }
};
