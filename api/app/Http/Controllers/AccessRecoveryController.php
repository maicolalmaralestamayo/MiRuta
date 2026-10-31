<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\AccessRecovery;
use App\Services\AccessRecoveries;
use App\Services\TokenService;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Http\Request;

/**
 * "No puedo entrar" (docs/08-version-2.md §8.6).
 *
 * - La instalación (sin sesión) la crea, la consulta y, si se aprobó y
 *   olvidó la contraseña, elige una nueva.
 * - El Administrador las lista y las aprueba o rechaza.
 */
class AccessRecoveryController extends Controller
{
    const INCLUDABLE = ['worker', 'worker.user', 'worker.entity', 'worker.itinerary', 'installation'];

    /** @var AccessRecoveries */
    private $recoveries;

    public function __construct(AccessRecoveries $recoveries)
    {
        $this->recoveries = $recoveries;
    }

    public function store(Request $request)
    {
        $data = $this->validateResource($request, 'access-recoveries', [
            'attributes.forgotUsername' => ['required', 'boolean'],
            'attributes.forgotPassword' => ['required', 'boolean'],
            'attributes.entityAbbreviation' => ['required', 'string', 'max:15'],
            'attributes.pass' => ['required', 'integer', 'min:1', 'max:4294967295'],
            'attributes.phone' => ['required', 'string', 'regex:/^\+?[0-9 ()\-]{7,20}$/'],
        ]);
        $attributes = $data['attributes'];

        $recovery = $this->recoveries->request(
            $request->attributes->get('installation'),
            (bool) $attributes['forgotUsername'],
            (bool) $attributes['forgotPassword'],
            $attributes['entityAbbreviation'],
            (int) $attributes['pass'],
            trim($attributes['phone'])
        );

        return JsonApiResponse::make((new Document($request))->resource($recovery), 201);
    }

    /**
     * La instalación consulta la suya (cuando se aprobó, trae el usuario si lo olvidó).
     */
    public function showForInstallation(Request $request, $id)
    {
        $recovery = $this->ownOrFail($request, $id);

        return JsonApiResponse::make((new Document($request))->resource($this->recoveries->readByInstallation($recovery)));
    }

    /**
     * Contraseña nueva tras la aprobación. Devuelve tokens para entrar.
     */
    public function setPassword(Request $request, TokenService $tokens, $id)
    {
        $recovery = $this->ownOrFail($request, $id);
        $data = $this->validateResource($request, 'access-recoveries', [
            'attributes.password' => ['required', 'string'],
            'attributes.deviceName' => ['nullable', 'string', 'max:100'],
        ]);

        $user = $this->recoveries->setPassword($recovery, $data['attributes']['password']);
        TokenController::linkInstallation($recovery->installation, $user);

        return TokenController::respond($tokens->issue($user, isset($data['attributes']['deviceName']) ? $data['attributes']['deviceName'] : null));
    }

    /**
     * Solo el Administrador. Por defecto, las pendientes y aprobadas.
     */
    public function index(Request $request)
    {
        $this->ensureAdmin($request);
        $parameters = QueryParameters::fromRequest($request, ['createdAt' => 'created_at', 'id' => 'id'], ['status'], self::INCLUDABLE, '-createdAt');
        $statuses = $parameters->filter('status') ? explode(',', $parameters->filter('status')) : [AccessRecovery::STATUS_PENDING, AccessRecovery::STATUS_APPROVED];

        $this->recoveries->expireOld();
        $query = AccessRecovery::whereIn('status', $statuses);
        $paginator = $parameters->applySort($query, ['createdAt' => 'created_at', 'id' => 'id'])
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator, $parameters->includes()));
    }

    public function show(Request $request, $id)
    {
        $this->ensureAdmin($request);

        return JsonApiResponse::make((new Document($request))->resource(AccessRecovery::findOrFail($id), QueryParameters::readIncludes($request, self::INCLUDABLE)));
    }

    /**
     * Solo el Administrador: attributes.status = approved o rejected.
     */
    public function update(Request $request, $id)
    {
        $this->ensureAdmin($request);
        $recovery = AccessRecovery::findOrFail($id);
        $data = $this->validateResource($request, 'access-recoveries', [
            'attributes.status' => ['required', 'in:approved,rejected'],
        ]);

        $recovery = $data['attributes']['status'] === 'approved'
            ? $this->recoveries->approve($recovery, $request->user())
            : $this->recoveries->reject($recovery, $request->user());

        return JsonApiResponse::make((new Document($request))->resource($recovery->fresh()));
    }

    private function ownOrFail(Request $request, $id): AccessRecovery
    {
        $recovery = AccessRecovery::find($id);

        if (! $recovery || (int) $recovery->installation_id !== (int) $request->attributes->get('installation')->id) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'La solicitud no existe.');
        }

        return $recovery;
    }

    private function ensureAdmin(Request $request): void
    {
        if (! $request->user()->isAdmin()) {
            throw new AuthorizationException();
        }
    }
}
