<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateApplicationsTables extends Migration
{
    const TYPES = ['entity_membership', 'itinerary_membership', 'role'];

    /**
     * Hijos (de la persona, con carné) y solicitudes (docs/11 §11.6, §11.11
     * y §11.16). Darse de baja es una acción directa, no una solicitud.
     *
     * @return void
     */
    public function up()
    {
        Schema::create('children', function (Blueprint $table) {
            $table->id();
            $table->text('identity_card_encrypted');
            $table->char('identity_card_hash', 64)->unique()->comment('HMAC del carné');
            $table->string('first_name', 50);
            $table->string('middle_name', 50)->nullable();
            $table->string('first_surname', 50);
            $table->string('second_surname', 50);
            $table->enum('sex', ['F', 'M'])->comment('Sale del carné');
            $table->date('birth_date')->comment('Sale del carné');
            $table->string('photo_path')->nullable();
            $table->boolean('active')->default(true)->comment('Los padres lo pueden desactivar y reactivar');
            $table->timestamps();
            $table->softDeletes()->comment('Cuando ya no le queda ningún padre');
        });

        Schema::create('child_parents', function (Blueprint $table) {
            $table->id();
            $table->foreignId('child_id')->constrained('children');
            $table->foreignId('user_id')->comment('Padre o madre que lo declaró')->constrained();
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['child_id', 'user_id']);
        });

        Schema::create('applications', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->comment('Persona a la que se refiere')->constrained();
            $table->foreignId('entity_id')->constrained();
            $table->enum('type', self::TYPES);
            $table->enum('status', ['pending', 'approved', 'rejected', 'cancelled']);
            $table->foreignId('itinerary_id')->nullable()->comment('itinerary_membership y roles por itinerario')->constrained();
            $table->foreignId('stop_id')->nullable()->comment('itinerary_membership')->constrained();
            $table->foreignId('role_id')->nullable()->comment('role')->constrained();
            $table->foreignId('created_by')->nullable()->constrained('users');
            $table->foreignId('resolved_by')->nullable()->constrained('users');
            $table->dateTime('resolved_at')->nullable();
            $table->text('resolution_note')->nullable();
            $table->timestamps();
            $table->softDeletes();
            $table->index(['status', 'type']);
            $table->index(['user_id', 'created_at']);
            $table->index(['entity_id', 'status']);
        });
    }

    /**
     * @return void
     */
    public function down()
    {
        foreach (['applications', 'child_parents', 'children'] as $name) {
            Schema::dropIfExists($name);
        }
    }
}
