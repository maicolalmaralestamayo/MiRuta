<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class CreatePasswordResetsTable extends Migration
{
    const NOTICE_TYPES = [
        'application_received', 'application_resolved', 'resignation',
        'inactivity_warning', 'inactivity_removal', 'trip_needs_reassignment',
    ];

    /**
     * Run the migrations.
     *
     * @return void
     */
    public function up()
    {
        Schema::create('password_resets', function (Blueprint $table) {
            $table->id();
            $table->foreignId('worker_id')->constrained();
            $table->text('phone_encrypted')->nullable()->comment('Teléfono para enviar el código por WhatsApp; se borra al terminar');
            $table->text('code_encrypted')->nullable()->comment('Código que ve el Administrador; se borra al terminar');
            $table->char('code_hash', 64)->nullable();
            $table->enum('status', ['pending', 'sent', 'used', 'expired', 'cancelled']);
            $table->unsignedTinyInteger('failed_attempts')->default(0);
            $table->dateTime('expires_at');
            $table->foreignId('sent_by')->nullable()->comment('Administrador que envió el código')->constrained('workers');
            $table->dateTime('sent_at')->nullable();
            $table->dateTime('used_at')->nullable();
            $table->timestamps();
            $table->softDeletes();

            $table->index(['worker_id', 'status']);
        });

        Schema::table('workers', function (Blueprint $table) {
            $table->boolean('must_change_password')->default(false)->after('is_admin');
        });

        Schema::table('notices', function (Blueprint $table) {
            $table->foreignId('password_reset_id')->nullable()->after('trip_id')->constrained();
        });

        $types = "'".implode("','", array_merge(self::NOTICE_TYPES, ['password_reset_requested']))."'";
        DB::statement("ALTER TABLE notices MODIFY type ENUM({$types}) NOT NULL");
    }

    /**
     * Reverse the migrations.
     *
     * @return void
     */
    public function down()
    {
        DB::table('notices')->where('type', 'password_reset_requested')->delete();
        $types = "'".implode("','", self::NOTICE_TYPES)."'";
        DB::statement("ALTER TABLE notices MODIFY type ENUM({$types}) NOT NULL");

        Schema::table('notices', function (Blueprint $table) {
            $table->dropForeign(['password_reset_id']);
            $table->dropColumn('password_reset_id');
        });

        Schema::table('workers', function (Blueprint $table) {
            $table->dropColumn('must_change_password');
        });

        Schema::dropIfExists('password_resets');
    }
}
