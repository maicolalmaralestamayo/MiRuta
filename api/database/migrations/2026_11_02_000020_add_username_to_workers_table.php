<?php

use App\Support\Username;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class AddUsernameToWorkersTable extends Migration
{
    /**
     * Nombre de usuario para iniciar sesión, en lugar del carné. A los que ya
     * están registrados se les genera uno a partir del nombre; pueden cambiarlo.
     *
     * @return void
     */
    public function up()
    {
        Schema::table('workers', function (Blueprint $table) {
            // Nulo solo durante esta migración; el registro siempre lo exige.
            $table->string('username', Username::MAX_LENGTH)->nullable()->unique()->after('id')
                ->comment('En minúsculas; único también entre inactivos');
        });

        foreach (DB::table('workers')->orderBy('id')->get(['id', 'first_name', 'last_name']) as $worker) {
            DB::table('workers')->where('id', $worker->id)
                ->update(['username' => Username::suggest($worker->first_name, $worker->last_name)]);
        }
    }

    /**
     * @return void
     */
    public function down()
    {
        Schema::table('workers', function (Blueprint $table) {
            $table->dropUnique(['username']);
            $table->dropColumn('username');
        });
    }
}
