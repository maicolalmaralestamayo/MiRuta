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
 * «Olvidé algo» (docs/11 §11.7): carné y teléfono.
 *
 * - La instalación (sin sesión) la crea y la consulta: una vez aprobada ve
 *   solo lo que pidió (usuario, contraseña propuesta o ambos) y la
 *   solicitud se da por terminada. Al entrar, debe cambiar la contraseña.
 * - Quien tiene access_recoveries.manage (el Administrador) las lista y las
 *   aprueba o rechaza; al aprobar ve también lo que hay que comunicar.
 */
class AccessRecoveryController extends Controller
{
    const INCLUDABLE = ['user', 'installation'];

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
            'attributes.identityCard' => ['required', 'string', 'max:20'],
            'attributes.phone' => ['required', 'string', 'regex:/^\+?[0-9 ()\-]{7,20}$/'],
        ]);
        $attributes = $data['attributes'];

        $recovery = $this->recoveries->request(
            $request->attributes->get('installation'),
            (bool) $attributes['forgotUsername'],
            (bool) $attributes['forgotPassword'],
            $attributes['identityCard'],
            trim($attributes['phone'])
        );

        return JsonApiResponse::make((new Document($request))->resource($recovery), 201);
    }

    /**
     * La instalación consulta la suya (cuando se aprobó, trae el usuario si lo olvidó).
     */
    public function showForInstallation(Request $request, $id)
    {
        $recovery = $this->recoveries->readByInstallation($this->ownOrFail($request, $id));
        $document = (new Document($request))->resource($recovery);
        $this->recoveries->completeAfterReading($recovery);

        return JsonApiResponse::make($document);
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
        app(\App\Services\Permissions::class)->authorize($request->user(), 'access_recoveries.manage');
    }
}
