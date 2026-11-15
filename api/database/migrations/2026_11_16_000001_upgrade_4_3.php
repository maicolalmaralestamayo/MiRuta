<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Versión 4.3.0 (docs/11 §11.63). Se aplica igual en una instalación nueva y
 * con «Actualizar base de datos» sobre una 4.2.0 (sin perder datos):
 *
 * - Viajando y Recogido se unifican en «Viajando»: los estados «recogido»
 *   guardados pasan a «viajando» y el tipo de la columna deja de admitirlo
 *   (MySQL / MariaDB 10.3; en SQLite la columna no se toca).
 */
return new class extends Migration
{
    private const STATES = ['de_camino', 'en_parada', 'viajando', 'dejado', 'botado', 'dormido', 'no_voy'];

    public function up(): void
    {
        if (! Schema::hasTable('trip_passengers')) {
            return;
        }

        DB::table('trip_passengers')->where('state', 'recogido')->update(['state' => 'viajando']);

        if (in_array(DB::getDriverName(), ['mysql', 'mariadb'], true)) {
            $list = implode(',', array_map(fn ($s) => "'".$s."'", self::STATES));
            DB::statement("ALTER TABLE trip_passengers MODIFY state ENUM({$list}) NOT NULL");
        }
    }

    public function down(): void
    {
        if (in_array(DB::getDriverName(), ['mysql', 'mariadb'], true) && Schema::hasTable('trip_passengers')) {
            $list = implode(',', array_map(fn ($s) => "'".$s."'", ['de_camino', 'en_parada', 'viajando', 'dejado', 'recogido', 'botado', 'dormido', 'no_voy']));
            DB::statement("ALTER TABLE trip_passengers MODIFY state ENUM({$list}) NOT NULL");
        }
        // Los «recogido» ya convertidos se quedan como «viajando».
    }
};
