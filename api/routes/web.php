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
    $router->post('tokens', 'TokenController@store');
    $router->post('tokens/refresh', 'TokenController@refresh');
    $router->post('activations', 'ActivationController@store');
    $router->post('installations', 'InstallationController@store');
    $router->get('password-policy', 'PasswordPolicyController@show');
    $router->get('ranks', 'RankController@index');
    $router->get('ranks/{id}', 'RankController@show');
    $router->get('conversation-topics', 'ConversationTopicController@index');
    $router->get('conversation-topics/{id}', 'ConversationTopicController@show');
    $router->get('app-versions/latest', 'AppVersionController@latest');

    // Sin cuenta, desde una instalación de la app (cabecera X-Installation)
    $router->group(['prefix' => 'guest', 'middleware' => 'installation'], function () use ($router) {
        $router->post('access-recoveries', 'AccessRecoveryController@store');
        $router->get('access-recoveries/{id}', 'AccessRecoveryController@showForInstallation');
        $router->post('access-recoveries/{id}/password', 'AccessRecoveryController@setPassword');
        $router->get('conversations', 'GuestConversationController@index');
        $router->post('conversations', 'GuestConversationController@store');
        $router->get('conversations/{id}/messages', 'GuestConversationController@messages');
        $router->post('conversations/{id}/messages', 'GuestConversationController@storeMessage');
    });

    // Con sesión o con instalación
    $router->get('entities/lookup', ['middleware' => 'auth.any', 'uses' => 'EntityController@lookup']);

    // Con sesión, aunque la cuenta aún no pertenezca a una Entidad
    $router->group(['middleware' => 'auth'], function () use ($router) {
        $router->delete('tokens/current', 'TokenController@destroyCurrent');
        $router->delete('tokens', 'TokenController@destroyAll');

        $router->get('me', 'MeController@show');
        $router->patch('me', 'MeController@update');
        $router->post('me/worker', 'MeController@joinEntity');
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
    });

    // Con sesión del Administrador o de un trabajador de una Entidad
    $router->group(['middleware' => 'auth:member'], function () use ($router) {
        $router->get('map', 'MapController@show');
        $router->get('setting-definitions', 'SettingDefinitionController@index');
        $router->get('setting-definitions/{id}', 'SettingDefinitionController@show');
        $router->get('settings', 'SettingController@index');
        $router->get('settings/{id}', 'SettingController@show');
        $router->patch('settings/{id}', 'SettingController@update');
        $router->get('entity-settings', 'EntitySettingController@index');
        $router->patch('entity-settings/{id}', 'EntitySettingController@update');
        $router->delete('entity-settings/{id}', 'EntitySettingController@destroy');

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
        $resource('ranks', 'RankController', ['store', 'update', 'destroy']);
        $resource('vehicle-types', 'VehicleTypeController');
        $resource('absence-types', 'AbsenceTypeController');
        $resource('conversation-topics', 'ConversationTopicController', ['store', 'update', 'destroy']);
        $resource('itineraries', 'ItineraryController');
        $resource('stops', 'StopController');
        $resource('itinerary-stops', 'ItineraryStopController');
        $resource('vehicles', 'VehicleController');
        $resource('users', 'AccountController', ['index', 'show', 'update']);
        $resource('workers', 'WorkerController', ['index', 'show', 'store', 'update']);
        $router->post('workers/{id}/activation-codes', 'WorkerController@activationCode');
        $resource('itinerary-chiefs', 'ItineraryChiefController', ['index', 'show', 'destroy']);
        $resource('drivers', 'DriverController', ['index', 'show', 'destroy']);
        $resource('transport-chiefs', 'TransportChiefController', ['index', 'show', 'destroy']);
        $resource('applications', 'ApplicationController', ['index', 'show', 'store', 'update']);
        $resource('children', 'ChildController', ['index', 'show']);
        $resource('trips', 'TripController', ['index', 'show', 'store', 'update']);
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
});

$router->group(['prefix' => 'api/v1', 'middleware' => ['jsonapi:multipart', 'auth:member']], function () use ($router) {
    $router->post('ranks/{id}/icon', 'RankController@uploadIcon');
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
