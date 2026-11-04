<?php

namespace App\Http\Controllers;

use App\JsonApi\JsonApiResponse;
use App\Services\Permissions;
use App\Support\Operations;
use Illuminate\Http\Request;

/**
 * Catálogo fijo de operaciones (docs/11 §11.16): solo se consulta, con
 * roles.view (o roles.manage).
 */
class OperationCatalogController extends Controller
{
    public function index(Request $request)
    {
        $permissions = app(Permissions::class);

        if (! $permissions->can($request->user(), 'roles.manage')) {
            $permissions->authorize($request->user(), 'roles.view');
        }

        $data = array_map(function ($operation) {
            return ['type' => 'operations', 'id' => $operation, 'attributes' => Operations::toArray($operation)];
        }, Operations::keys());

        return JsonApiResponse::make(['data' => $data, 'meta' => ['scopes' => Operations::SCOPE_NAMES]]);
    }
}
