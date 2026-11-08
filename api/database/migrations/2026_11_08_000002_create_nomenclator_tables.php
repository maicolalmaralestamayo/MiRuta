<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Nomencladores (docs/11 §11.26, §11.31 y §11.46): nombre, descripción,
 * observación y activación. Lo que está en uso no se elimina (se desactiva).
 */
return new class extends Migration
{
    public const TABLES = ['vehicle_types', 'absence_types', 'conversation_topics', 'denial_reasons', 'detention_causes'];

    public function up(): void
    {
        foreach (self::TABLES as $name) {
            Schema::create($name, function (Blueprint $table) use ($name) {
                $table->id();
                $table->string('name', 100)->unique();
                $table->text('description')->nullable();
                $table->text('observation')->nullable();

                if ($name === 'vehicle_types') {
                    $table->unsignedSmallInteger('seats')->default(0)->comment('Asientos');
                    $table->unsignedSmallInteger('standing')->default(0)->comment('Pasajeros de pie');
                }

                if ($name === 'denial_reasons') {
                    $table->enum('application_type', ['entidad', 'itinerario'])->nullable()
                        ->comment('Tipo de solicitud a la que se aplica; NULL = a todas');
                }

                $table->boolean('active')->default(true);
                $table->timestamps();
            });
        }
    }

    public function down(): void
    {
        foreach (array_reverse(self::TABLES) as $name) {
            Schema::dropIfExists($name);
        }
    }
};
