<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\Models\Role;
use App\Serializers\RoleSerializer;
use App\Services\Permissions;
use App\Services\Roles;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Roles configurables (docs/11 §11.16). Los consulta cualquiera con sesión
 * (para solicitarlos); el Administrador aparece como rol fijo de solo
 * lectura (id "admin"). Crear, editar y eliminar: roles.manage.
 *
 * Atributos: name, icon, requestable, isDefault, itineraryScoped,
 * permissions [{operation, scope}], approverRoleIds [id].
 */
class RoleController extends Controller
{
    /** @var Roles */
    private $roles;

    public function __construct(Roles $roles)
    {
        $this->roles = $roles;
    }

    public function index(Request $request)
    {
        $document = (new Document($request))->list(Role::orderBy('name')->get());
        array_unshift($document['data'], RoleSerializer::administrator());

        return JsonApiResponse::make($document);
    }

    public function show(Request $request, $id)
    {
        if ($id === RoleSerializer::ADMIN_ID) {
            return JsonApiResponse::make(['data' => RoleSerializer::administrator()]);
        }

        return JsonApiResponse::make((new Document($request))->resource(Role::findOrFail($id)));
    }

    public function store(Request $request)
    {
        app(Permissions::class)->authorize($request->user(), 'roles.manage');
        $data = $this->validateResource($request, 'roles', $this->rules(null));
        $role = $this->roles->save($request->user(), null, $data['attributes']);

        return JsonApiResponse::make((new Document($request))->resource($role), 201, ['Location' => url('api/v1/roles/'.$role->id)]);
    }

    public function update(Request $request, $id)
    {
        $this->ensureNotAdministrator($id);
        $role = Role::findOrFail($id);
        $permissions = app(Permissions::class);
        $onlyDefault = array_keys((array) $request->json('data.attributes', [])) === ['isDefault'];

        if (! $onlyDefault || ! $permissions->can($request->user(), 'roles.set_default')) {
            $permissions->authorize($request->user(), 'roles.manage');
        }

        $data = $this->validateResource($request, 'roles', $this->rules($role));

        if (isset($data['id']) && (string) $data['id'] !== (string) $role->id) {
            throw JsonApiException::conflict('ID_MISMATCH', 'El id del documento no coincide con el de la URL.', '/data/id');
        }

        $role = $this->roles->save($request->user(), $role, isset($data['attributes']) ? $data['attributes'] : []);

        return JsonApiResponse::make((new Document($request))->resource($role));
    }

    public function destroy(Request $request, $id)
    {
        $this->ensureNotAdministrator($id);
        app(Permissions::class)->authorize($request->user(), 'roles.manage');
        $this->roles->delete($request->user(), Role::findOrFail($id));

        return response('', 204);
    }

    private function rules(?Role $role): array
    {
        $presence = $role ? 'sometimes' : 'required';

        return [
            'attributes.name' => [$presence, 'string', 'max:100', 'regex:/\S/',
                Rule::unique('roles', 'name')->whereNull('deleted_at')->ignore($role ? $role->id : null)],
            'attributes.icon' => ['sometimes', 'nullable', 'string', 'max:100'],
            'attributes.requestable' => ['sometimes', 'boolean'],
            'attributes.isDefault' => ['sometimes', 'boolean'],
            'attributes.itineraryScoped' => ['sometimes', 'boolean'],
            'attributes.permissions' => ['sometimes', 'array'],
            'attributes.approverRoleIds' => ['sometimes', 'array'],
        ];
    }

    private function ensureNotAdministrator($id): void
    {
        if ($id === RoleSerializer::ADMIN_ID) {
            throw new JsonApiException(403, 'ROLE_NOT_EDITABLE', 'Rol fijo', 'El Administrador es un rol fijo: no se puede editar ni eliminar.');
        }
    }
}
