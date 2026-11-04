<?php

/** @var \Laravel\Lumen\Routing\Router $router */

/*
|--------------------------------------------------------------------------
| API v1 (JSON:API)
|--------------------------------------------------------------------------
*/

$router->group(['prefix' => 'api/v1', 'middleware' => 'jsonapi'], function () use ($router) {
    // Públicas
    $router->post('users', 'UserController@store');
    $router->get('registration-status', 'UserController@registrationStatus');
    $router->get('username-suggestion', 'UserController@usernameSuggestion');
    $router->get('password-suggestion', 'UserController@passwordSuggestion');
    $router->post('tokens', 'TokenController@store');
    $router->post('tokens/refresh', 'TokenController@refresh');
    $router->post('installations', 'InstallationController@store');
    $router->get('password-policy', 'PasswordPolicyController@show');
    $router->get('conversation-topics', 'ConversationTopicController@index');
    $router->get('conversation-topics/{id}', 'ConversationTopicController@show');
    $router->get('app-versions/latest', 'AppVersionController@latest');

    // Mantenimiento del servidor (maintenance.run o clave de mantenimiento)
    $router->group(['middleware' => 'maintenance'], function () use ($router) {
        $router->get('server-status', 'MaintenanceController@status');
        $router->post('maintenance-runs', 'MaintenanceController@run');
    });

    // Sin cuenta, desde una instalación de la app (cabecera X-Installation)
    $router->group(['prefix' => 'guest', 'middleware' => 'installation'], function () use ($router) {
        $router->post('access-recoveries', 'AccessRecoveryController@store');
        $router->get('access-recoveries/{id}', 'AccessRecoveryController@showForInstallation');
        $router->get('conversations', 'GuestConversationController@index');
        $router->post('conversations', 'GuestConversationController@store');
        $router->get('conversations/{id}/messages', 'GuestConversationController@messages');
        $router->post('conversations/{id}/messages', 'GuestConversationController@storeMessage');
    });

    // Con sesión o con instalación
    $router->get('entities/lookup', ['middleware' => 'auth.any', 'uses' => 'EntityController@lookup']);

    // Con sesión (no hace falta pertenecer a una Entidad: cada uno ve y hace lo que le permiten sus roles)
    $router->group(['middleware' => 'auth'], function () use ($router) {
        $router->delete('tokens/current', 'TokenController@destroyCurrent');
        $router->delete('tokens', 'TokenController@destroyAll');

        $router->get('me', 'MeController@show');
        $router->patch('me', 'MeController@update');
        $router->post('me/entities', 'MeController@joinEntity');
        $router->delete('me/entities/{entityId}', 'MeController@leaveEntity');
        $router->delete('me/photo', 'MeController@deletePhoto');
        $router->get('me/settings', 'UserSettingController@index');
        $router->patch('me/settings/{id}', 'UserSettingController@update');
        $router->delete('me/settings/{id}', 'UserSettingController@destroy');

        $router->get('notices', 'NoticeController@index');
        $router->patch('notices/{id}', 'NoticeController@update');

        $router->get('conversations', 'ConversationController@index');
        $router->get('conversations/{id}', 'ConversationController@show');
        $router->post('conversations', 'ConversationController@store');
        $router->patch('conversations/{id}', 'ConversationController@update');
        $router->get('conversations/{id}/messages', 'ConversationController@messages');
        $router->post('conversation-messages', 'ConversationController@storeMessage');

        $router->get('map', 'MapController@show');
        $router->get('setting-definitions', 'SettingDefinitionController@index');
        $router->get('setting-definitions/{id}', 'SettingDefinitionController@show');
        $router->get('settings', 'SettingController@index');
        $router->get('settings/{id}', 'SettingController@show');
        $router->patch('settings/{id}', 'SettingController@update');
        $router->get('entity-settings', 'EntitySettingController@index');
        $router->patch('entity-settings/{id}', 'EntitySettingController@update');
        $router->delete('entity-settings/{id}', 'EntitySettingController@destroy');
        $router->get('itinerary-settings', 'ItinerarySettingController@index');
        $router->patch('itinerary-settings/{id}', 'ItinerarySettingController@update');
        $router->delete('itinerary-settings/{id}', 'ItinerarySettingController@destroy');
        $router->get('itinerary-stop-settings', 'ItinerarySettingController@stopIndex');
        $router->patch('itinerary-stop-settings/{id}', 'ItinerarySettingController@stopUpdate');
        $router->delete('itinerary-stop-settings/{id}', 'ItinerarySettingController@stopDestroy');

        $resource = function (string $uri, string $controller, array $only = ['index', 'show', 'store', 'update', 'destroy']) use ($router) {
            $routes = [
                'index' => ['get', $uri],
                'store' => ['post', $uri],
                'show' => ['get', $uri.'/{id}'],
                'update' => ['patch', $uri.'/{id}'],
                'destroy' => ['delete', $uri.'/{id}'],
            ];

            foreach ($only as $action) {
                list($method, $path) = $routes[$action];
                $router->{$method}($path, $controller.'@'.$action);
            }
        };

        $resource('entities', 'EntityController');
        $resource('vehicle-types', 'VehicleTypeController');
        $resource('absence-types', 'AbsenceTypeController');
        $resource('conversation-topics', 'ConversationTopicController', ['store', 'update', 'destroy']);
        $resource('itineraries', 'ItineraryController');
        $resource('stops', 'StopController');
        $resource('itinerary-stops', 'ItineraryStopController');
        $resource('vehicles', 'VehicleController');
        $resource('users', 'AccountController', ['index', 'show', 'update']);
        $resource('workers', 'WorkerController');
        $router->delete('workers/{id}/itinerary', 'WorkerController@removeItinerary');
        $resource('roles', 'RoleController');
        $router->get('operations', 'OperationCatalogController@index');
        $resource('worker-roles', 'WorkerRoleController', ['index', 'show', 'store', 'destroy']);
        $resource('applications', 'ApplicationController', ['index', 'show', 'store', 'update']);
        $resource('absences', 'AbsenceController');
        $resource('children', 'ChildController');
        $router->delete('children/{id}/photo', 'ChildController@deletePhoto');
        $router->delete('{resource:entities|itineraries|stops}/{id}/image', 'ImageController@destroy');
        $resource('trips', 'TripController');
        $router->get('trips/{id}/passengers', 'TripPassengerController@index');
        $resource('trip-completions', 'TripCompletionController', ['index', 'store']);
        $router->post('operations', 'OperationController@store');
        $resource('trip-legs', 'TripLegController', ['index', 'show', 'store', 'update']);
        $resource('trip-positions', 'TripPositionController', ['index', 'store']);
        $resource('trip-stop-passes', 'TripStopPassController', ['index']);
        $resource('trip-boardings', 'TripBoardingController', ['index', 'store']);
        $router->post('boarding-passes', 'BoardingPassController@store');
        $router->get('trips/{id}/messages', 'TripMessageController@index');
        $router->post('trip-messages', 'TripMessageController@store');
        $router->get('statistics/{name}', 'StatisticController@show');
        $router->get('app-versions', 'AppVersionController@index');
        $router->delete('app-versions/{id}', 'AppVersionController@destroy');
        $router->get('access-recoveries', 'AccessRecoveryController@index');
        $router->get('access-recoveries/{id}', 'AccessRecoveryController@show');
        $router->patch('access-recoveries/{id}', 'AccessRecoveryController@update');
        $router->get('installations/{id}', 'InstallationController@show');
        $router->patch('installations/{id}', 'InstallationController@update');
    });
});

/*
|--------------------------------------------------------------------------
| Subida de archivos (multipart/form-data; respuesta JSON:API)
|--------------------------------------------------------------------------
*/

$router->group(['prefix' => 'api/v1', 'middleware' => ['jsonapi:multipart', 'auth']], function () use ($router) {
    $router->post('me/photo', 'MeController@uploadPhoto');
    $router->post('children/{id}/photo', 'ChildController@uploadPhoto');
    $router->post('{resource:entities|itineraries|stops}/{id}/image', 'ImageController@upload');
    $router->post('app-versions', 'AppVersionController@store');
});

/*
|--------------------------------------------------------------------------
| Documentación (solo desarrollo)
|--------------------------------------------------------------------------
*/

if (config('mitransporte.docs_enabled')) {
    $router->get('docs', 'DocsController@index');
    $router->get('docs/openapi.yaml', 'DocsController@spec');
}
