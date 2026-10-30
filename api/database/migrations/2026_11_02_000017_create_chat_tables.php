<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Chats. Los mensajes se borran físicamente (única excepción al borrado
 * lógico); deleted_at se mantiene por uniformidad.
 */
class CreateChatTables extends Migration
{
    /**
     * Run the migrations.
     *
     * @return void
     */
    public function up()
    {
        Schema::create('trip_messages', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_id')->constrained();
            $table->foreignId('worker_id')->constrained();
            $table->text('body');
            $table->timestamps();
            $table->softDeletes();

            $table->index(['trip_id', 'created_at']);
        });

        Schema::create('conversations', function (Blueprint $table) {
            $table->id();
            $table->foreignId('conversation_topic_id')->constrained();
            $table->foreignId('opened_by')->constrained('workers');
            $table->foreignId('itinerary_id')->nullable()->comment('Solo para los Jefes de itinerario')->constrained();
            $table->timestamps();
            $table->softDeletes();
        });

        Schema::create('conversation_messages', function (Blueprint $table) {
            $table->id();
            $table->foreignId('conversation_id')->constrained();
            $table->foreignId('worker_id')->constrained();
            $table->text('body');
            $table->timestamps();
            $table->softDeletes();

            $table->index(['conversation_id', 'created_at']);
        });
    }

    /**
     * Reverse the migrations.
     *
     * @return void
     */
    public function down()
    {
        Schema::dropIfExists('conversation_messages');
        Schema::dropIfExists('conversations');
        Schema::dropIfExists('trip_messages');
    }
}
