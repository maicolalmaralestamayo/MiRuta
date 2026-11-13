<?php

use App\Http\Controllers as C;
use App\Http\Controllers\Nomenclators as N;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| API v1 (JSON:API) — prefijo api/v1, grupo «api»
|--------------------------------------------------------------------------
|
| Todas las rutas exigen la negociación de JSON:API y comprueban la versión
| de la app (cabecera X-App-Version; docs/11 §11.54). Las de subida de
| archivos (nombre «subida.*») aceptan multipart/form-data. Detalle en
| docs/13-api-proxima-version.md.
|
*/

// Públicas
Route::post('users', [C\UserController::class, 'store']);
Route::get('registration-status', [C\UserController::class, 'registrationStatus']);
Route::get('username-suggestion', [C\UserController::class, 'usernameSuggestion']);
Route::get('password-suggestion', [C\UserController::class, 'passwordSuggestion']);
Route::get('password-policy', [C\PasswordPolicyController::class, 'show']);
Route::post('tokens', [C\TokenController::class, 'store']);
Route::post('tokens/refresh', [C\TokenController::class, 'refresh']);
Route::post('installations', [C\InstallationController::class, 'store']);
Route::get('app-versions/latest', [C\AppVersionController::class, 'latest']);
Route::get('qr-public-key', [C\QrController::class, 'publicKey']);

// Mantenimiento del servidor (el Administrador con su sesión o la clave de mantenimiento)
Route::middleware('maintenance')->group(function () {
    Route::get('server-status', [C\MaintenanceController::class, 'status']);
    Route::post('maintenance-runs', [C\MaintenanceController::class, 'run']);
});

// Sin cuenta, desde una instalación de la app (cabecera X-Installation): «Olvidé algo»
Route::prefix('guest')->middleware('installation')->group(function () {
    Route::post('access-recoveries', [C\AccessRecoveryController::class, 'store']);
    Route::get('access-recoveries/{id}', [C\AccessRecoveryController::class, 'showForInstallation']);
});

// Con sesión o con instalación
Route::get('entities/lookup', [C\EntityController::class, 'lookup'])->middleware('auth.any');

// Con sesión
Route::middleware('auth.token')->group(function () {
    Route::delete('tokens/current', [C\TokenController::class, 'destroyCurrent']);
    Route::delete('tokens', [C\TokenController::class, 'destroyAll']);

    Route::get('me', [C\MeController::class, 'show']);
    Route::patch('me', [C\MeController::class, 'update']);
    Route::post('me/photo', [C\MeController::class, 'uploadPhoto'])->name('subida.me');
    Route::delete('me/photo', [C\MeController::class, 'deletePhoto']);
    Route::post('me/qr-devices', [C\QrController::class, 'storeDevice']);
    Route::post('me/applications-seen', [C\MeController::class, 'applicationsSeen']);

    Route::get('sync', [C\SyncController::class, 'show']);

    $resource = function (string $uri, string $controller, array $only = ['index', 'show', 'store', 'update', 'destroy']) {
        $routes = [
            'index' => ['get', $uri],
            'store' => ['post', $uri],
            'show' => ['get', $uri.'/{id}'],
            'update' => ['patch', $uri.'/{id}'],
            'destroy' => ['delete', $uri.'/{id}'],
        ];

        foreach ($only as $action) {
            [$method, $path] = $routes[$action];
            Route::{$method}($path, [$controller, $action])->where('id', '[0-9]+');
        }
    };

    // Gestión
    $resource('entities', C\EntityController::class);
    $resource('itineraries', C\ItineraryController::class);
    Route::patch('itineraries/{id}/relationships/stops', [C\ItineraryController::class, 'reorderStops'])->where('id', '[0-9]+');
    $resource('stops', C\StopController::class);
    $resource('itinerary-stops', C\ItineraryStopController::class, ['index', 'store', 'update', 'destroy']);
    $resource('users', C\PersonController::class, ['index', 'show', 'update', 'destroy']);
    $resource('workers', C\WorkerController::class);
    $resource('worker-itineraries', C\WorkerItineraryController::class);
    Route::get('management-summary', [C\ManagementSummaryController::class, 'show']);
    $resource('applications', C\ApplicationController::class);
    $resource('absences', C\AbsenceController::class);
    $resource('children', C\ChildController::class);
    Route::post('children/{id}/photo', [C\ChildController::class, 'uploadPhoto'])->name('subida.child')->where('id', '[0-9]+');
    Route::delete('children/{id}/photo', [C\ChildController::class, 'deletePhoto'])->where('id', '[0-9]+');
    Route::post('{resource}/{id}/image', [C\ImageController::class, 'upload'])->name('subida.image')
        ->where(['resource' => 'entities|itineraries|stops', 'id' => '[0-9]+']);
    Route::delete('{resource}/{id}/image', [C\ImageController::class, 'destroy'])
        ->where(['resource' => 'entities|itineraries|stops', 'id' => '[0-9]+']);

    // Incluir por QR
    Route::post('qr-scans', [C\QrController::class, 'scan']);
    Route::post('qr-inclusions', [C\QrController::class, 'include']);

    // Nomencladores
    $resource('vehicle-types', N\VehicleTypeController::class);
    $resource('absence-types', N\AbsenceTypeController::class);
    $resource('conversation-topics', N\ConversationTopicController::class);
    $resource('denial-reasons', N\DenialReasonController::class);
    $resource('detention-causes', N\DetentionCauseController::class);

    // Viajes y tiempo real
    $resource('trips', C\TripController::class);
    Route::get('trips/{id}/live', [C\TripController::class, 'live'])->where('id', '[0-9]+');
    Route::get('trips/{id}/passengers', [C\TripController::class, 'passengers'])->where('id', '[0-9]+');
    Route::post('trips/{id}/reports', [C\TripController::class, 'report'])->where('id', '[0-9]+');

    // Conversaciones con el desarrollador
    $resource('conversations', C\ConversationController::class, ['index', 'show', 'store']);
    Route::get('conversations/{id}/messages', [C\ConversationController::class, 'messages'])->where('id', '[0-9]+');
    Route::post('conversations/{id}/messages', [C\ConversationController::class, 'storeMessage'])->where('id', '[0-9]+');

    // Ajustes de la app
    Route::get('settings', [C\SettingController::class, 'index']);
    Route::get('settings/{id}', [C\SettingController::class, 'show']);
    Route::patch('settings/{id}', [C\SettingController::class, 'update']);

    // Actualizaciones de la app, «Olvidé algo» e instalaciones (Administrador)
    Route::get('app-versions', [C\AppVersionController::class, 'index']);
    Route::post('app-versions', [C\AppVersionController::class, 'store'])->name('subida.apk');
    Route::patch('app-versions/{id}', [C\AppVersionController::class, 'update'])->where('id', '[0-9]+');
    Route::delete('app-versions/{id}', [C\AppVersionController::class, 'destroy'])->where('id', '[0-9]+');
    Route::get('access-recoveries', [C\AccessRecoveryController::class, 'index']);
    Route::get('access-recoveries/{id}', [C\AccessRecoveryController::class, 'show']);
    Route::patch('access-recoveries/{id}', [C\AccessRecoveryController::class, 'update']);
    Route::get('installations/{id}', [C\InstallationController::class, 'show']);
    Route::patch('installations/{id}', [C\InstallationController::class, 'update']);
});
