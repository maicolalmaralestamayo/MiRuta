<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\PasswordReset;
use App\Services\PasswordResets;
use App\Services\TokenService;
use Illuminate\Http\Request;

class PasswordResetController extends Controller
{
    /** @var PasswordResets */
    private $resets;

    public function __construct(PasswordResets $resets)
    {
        $this->resets = $resets;
    }

    /**
     * Público: el trabajador pide restablecer su contraseña. La respuesta es
     * la misma exista o no el carné.
     */
    public function store(Request $request)
    {
        $data = $this->validateResource($request, 'password-resets', [
            'attributes.cardNumber' => ['required', 'string', 'regex:/^\d{11}$/'],
            'attributes.phone' => ['required', 'string', 'regex:/^\+?[0-9 ()\-]{7,20}$/'],
        ]);

        $this->resets->request($data['attributes']['cardNumber'], trim($data['attributes']['phone']));

        return JsonApiResponse::make(['meta' => [
            'message' => 'Solicitud enviada. El Administrador te enviará un código por WhatsApp.',
        ]], 202);
    }

    /**
     * Público: entrar con el código. Devuelve tokens; la cuenta queda obligada
     * a cambiar la contraseña.
     */
    public function redeem(Request $request, TokenService $tokens)
    {
        $data = $this->validateResource($request, 'tokens', [
            'attributes.cardNumber' => ['required', 'string'],
            'attributes.resetCode' => ['required', 'string', 'max:20'],
            'attributes.deviceName' => ['nullable', 'string', 'max:100'],
        ]);
        $attributes = $data['attributes'];

        $worker = $this->resets->redeem($attributes['cardNumber'], $attributes['resetCode']);
        $pair = $tokens->issue($worker, isset($attributes['deviceName']) ? $attributes['deviceName'] : null);

        return JsonApiResponse::make(['data' => [
            'type' => 'tokens',
            'id' => (string) $pair['model']->id,
            'attributes' => [
                'accessToken' => $pair['accessToken'],
                'refreshToken' => $pair['refreshToken'],
                'tokenType' => 'Bearer',
                'expiresIn' => $pair['expiresIn'],
                'refreshExpiresIn' => $pair['refreshExpiresIn'],
                'mustChangePassword' => true,
            ],
            'relationships' => ['worker' => ['data' => ['type' => 'workers', 'id' => (string) $worker->id]]],
        ]], 201);
    }

    /**
     * Administrador: solicitudes (abiertas por defecto).
     */
    public function index(Request $request)
    {
        $this->ensureAdmin($request);
        $parameters = QueryParameters::fromRequest($request, ['createdAt' => 'created_at'], ['status'], ['worker'], '-createdAt');
        $this->resets->expireOld();
        $status = $parameters->filter('status', 'pending,sent');

        $paginator = $parameters->applySort(PasswordReset::whereIn('status', explode(',', $status)), ['createdAt' => 'created_at'])
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator, $parameters->includes()));
    }

    /**
     * Administrador: marcar como enviado o cancelar.
     */
    public function update(Request $request, $id)
    {
        $this->ensureAdmin($request);
        $reset = PasswordReset::findOrFail($id);
        $data = $this->validateResource($request, 'password-resets', ['attributes.status' => ['required', 'in:sent,cancelled']]);

        if ($data['attributes']['status'] === PasswordReset::STATUS_SENT) {
            $this->resets->markSent($reset, $request->user());
        } elseif ($reset->isOpen()) {
            $reset->close(PasswordReset::STATUS_CANCELLED);
        }

        return JsonApiResponse::make((new Document($request))->resource($reset->fresh()));
    }

    private function ensureAdmin(Request $request): void
    {
        if (! $request->user()->isAdmin()) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'Solo el Administrador gestiona los restablecimientos de contraseña.');
        }
    }
}
