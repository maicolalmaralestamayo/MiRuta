<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateAppVersionsTables extends Migration
{
    /**
     * Versiones de la app con un APK por tipo de procesador
     * (docs/08-version-2.md §8.1).
     *
     * @return void
     */
    public function up()
    {
        Schema::create('app_versions', function (Blueprint $table) {
            $table->id();
            $table->string('version_name', 20)->comment('Versión visible, p. ej. 1.3.0');
            $table->unsignedInteger('version_code')->unique()->comment('versionCode de Android; crece con cada versión');
            $table->text('notes')->nullable()->comment('Novedades');
            $table->boolean('mandatory')->default(false)->comment('Las versiones anteriores dejan de poder usarse');
            $table->foreignId('published_by')->constrained('users');
            $table->timestamps();
            $table->softDeletes();
        });

        Schema::create('app_version_files', function (Blueprint $table) {
            $table->id();
            $table->foreignId('app_version_id')->constrained();
            $table->enum('abi', ['arm64-v8a', 'armeabi-v7a', 'universal'])->comment('Tipo de procesador del APK');
            $table->string('apk_path');
            $table->unsignedBigInteger('size_bytes');
            $table->char('sha256', 64);
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['app_version_id', 'abi']);
        });
    }

    /**
     * @return void
     */
    public function down()
    {
        Schema::dropIfExists('app_version_files');
        Schema::dropIfExists('app_versions');
    }
}
