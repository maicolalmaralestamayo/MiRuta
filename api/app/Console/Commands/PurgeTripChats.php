<?php

namespace App\Console\Commands;

use App\Models\Trip;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Borra los mensajes de los viajes cancelados o realizados (7.27). El borrado
 * también se hace al cambiar el estado; esto es una red de seguridad.
 */
class PurgeTripChats extends Command
{
    protected $signature = 'chats:purge-trips';

    protected $description = 'Borra los chats de los viajes cancelados o realizados';

    public function handle()
    {
        $deleted = DB::table('trip_messages')
            ->whereIn('trip_id', Trip::withTrashed()->whereIn('status', [Trip::STATUS_CANCELLED, Trip::STATUS_COMPLETED])->select('id'))
            ->delete();

        $this->info("Mensajes borrados: {$deleted}");
    }
}
