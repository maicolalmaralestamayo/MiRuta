<?php

use App\Services\ScheduledTasks;
use Illuminate\Support\Facades\Artisan;

// Con cron (opcional): php artisan miruta:tareas cada minuto. Sin cron, las
// tareas se ejecutan con las peticiones (TASKS_ON_REQUESTS) o desde la app
// (Mantenimiento del servidor → Ejecutar tareas).
Artisan::command('miruta:tareas', function (ScheduledTasks $tasks) {
    foreach ($tasks->runDue() as $name => $result) {
        $this->line($name.': '.($result['ok'] ? 'bien' : 'error: '.$result['error']));
    }
})->purpose('Ejecuta las tareas programadas pendientes de MiRuta');
