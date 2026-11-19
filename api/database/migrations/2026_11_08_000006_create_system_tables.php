<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ajustes (un solo nivel), versiones de la app, «Olvidé algo» (por correo
 * desde la 5.0.0), claves del QR, registro de cambios y simulaciones.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('settings', function (Blueprint $table) {
            $table->id();
            $table->string('key', 60)->unique()->comment('Clave del catálogo App\\Support\\SettingCatalog');
            $table->string('value', 100)->comment('Texto con unidades, p. ej. 10min');
            $table->timestamps();
        });

        Schema::create('app_versions', function (Blueprint $table) {
            $table->id();
            $table->string('version_name', 20);
            $table->unsignedInteger('version_code')->unique();
            $table->text('notes')->nullable();
            $table->boolean('mandatory')->default(false);
            $table->foreignId('published_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
        });

        Schema::create('app_version_files', function (Blueprint $table) {
            $table->id();
            $table->foreignId('app_version_id')->constrained()->cascadeOnDelete();
            $table->enum('abi', ['arm64-v8a', 'armeabi-v7a', 'universal']);
            $table->string('apk_path');
            $table->unsignedBigInteger('size_bytes');
            $table->char('sha256', 64);
            $table->timestamps();
            $table->unique(['app_version_id', 'abi']);
        });

        Schema::create('access_recoveries', function (Blueprint $table) {
            $table->id();
            $table->foreignId('installation_id')->constrained()->cascadeOnDelete();
            $table->boolean('forgot_username');
            $table->boolean('forgot_password');
            $table->string('email', 150)->comment('Correo de la persona (docs/11 §11.67)');
            $table->text('phone_encrypted')->nullable();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->enum('status', ['pending', 'approved', 'rejected', 'completed', 'expired']);
            $table->foreignId('resolved_by')->nullable()->constrained('users')->nullOnDelete();
            $table->dateTime('resolved_at')->nullable();
            $table->text('password_encrypted')->nullable();
            $table->dateTime('expires_at');
            $table->dateTime('completed_at')->nullable();
            $table->timestamps();
            $table->index('status');
        });

        Schema::create('server_keys', function (Blueprint $table) {
            $table->id();
            $table->string('purpose', 30)->unique();
            $table->text('public_key')->comment('SPKI DER en base64');
            $table->text('private_key_encrypted');
            $table->timestamps();
        });

        Schema::create('qr_nonces', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->char('nonce', 16);
            $table->string('purpose', 30)->nullable();
            $table->unsignedBigInteger('reference_id')->nullable()->comment('Pertenencia (workers) que lo usó');
            $table->dateTime('expires_at');
            $table->timestamps();
            $table->unique(['user_id', 'nonce']);
            $table->index('expires_at');
        });

        // Registro de cambios para la caché del teléfono (docs/11 §11.65).
        Schema::create('change_log', function (Blueprint $table) {
            $table->id();
            $table->string('table_name', 64);
            $table->unsignedBigInteger('record_id');
            $table->string('operation', 10)->comment('create, update o delete');
            $table->dateTime('changed_at');
            $table->index('changed_at');
        });

        // Simulador de trabajadores (docs/11 §11.66): una simulación a la vez.
        Schema::create('simulations', function (Blueprint $table) {
            $table->id();
            $table->foreignId('itinerary_id')->constrained()->cascadeOnDelete();
            $table->unsignedBigInteger('trip_id')->nullable()->comment('Viaje de prueba');
            $table->foreignId('created_by')->comment('Administrador que la inició')->constrained('users')->cascadeOnDelete();
            $table->string('direction', 10);
            $table->string('vehicle_mode', 10)->comment('simulado o real');
            $table->unsignedSmallInteger('workers_count');
            $table->unsignedTinyInteger('pct_normal');
            $table->unsignedTinyInteger('pct_late');
            $table->unsignedTinyInteger('pct_left_behind');
            $table->unsignedTinyInteger('pct_not_going');
            $table->unsignedTinyInteger('speed_factor')->default(1);
            $table->unsignedSmallInteger('vehicle_speed_kmh')->default(30);
            $table->unsignedInteger('seed');
            $table->longText('plan')->nullable()->comment('Plan en JSON');
            $table->string('status', 12)->default('en_curso');
            $table->dateTime('started_at');
            $table->dateTime('last_tick_at')->nullable();
            $table->dateTime('finished_at')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        foreach (['simulations', 'change_log', 'qr_nonces', 'server_keys', 'access_recoveries', 'app_version_files', 'app_versions', 'settings'] as $name) {
            Schema::dropIfExists($name);
        }
    }
};
