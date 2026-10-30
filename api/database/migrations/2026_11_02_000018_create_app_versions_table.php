<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateAppVersionsTable extends Migration
{
    /**
     * Run the migrations.
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
            $table->string('apk_path');
            $table->unsignedBigInteger('size_bytes');
            $table->char('sha256', 64);
            $table->foreignId('published_by')->constrained('workers');
            $table->timestamps();
            $table->softDeletes();
        });

        Schema::table('workers', function (Blueprint $table) {
            $table->unsignedInteger('app_version_code')->nullable()->after('photo_path')
                ->comment('Versión de la app instalada (la envía la app en cada petición)');
        });
    }

    /**
     * Reverse the migrations.
     *
     * @return void
     */
    public function down()
    {
        Schema::table('workers', function (Blueprint $table) {
            $table->dropColumn('app_version_code');
        });

        Schema::dropIfExists('app_versions');
    }
}
