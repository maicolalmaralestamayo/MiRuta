<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class CreateNomenclatorTables extends Migration
{
    /**
     * Nomencladores comunes a todas las Entidades (docs/08-version-2.md §8.2).
     *
     * @return void
     */
    public function up()
    {
        Schema::create('ranks', function (Blueprint $table) {
            $table->id();
            $table->string('name', 100)->unique();
            $table->text('description')->nullable();
            $table->text('observation')->nullable();
            $table->unsignedSmallInteger('sort_order')->default(0)->comment('Orden de presentación en las listas');
            $table->string('icon_path')->nullable();
            $table->timestamps();
            $table->softDeletes();
        });

        foreach (['vehicle_types', 'absence_types'] as $name) {
            Schema::create($name, function (Blueprint $table) {
                $table->id();
                $table->string('name', 100)->unique();
                $table->text('description')->nullable();
                $table->text('observation')->nullable();
                $table->timestamps();
                $table->softDeletes();
            });
        }

        Schema::create('conversation_topics', function (Blueprint $table) {
            $table->id();
            $table->string('name', 100);
            $table->text('description')->nullable();
            $table->text('observation')->nullable();
            $table->enum('recipient', ['itinerary_chiefs', 'transport_chiefs', 'developer']);
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['name', 'recipient']);
        });

        Schema::create('forbidden_words', function (Blueprint $table) {
            $table->id();
            $table->string('name', 50)->unique()->comment('Palabra que no puede aparecer en un usuario (en minúsculas, sin tildes)');
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
        foreach (['forbidden_words', 'conversation_topics', 'absence_types', 'vehicle_types', 'ranks'] as $name) {
            Schema::dropIfExists($name);
        }
    }
}
