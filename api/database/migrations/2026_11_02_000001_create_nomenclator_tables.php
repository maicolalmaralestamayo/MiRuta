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
        // Roles configurables (docs/11 §11.16). El Administrador no es una fila:
        // es users.is_admin y tiene todas las operaciones con ámbito «Todas».
        Schema::create('roles', function (Blueprint $table) {
            $table->id();
            $table->string('name', 100)->unique();
            $table->string('icon', 100)->nullable()->comment('Nombre de un ícono de Material');
            $table->boolean('requestable')->default(false)->comment('Los trabajadores lo pueden solicitar');
            $table->boolean('is_default')->default(false)->comment('Se asigna al aprobarse la entrada en una Entidad (como mucho uno)');
            $table->boolean('itinerary_scoped')->default(false)->comment('Se asigna con un itinerario (p. ej. Jefe de itinerario)');
            $table->timestamps();
            $table->softDeletes();
        });

        Schema::create('role_permissions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('role_id')->constrained();
            $table->string('operation', 60)->comment('Clave del catálogo fijo App\\Support\\Operations');
            $table->enum('scope', ['own', 'itinerary', 'entity', 'all']);
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['role_id', 'operation']);
        });

        Schema::create('role_approvers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('role_id')->comment('Rol solicitado')->constrained();
            $table->foreignId('approver_role_id')->comment('Rol que aprueba sus solicitudes')->constrained('roles');
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['role_id', 'approver_role_id']);
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
            $table->enum('recipient', ['role', 'developer'])->comment('role: a quienes tienen ese rol en la Entidad (o el itinerario)');
            $table->foreignId('role_id')->nullable()->constrained();
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['name', 'recipient', 'role_id']);
        });

    }

    /**
     * @return void
     */
    public function down()
    {
        foreach (['conversation_topics', 'absence_types', 'vehicle_types', 'role_approvers', 'role_permissions', 'roles'] as $name) {
            Schema::dropIfExists($name);
        }
    }
}
