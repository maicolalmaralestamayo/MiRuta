<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateEntitiesTable extends Migration
{
    /**
     * Entidades: empresas que usan la app (docs/08-version-2.md §8.2).
     *
     * @return void
     */
    public function up()
    {
        Schema::create('entities', function (Blueprint $table) {
            $table->id();
            $table->string('abbreviation', 15)->unique()->comment('En mayúsculas; única también entre inactivas; es lo que se muestra');
            $table->char('number', 4)->nullable()->unique()->comment('Opcional; 4 dígitos');
            $table->string('name', 150);
            $table->text('description')->nullable();
            $table->text('observation')->nullable();
            $table->timestamps();
            $table->softDeletes();
        });
    }

    /**
     * @return void
     */
    public function down()
    {
        Schema::dropIfExists('entities');
    }
}
