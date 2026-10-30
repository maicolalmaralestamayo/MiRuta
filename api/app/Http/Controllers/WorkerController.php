<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiResponse;
use App\Rules\CardNumberRule;
use App\Serializers\WorkerSerializer;
use App\Services\WorkerRegistration;
use App\Support\CardNumber;
use Illuminate\Http\Request;

class WorkerController extends Controller
{
    /**
     * Registro público. El primer trabajador registrado es Administrador.
     */
    public function store(Request $request, WorkerRegistration $registration, WorkerSerializer $serializer)
    {
        $data = $this->validateResource($request, 'workers', [
            'attributes.cardNumber' => ['required', 'string', new CardNumberRule()],
            'attributes.firstName' => ['required', 'string', 'max:100'],
            'attributes.lastName' => ['required', 'string', 'max:150'],
            'attributes.password' => ['required', 'string', 'min:8', 'max:72'],
            'relationships.rank.data.type' => ['required', 'in:ranks'],
            'relationships.rank.data.id' => ['required', 'exists:ranks,id,deleted_at,NULL'],
        ]);

        $attributes = $data['attributes'];

        $worker = $registration->register(
            CardNumber::tryParse($attributes['cardNumber']),
            trim($attributes['firstName']),
            trim($attributes['lastName']),
            (int) $data['relationships']['rank']['data']['id'],
            $attributes['password']
        );

        $document = (new Document($request))->resource($worker->fresh());

        return JsonApiResponse::make($document, 201, ['Location' => $serializer->selfLink($worker)]);
    }
}
