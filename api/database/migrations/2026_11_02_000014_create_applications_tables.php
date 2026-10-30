<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateApplicationsTables extends Migration
{
    const TYPES = [
        'itinerary_membership', 'itinerary_chief', 'driver', 'transport_chief', 'rank_change',
        'child_addition', 'child_removal', 'absence', 'itinerary_leave', 'itinerary_chief_leave',
        'driver_leave', 'transport_chief_leave', 'itinerary_removal',
    ];

    /**
     * Run the migrations.
     *
     * @return void
     */
    public function up()
    {
        Schema::create('children', function (Blueprint $table) {
            $table->id();
            $table->foreignId('worker_id')->constrained();
            $table->string('first_name', 100);
            $table->string('last_name', 150);
            $table->text('card_number_encrypted');
            $table->char('card_number_hash', 64)->unique();
            $table->timestamps();
            $table->softDeletes();
        });

        Schema::create('applications', function (Blueprint $table) {
            $table->id();
            $table->foreignId('worker_id')->comment('Solicitante')->constrained();
            $table->enum('type', self::TYPES);
            $table->enum('status', ['pending', 'approved', 'rejected', 'cancelled']);
            $table->foreignId('resolved_by')->nullable()->constrained('workers');
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

        Schema::create('rank_applications', function (Blueprint $table) {
            $table->foreignId('application_id')->primary()->constrained();
            $table->foreignId('rank_id')->constrained();
            $table->timestamps();
            $table->softDeletes();
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

        Schema::create('notices', function (Blueprint $table) {
            $table->id();
            $table->foreignId('worker_id')->comment('Destinatario')->constrained();
            $table->enum('type', [
                'application_received', 'application_resolved', 'resignation',
                'inactivity_warning', 'inactivity_removal', 'trip_needs_reassignment',
            ]);
            $table->foreignId('application_id')->nullable()->constrained();
            // La clave foránea a trips se añade al crear esa tabla.
            $table->unsignedBigInteger('trip_id')->nullable();
            $table->dateTime('read_at')->nullable();
            $table->timestamps();
            $table->softDeletes();

            $table->index(['worker_id', 'read_at']);
        });
    }

    /**
     * Reverse the migrations.
     *
     * @return void
     */
    public function down()
    {
        Schema::dropIfExists('notices');
        Schema::dropIfExists('absence_applications');
        Schema::dropIfExists('child_applications');
        Schema::dropIfExists('rank_applications');
        Schema::dropIfExists('itinerary_applications');
        Schema::dropIfExists('applications');
        Schema::dropIfExists('children');
    }
}
