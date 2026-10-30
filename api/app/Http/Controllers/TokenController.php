<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\Models\Worker;
use App\Services\TokenService;
use App\Support\CardNumber;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

class TokenController extends Controller
{
    /**
     * Hash bcrypt de una contraseña cualquiera. Se verifica contra él cuando
     * el carné no existe, para que el tiempo de respuesta no lo delate.
     */
    const DUMMY_HASH = '$2y$10$7rLSvRVyTQORapkDOqmkhetjF6H9lJHngr4hJMSM2lHObJbW5EQh6';

    /** @var TokenService */
    private $tokens;

    public function __construct(TokenService $tokens)
    {
        $this->tokens = $tokens;
    }

    /**
     * Inicio de sesión con carné y contraseña.
     */
    public function store(Request $request)
    {
        $data = $this->validateResource($request, 'tokens', [
            'attributes.cardNumber' => ['required', 'string'],
            'attributes.password' => ['required', 'string'],
            'attributes.deviceName' => ['nullable', 'string', 'max:100'],
        ]);
        $attributes = $data['attributes'];

        $worker = preg_match('/^\d{11}$/', $attributes['cardNumber'])
            ? Worker::where('card_number_hash', CardNumber::hashOf($attributes['cardNumber']))->first()
            : null;

        if (! Hash::check($attributes['password'], $worker ? $worker->password : self::DUMMY_HASH) || ! $worker) {
            throw new JsonApiException(401, 'INVALID_CREDENTIALS', 'Credenciales incorrectas', 'El carné o la contraseña no son correctos.');
        }

        $deviceName = isset($attributes['deviceName']) ? $attributes['deviceName'] : null;

        return $this->respond($this->tokens->issue($worker, $deviceName));
    }

    /**
     * Renovación con rotación.
     */
    public function refresh(Request $request)
    {
        $data = $this->validateResource($request, 'tokens', [
            'attributes.refreshToken' => ['required', 'string'],
            'attributes.deviceName' => ['nullable', 'string', 'max:100'],
        ]);
        $attributes = $data['attributes'];

        $pair = $this->tokens->refresh($attributes['refreshToken'], isset($attributes['deviceName']) ? $attributes['deviceName'] : null);

        return $this->respond($pair);
    }

    /**
     * Cierra la sesión de este dispositivo.
     */
    public function destroyCurrent(Request $request)
    {
        $sessionId = $request->user()->currentSessionId();

        if ($sessionId) {
            $this->tokens->revoke($sessionId);
        }

        return response('', 204);
    }

    /**
     * Cierra la sesión en todos los dispositivos.
     */
    public function destroyAll(Request $request)
    {
        $this->tokens->revokeAll($request->user()->id);

        return response('', 204);
    }

    private function respond(array $pair)
    {
        return JsonApiResponse::make(Document::fromArray([
            'type' => 'tokens',
            'id' => (string) $pair['model']->id,
            'attributes' => [
                'accessToken' => $pair['accessToken'],
                'refreshToken' => $pair['refreshToken'],
                'tokenType' => 'Bearer',
                'expiresIn' => $pair['expiresIn'],
                'refreshExpiresIn' => $pair['refreshExpiresIn'],
            ],
            'relationships' => [
                'worker' => ['data' => ['type' => 'workers', 'id' => (string) $pair['model']->worker_id]],
            ],
        ]), 201);
    }
}
