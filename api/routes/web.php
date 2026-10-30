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

/*
|--------------------------------------------------------------------------
| Documentación (solo desarrollo)
|--------------------------------------------------------------------------
*/

if (config('mitransporte.docs_enabled')) {
    $router->get('docs', 'DocsController@index');
    $router->get('docs/openapi.yaml', 'DocsController@spec');
}
