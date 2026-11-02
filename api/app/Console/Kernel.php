<?php

namespace App\Console;

use App\Services\ScheduledTasks;
use Illuminate\Console\Scheduling\Schedule;
use Illuminate\Support\Facades\Artisan;
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
        Commands\PurgeTripChats::class,
        Commands\PurgeExpiredConversations::class,
        Commands\RemoveInactiveWorkers::class,
        Commands\ExpireAccessRecoveries::class,
        Commands\WarnPasswordExpiry::class,
        Commands\NotifyTripDelays::class,
    ];

    /**
     * Tareas programadas (docs/02-procesos.md §2.13), definidas en
     * App\Services\ScheduledTasks. Con cron hace falta ejecutar cada minuto:
     * php artisan schedule:run. Sin cron, TASKS_ON_REQUESTS=true.
     *
     * Se ejecutan dentro del mismo proceso (sin lanzar "php artisan" aparte),
     * porque en un hospedaje compartido no suele poder lanzarse procesos.
     *
     * @param  \Illuminate\Console\Scheduling\Schedule  $schedule
     * @return void
     */
    protected function schedule(Schedule $schedule)
    {
        foreach (ScheduledTasks::TASKS as $command => $frequency) {
            $event = $schedule->call(function () use ($command) {
                Artisan::call($command);
            })->name($command);

            if ($frequency === 'minute') {
                $event->everyMinute()->withoutOverlapping();
            } elseif ($frequency === 'hour') {
                $event->hourly();
            } else {
                $event->dailyAt($frequency);
            }
        }
    }
}
