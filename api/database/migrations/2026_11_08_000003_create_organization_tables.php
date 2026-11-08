<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Entidades, itinerarios, paradas (compartidas), personas en las Entidades,
 * ausencias, hijos y solicitudes (docs/11 §11.19 a §11.30).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('entities', function (Blueprint $table) {
            $table->id();
            $table->string('abbreviation', 15)->unique()->comment('En mayúsculas');
            $table->char('number', 4)->nullable()->unique();
            $table->string('name', 150);
            $table->text('description')->nullable();
            $table->text('observation')->nullable();
            $table->string('image_path')->nullable();
            $table->boolean('active')->default(true);
            $table->timestamps();
        });

        Schema::create('itineraries', function (Blueprint $table) {
            $table->id();
            $table->foreignId('entity_id')->constrained()->cascadeOnDelete();
            $table->string('name', 100);
            $table->text('description')->nullable();
            $table->text('observation')->nullable();
            $table->string('image_path')->nullable();
            $table->boolean('active')->default(true);
            $table->timestamps();
            $table->unique(['entity_id', 'name']);
        });

        // Una parada puede estar en varios itinerarios de varias Entidades.
        Schema::create('stops', function (Blueprint $table) {
            $table->id();
            $table->string('landmark')->comment('Punto de referencia');
            $table->string('street');
            $table->string('cross_street_1')->nullable();
            $table->string('cross_street_2')->nullable();
            $table->decimal('latitude', 10, 7);
            $table->decimal('longitude', 10, 7);
            $table->string('image_path')->nullable();
            $table->boolean('active')->default(true);
            $table->timestamps();
        });

        Schema::create('itinerary_stop', function (Blueprint $table) {
            $table->id();
            $table->foreignId('itinerary_id')->constrained()->cascadeOnDelete();
            $table->foreignId('stop_id')->constrained()->cascadeOnDelete();
            $table->unsignedSmallInteger('position')->comment('1 = primera parada; la última es la última');
            $table->timestamps();
            $table->unique(['itinerary_id', 'stop_id']);
            $table->index(['itinerary_id', 'position']);
        });

        // La persona en una Entidad (un solo itinerario por Entidad y una sola
        // parada por itinerario; los dos opcionales).
        Schema::create('workers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('entity_id')->constrained()->cascadeOnDelete();
            $table->foreignId('itinerary_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('stop_id')->nullable()->constrained()->nullOnDelete();
            $table->boolean('is_chief')->default(false)->comment('Jefe de su itinerario (uno solo por persona)');
            $table->boolean('active')->default(true);
            $table->timestamps();
            $table->unique(['user_id', 'entity_id']);
            $table->index(['itinerary_id', 'stop_id']);
        });

        Schema::create('absences', function (Blueprint $table) {
            $table->id();
            $table->foreignId('worker_id')->constrained()->cascadeOnDelete();
            $table->foreignId('absence_type_id')->constrained();
            $table->date('starts_on');
            $table->date('ends_on')->nullable()->comment('NULL = indefinida');
            $table->text('note')->nullable();
            $table->timestamps();
            $table->index(['worker_id', 'starts_on']);
        });

        Schema::create('children', function (Blueprint $table) {
            $table->id();
            $table->text('identity_card_encrypted');
            $table->char('identity_card_hash', 64)->unique();
            $table->string('first_name', 50);
            $table->string('middle_name', 50)->nullable();
            $table->string('first_surname', 50);
            $table->string('second_surname', 50);
            $table->enum('sex', ['F', 'M']);
            $table->date('birth_date');
            $table->string('photo_path')->nullable();
            $table->boolean('active')->default(true);
            $table->timestamps();
        });

        Schema::create('child_parents', function (Blueprint $table) {
            $table->id();
            $table->foreignId('child_id')->constrained('children')->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->timestamps();
            $table->unique(['child_id', 'user_id']);
        });

        Schema::create('applications', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->comment('Quien la hace')->constrained()->cascadeOnDelete();
            $table->enum('type', ['entidad', 'itinerario']);
            $table->enum('status', ['pendiente', 'aprobada', 'rechazada']);
            $table->foreignId('entity_id')->constrained()->cascadeOnDelete();
            $table->foreignId('itinerary_id')->nullable()->constrained()->cascadeOnDelete();
            $table->foreignId('stop_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('denial_reason_id')->nullable()->constrained();
            $table->text('resolution_note')->nullable();
            $table->foreignId('resolved_by')->nullable()->constrained('users')->nullOnDelete();
            $table->dateTime('resolved_at')->nullable();
            $table->dateTime('seen_at')->nullable()->comment('Quien la hizo vio la resolución');
            $table->timestamps();
            $table->index(['status', 'type']);
        });
    }

    public function down(): void
    {
        foreach (['applications', 'child_parents', 'children', 'absences', 'workers', 'itinerary_stop', 'stops', 'itineraries', 'entities'] as $name) {
            Schema::dropIfExists($name);
        }
    }
};
