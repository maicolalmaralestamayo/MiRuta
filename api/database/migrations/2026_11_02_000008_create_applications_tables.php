<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateApplicationsTables extends Migration
{
    const TYPES = [
        'itinerary_membership', 'itinerary_chief', 'driver', 'transport_chief',
        'child_addition', 'child_removal', 'absence', 'itinerary_leave', 'itinerary_chief_leave',
        'driver_leave', 'transport_chief_leave', 'itinerary_removal',
    ];

    /**
     * Hijos y solicitudes. Las solicitudes son el historial: también las
     * asignaciones y retiradas que hace un superior (created_by) y las bajas
     * que genera el sistema (created_by NULL).
     *
     * @return void
     */
    public function up()
    {
        Schema::create('children', function (Blueprint $table) {
            $table->id();
            $table->foreignId('worker_id')->constrained();
            $table->string('first_name', 50);
            $table->string('middle_name', 50);
            $table->string('first_surname', 50);
            $table->string('second_surname', 50);
            $table->date('birth_date')->comment('Privada: el padre o la madre, sus jefes al aprobar y el Administrador');
            $table->timestamps();
            $table->softDeletes();
            $table->index(['birth_date', 'first_name', 'first_surname']);
        });

        Schema::create('applications', function (Blueprint $table) {
            $table->id();
            $table->foreignId('worker_id')->comment('Trabajador al que se refiere')->constrained();
            $table->enum('type', self::TYPES);
            $table->enum('status', ['pending', 'approved', 'rejected', 'cancelled']);
            $table->foreignId('created_by')->nullable()->comment('Quien la creó: el trabajador, un superior (asignación) o NULL (el sistema)')->constrained('users');
            $table->foreignId('resolved_by')->nullable()->constrained('users');
            $table->dateTime('resolved_at')->nullable();
            $table->text('resolution_note')->nullable();
            $table->timestamps();
            $table->softDeletes();
            $table->index(['status', 'type']);
            $table->index(['worker_id', 'created_at']);
        });

        Schema::create('itinerary_applications', function (Blueprint $table) {
            $table->foreignId('application_id')->primary()->constrained();
            $table->foreignId('itinerary_id')->constrained();
            $table->unsignedBigInteger('stop_id')->nullable();
            $table->timestamps();
            $table->softDeletes();
            $table->foreign('stop_id')->references('id')->on('stops');
            $table->foreign(['itinerary_id', 'stop_id'])->references(['itinerary_id', 'stop_id'])->on('itinerary_stop');
        });

        Schema::create('child_applications', function (Blueprint $table) {
            $table->foreignId('application_id')->primary()->constrained();
            $table->foreignId('child_id')->constrained('children');
            $table->timestamps();
            $table->softDeletes();
        });

        Schema::create('absence_applications', function (Blueprint $table) {
            $table->foreignId('application_id')->primary()->constrained();
            $table->foreignId('absence_type_id')->constrained();
            $table->date('starts_on');
            $table->date('ends_on');
            $table->text('observation')->nullable();
            $table->timestamps();
            $table->softDeletes();
            $table->index(['starts_on', 'ends_on']);
        });
    }

    /**
     * @return void
     */
    public function down()
    {
        foreach (['absence_applications', 'child_applications', 'itinerary_applications', 'applications', 'children'] as $name) {
            Schema::dropIfExists($name);
        }
    }
}
