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
