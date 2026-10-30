<?php

/** @var \Laravel\Lumen\Routing\Router $router */

/*
|--------------------------------------------------------------------------
| API v1 (JSON:API)
|--------------------------------------------------------------------------
*/

$router->group(['prefix' => 'api/v1', 'middleware' => 'jsonapi'], function () use ($router) {
    // Públicas
    $router->post('workers', 'WorkerController@store');
    $router->get('ranks', 'RankController@index');
    $router->get('ranks/{id}', 'RankController@show');
    $router->post('tokens', 'TokenController@store');
    $router->post('tokens/refresh', 'TokenController@refresh');

    // Con sesión
    $router->group(['middleware' => 'auth'], function () use ($router) {
        $router->delete('tokens/current', 'TokenController@destroyCurrent');
        $router->delete('tokens', 'TokenController@destroyAll');

        $router->get('me', 'MeController@show');
        $router->patch('me', 'MeController@update');
        $router->delete('me/photo', 'MeController@deletePhoto');
        $router->get('me/settings', 'UserSettingController@index');
        $router->patch('me/settings/{id}', 'UserSettingController@update');
        $router->delete('me/settings/{id}', 'UserSettingController@destroy');

        $router->get('setting-definitions', 'SettingDefinitionController@index');
        $router->get('setting-definitions/{id}', 'SettingDefinitionController@show');
        $router->get('settings', 'SettingController@index');
        $router->get('settings/{id}', 'SettingController@show');
        $router->patch('settings/{id}', 'SettingController@update');

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

        $resource('ranks', 'RankController', ['store', 'update', 'destroy']);
        $resource('vehicle-types', 'VehicleTypeController');
        $resource('absence-types', 'AbsenceTypeController');
        $resource('conversation-topics', 'ConversationTopicController');
        $resource('itineraries', 'ItineraryController');
        $resource('stops', 'StopController');
        $resource('itinerary-stops', 'ItineraryStopController');
        $resource('vehicles', 'VehicleController');
        $resource('workers', 'WorkerController', ['index', 'show', 'update']);
        $resource('itinerary-chiefs', 'ItineraryChiefController', ['index', 'show', 'destroy']);
        $resource('drivers', 'DriverController', ['index', 'show', 'destroy']);
        $resource('transport-chiefs', 'TransportChiefController', ['index', 'show', 'destroy']);
        $resource('applications', 'ApplicationController', ['index', 'show', 'store', 'update']);
        $resource('children', 'ChildController', ['index', 'show']);
        $resource('notices', 'NoticeController', ['index', 'update']);
        $resource('trips', 'TripController', ['index', 'show', 'store', 'update']);
        $router->get('trips/{id}/passengers', 'TripPassengerController@index');
        $resource('trip-completions', 'TripCompletionController', ['index', 'store']);
        $router->post('operations', 'OperationController@store');
        $resource('trip-legs', 'TripLegController', ['index', 'show', 'store', 'update']);
        $resource('trip-positions', 'TripPositionController', ['index', 'store']);
        $resource('trip-stop-passes', 'TripStopPassController', ['index']);
        $resource('trip-boardings', 'TripBoardingController', ['index', 'store']);
        $router->post('boarding-passes', 'BoardingPassController@store');
    });
});

/*
|--------------------------------------------------------------------------
| Subida de archivos (multipart/form-data; respuesta JSON:API)
|--------------------------------------------------------------------------
*/

$router->group(['prefix' => 'api/v1', 'middleware' => ['jsonapi:multipart', 'auth']], function () use ($router) {
    $router->post('me/photo', 'MeController@uploadPhoto');
    $router->post('ranks/{id}/icon', 'RankController@uploadIcon');
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
