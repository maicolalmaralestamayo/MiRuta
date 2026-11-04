<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateSettingsTables extends Migration
{
    /**
     * Ajustes: app → Entidad → itinerario → parada del itinerario → usuario
     * (docs/06-ajustes.md y docs/11 §11.17). Gana el más concreto.
     *
     * @return void
     */
    public function up()
    {
        Schema::create('setting_definitions', function (Blueprint $table) {
            $table->id();
            $table->string('key', 100)->unique();
            $table->string('name', 150);
            $table->text('description')->nullable();
            $table->text('observation')->nullable();
            $table->enum('value_type', ['integer', 'boolean', 'string', 'time', 'option']);
            $table->string('default_value', 1000);
            $table->integer('min_value')->nullable()->comment('Para texto: longitud mínima');
            $table->integer('max_value')->nullable()->comment('Para texto: longitud máxima');
            $table->foreignId('min_setting_definition_id')->nullable()
                ->comment('Ajuste de la app que fija el valor mínimo de este')
                ->constrained('setting_definitions');
            $table->foreignId('max_setting_definition_id')->nullable()
                ->comment('Ajuste de la app que fija el valor máximo de este')
                ->constrained('setting_definitions');
            $table->enum('level', ['app', 'entity'])
                ->comment('app: solo el Administrador; entity: el Administrador fija el valor de la app y cada Jefe de Transporte el de su Entidad');
            $table->boolean('user_overridable')->default(false);
            $table->boolean('itinerary_level')->default(false)->comment('Se puede cambiar por itinerario');
            $table->boolean('stop_level')->default(false)->comment('Se puede cambiar por parada de un itinerario');
            $table->timestamps();
            $table->softDeletes();
        });

        Schema::create('setting_options', function (Blueprint $table) {
            $table->id();
            $table->foreignId('setting_definition_id')->constrained();
            $table->string('value', 100);
            $table->string('name', 150);
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['setting_definition_id', 'value']);
        });

        Schema::create('settings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('setting_definition_id')->unique()->constrained();
            $table->string('value', 1000);
            $table->timestamps();
            $table->softDeletes();
        });

        Schema::create('entity_settings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('entity_id')->constrained();
            $table->foreignId('setting_definition_id')->constrained();
            $table->string('value', 1000);
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['entity_id', 'setting_definition_id']);
        });
    }

    /**
     * @return void
     */
    public function down()
    {
        foreach (['entity_settings', 'settings', 'setting_options', 'setting_definitions'] as $name) {
            Schema::dropIfExists($name);
        }
    }
}
