<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Conversaciones con el desarrollador (docs/11 §11.46) y notificaciones que
 * la app recoge al sincronizar (§11.47 y §11.50; no hay servicio de envío).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('conversations', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('conversation_topic_id')->constrained();
            $table->dateTime('last_message_at');
            $table->boolean('unread_by_developer')->default(true);
            $table->boolean('unread_by_user')->default(false);
            $table->timestamps();
        });

        Schema::create('conversation_messages', function (Blueprint $table) {
            $table->id();
            $table->foreignId('conversation_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->nullable()->comment('Autor')->constrained()->nullOnDelete();
            $table->boolean('from_developer')->default(false);
            $table->text('body');
            $table->timestamps();
        });

        Schema::create('notifications', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->comment('Destinatario')->constrained()->cascadeOnDelete();
            $table->string('kind', 40);
            $table->string('title', 150);
            $table->text('body');
            $table->text('data')->nullable()->comment('JSON');
            $table->dateTime('created_at');
            $table->index(['user_id', 'id']);
        });
    }

    public function down(): void
    {
        foreach (['notifications', 'conversation_messages', 'conversations'] as $name) {
            Schema::dropIfExists($name);
        }
    }
};
