<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateChatTables extends Migration
{
    /**
     * Chat del viaje y conversaciones. Una conversación con el desarrollador
     * puede abrirse sin cuenta, desde una instalación de la app
     * (docs/08-version-2.md §8.7).
     *
     * @return void
     */
    public function up()
    {
        Schema::create('trip_messages', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_id')->constrained();
            $table->foreignId('user_id')->constrained();
            $table->text('body');
            $table->timestamps();
            $table->softDeletes();
            $table->index(['trip_id', 'created_at']);
        });

        Schema::create('conversations', function (Blueprint $table) {
            $table->id();
            $table->foreignId('conversation_topic_id')->constrained();
            $table->foreignId('opened_by')->nullable()->comment('NULL = sin cuenta')->constrained('users');
            $table->foreignId('installation_id')->nullable()->comment('Instalación desde la que se abrió sin cuenta')->constrained();
            $table->string('guest_name', 150)->nullable()->comment('Solo sin cuenta');
            $table->text('guest_phone_encrypted')->nullable()->comment('Solo sin cuenta; lo ve el Administrador');
            $table->foreignId('itinerary_id')->nullable()->comment('Solo para los Jefes de itinerario')->constrained();
            $table->foreignId('entity_id')->nullable()->comment('Solo para los Jefes de Transporte')->constrained();
            $table->dateTime('closed_at')->nullable();
            $table->timestamps();
            $table->softDeletes();
        });

        Schema::create('conversation_messages', function (Blueprint $table) {
            $table->id();
            $table->foreignId('conversation_id')->constrained();
            $table->foreignId('user_id')->nullable()->comment('NULL = lo escribió quien abrió la conversación sin cuenta')->constrained();
            $table->text('body');
            $table->timestamps();
            $table->softDeletes();
            $table->index(['conversation_id', 'created_at']);
        });
    }

    /**
     * @return void
     */
    public function down()
    {
        foreach (['conversation_messages', 'conversations', 'trip_messages'] as $name) {
            Schema::dropIfExists($name);
        }
    }
}
