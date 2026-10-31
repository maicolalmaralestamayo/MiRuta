<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\Http\Middleware\AuthenticateInstallation;
use App\Models\Conversation;
use App\Models\Installation;
use App\Models\User;
use App\Services\TokenService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

class TokenController extends Controller
{
    /**
     * Hash bcrypt de una contraseña cualquiera. Se verifica contra él cuando
     * el usuario no existe, para que el tiempo de respuesta no lo delate.
     */
    const DUMMY_HASH = '$2y$10$7rLSvRVyTQORapkDOqmkhetjF6H9lJHngr4hJMSM2lHObJbW5EQh6';

    /** @var TokenService */
    private $tokens;

    public function __construct(TokenService $tokens)
    {
        $this->tokens = $tokens;
    }

    /**
     * Inicio de sesión con usuario y contraseña.
     */
    public function store(Request $request)
    {
        $data = $this->validateResource($request, 'tokens', [
            'attributes.username' => ['required', 'string'],
            'attributes.password' => ['required', 'string'],
            'attributes.deviceName' => ['nullable', 'string', 'max:100'],
        ]);
        $attributes = $data['attributes'];

        $user = User::findByUsername($attributes['username']);

        if (! Hash::check($attributes['password'], $user && $user->password ? $user->password : self::DUMMY_HASH) || ! $user || ! $user->password) {
            throw new JsonApiException(401, 'INVALID_CREDENTIALS', 'Credenciales incorrectas', 'El usuario o la contraseña no son correctos.');
        }

        if ($installation = AuthenticateInstallation::resolve($request)) {
            self::linkInstallation($installation, $user);
        }

        $deviceName = isset($attributes['deviceName']) ? $attributes['deviceName'] : null;

        return self::respond($this->tokens->issue($user, $deviceName));
    }

    /**
     * La instalación pasa a ser de esa cuenta, y sus conversaciones sin
     * cuenta pasan a la cuenta (docs/08-version-2.md §8.7).
     */
    public static function linkInstallation(Installation $installation, User $user): void
    {
        $installation->user_id = $user->id;
        $installation->save();

        Conversation::where('installation_id', $installation->id)->whereNull('opened_by')
            ->update(['opened_by' => $user->id]);
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

        return self::respond($pair);
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

    public static function respond(array $pair)
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
                'user' => ['data' => ['type' => 'users', 'id' => (string) $pair['model']->user_id]],
            ],
        ]), 201);
    }
}
