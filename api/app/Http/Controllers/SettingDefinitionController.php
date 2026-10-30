<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiResponse;
use App\Services\Settings;
use Illuminate\Http\Request;

class SettingDefinitionController extends Controller
{
    public function index(Request $request, Settings $settings)
    {
        return JsonApiResponse::make((new Document($request))->list(array_values($settings->definitions())));
    }

    public function show(Request $request, Settings $settings, string $id)
    {
        return JsonApiResponse::make((new Document($request))->resource($settings->definition($id)));
    }
}
