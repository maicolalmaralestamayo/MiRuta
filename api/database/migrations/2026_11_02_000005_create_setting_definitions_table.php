<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateSettingDefinitionsTable extends Migration
{
    /**
     * Run the migrations.
     *
     * @return void
     */
    public function up()
    {
        Schema::create('setting_definitions', function (Blueprint $table) {
            $table->id();
            $table->string('key', 100)->unique();
            $table->string('name', 100);
            $table->text('description')->nullable();
            $table->text('observation')->nullable();
            $table->enum('value_type', ['integer', 'boolean', 'string', 'time', 'option']);
            $table->string('default_value', 1000);
            $table->integer('min_value')->nullable()->comment('Para texto: longitud mínima');
            $table->integer('max_value')->nullable()->comment('Para texto: longitud máxima');
            $table->foreignId('min_setting_definition_id')->nullable()
                ->comment('Ajuste global que fija el valor mínimo de este')
                ->constrained('setting_definitions');
            $table->enum('editable_by', ['administrator', 'transport_chief'])->nullable()
                ->comment('Quién cambia el valor global; el Administrador siempre puede');
            $table->boolean('user_overridable')->default(false);
            $table->timestamps();
            $table->softDeletes();
        });
    }

    /**
     * Reverse the migrations.
     *
     * @return void
     */
    public function down()
    {
        Schema::dropIfExists('setting_definitions');
    }
}
