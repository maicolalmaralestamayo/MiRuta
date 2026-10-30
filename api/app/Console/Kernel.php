<?php

namespace App\Console;

use Illuminate\Console\Scheduling\Schedule;
use Laravel\Lumen\Console\Kernel as ConsoleKernel;

class Kernel extends ConsoleKernel
{
    /**
     * The Artisan commands provided by your application.
     *
     * @var array
     */
    protected $commands = [
        Commands\AutoCompleteTrips::class,
    ];

    /**
     * Tareas programadas (docs/02-procesos.md §2.12). En el servidor hace falta
     * un cron que ejecute cada minuto: php artisan schedule:run
     *
     * @param  \Illuminate\Console\Scheduling\Schedule  $schedule
     * @return void
     */
    protected function schedule(Schedule $schedule)
    {
        $schedule->command('trips:auto-complete')->everyMinute()->withoutOverlapping();
    }
}
