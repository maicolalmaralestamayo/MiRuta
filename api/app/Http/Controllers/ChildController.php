<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Child;
use App\Models\ChildParent;
use App\Models\User;
use App\Models\Worker;
use App\Services\ChildEligibility;
use App\Services\Children;
use App\Services\Permissions;
use App\Services\Settings;
use App\Services\Uploads;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

/**
 * Hijos (docs/11 §11.11). Los padres los añaden (por carné; si ya existe se
 * les vincula, con aviso), corrigen, desactivan, reactivan y quitan
 * directamente. Con children.manage «all» se gestionan los de cualquiera;
 * con children.view, se consultan los de su ámbito.
 */
class ChildController extends Controller
{
    const SORTABLE = ['firstName' => 'first_name', 'firstSurname' => 'first_surname', 'secondSurname' => 'second_surname', 'id' => 'id'];

    /** @var Children */
    private $children;

    /** @var Permissions */
    private $permissions;

    public function __construct(Children $children, Permissions $permissions)
    {
        $this->children = $children;
        $this->permissions = $permissions;
    }

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, self::SORTABLE, ['parent', 'active', 'eligible', 'entity', 'itinerary'], [], 'firstSurname,secondSurname,firstName');
        $query = $this->visible($request);

        if ($parent = $parameters->filter('parent')) {
            $query->ofParent((int) $parent);
        }

        if ($parameters->filter('active') !== null) {
            $query->where('active', $parameters->filter('active') === 'true');
        }

        foreach (['entity' => 'entity_id', 'itinerary' => 'itinerary_id'] as $filter => $column) {
            if ($value = $parameters->filter($filter)) {
                $query->whereIn('children.id', ChildParent::whereIn('user_id', Worker::where($column, $value)->select('user_id'))->select('child_id'));
            }
        }

        if ($parameters->filter('eligible') !== null) {
            $wanted = $parameters->filter('eligible') === 'true';
            $eligibility = app(ChildEligibility::class);
            $ids = $query->get()->filter(function (Child $child) use ($eligibility, $wanted) {
                return $eligibility->isChildEligible($child) === $wanted;
            })->pluck('id')->all();
            $query = Child::whereIn('id', $ids ?: [0]);
        }

        $paginator = $parameters->applySort($query, self::SORTABLE)
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator));
    }

    public function show(Request $request, $id)
    {
        return JsonApiResponse::make((new Document($request))->resource($this->visible($request)->findOrFail($id)));
    }

    /**
     * Añade un hijo por su carné. Si ya lo tiene declarado otra persona, se le
     * vincula igualmente y meta.alreadyDeclared = true.
     */
    public function store(Request $request)
    {
        $data = $this->validateResource($request, 'children', UserController::nameRules() + [
            'attributes.identityCard' => ['required', 'string', 'max:20'],
            'relationships.parent.data.type' => ['sometimes', 'in:users'],
            'relationships.parent.data.id' => ['sometimes', 'exists:users,id,deleted_at,NULL'],
        ]);
        $user = $request->user();
        $parentId = isset($data['relationships']['parent']['data']['id']) ? (int) $data['relationships']['parent']['data']['id'] : (int) $user->id;

        if ($parentId !== (int) $user->id) {
            $this->permissions->authorize($user, 'children.manage', null, null, 'Solo puede añadir sus propios hijos.');
        }

        list($child, $alreadyDeclared) = $this->children->add(User::findOrFail($parentId), UserController::names($data['attributes']), $data['attributes']['identityCard']);
        $document = (new Document($request))->resource($child);
        $document['data']['meta'] = array_merge(isset($document['data']['meta']) ? $document['data']['meta'] : [], [
            'alreadyDeclared' => $alreadyDeclared,
        ]);

        if ($alreadyDeclared) {
            $document['meta'] = ['notice' => 'Ese niño ya está declarado por otra persona. Se le asignó también a usted.'];
        }

        return JsonApiResponse::make($document, 201, ['Location' => url('api/v1/children/'.$child->id)]);
    }

    /**
     * Nombres, carné y active (desactivar o reactivar).
     */
    public function update(Request $request, $id)
    {
        $child = $this->manageable($request, $id);
        $data = $this->validateResource($request, 'children', UserController::nameRules('attributes.', false) + [
            'attributes.identityCard' => ['sometimes', 'required', 'string', 'max:20'],
            'attributes.active' => ['sometimes', 'boolean'],
        ]);
        $attributes = isset($data['attributes']) ? $data['attributes'] : [];

        $child = $this->children->update(
            $child,
            UserController::names($attributes),
            isset($attributes['identityCard']) ? $attributes['identityCard'] : null,
            array_key_exists('active', $attributes) ? (bool) $attributes['active'] : null
        );

        return JsonApiResponse::make((new Document($request))->resource($child));
    }

    /**
     * Eliminar = desvincular de su padre o madre (filter[parent] para otro,
     * con children.manage «all»). Sin padres, se borra.
     */
    public function destroy(Request $request, $id)
    {
        $child = $this->manageable($request, $id);
        $user = $request->user();
        $parentId = $request->input('filter.parent');

        if ($parentId === null) {
            $parentId = $this->children->isParent($child, $user) ? (int) $user->id : null;
        }

        if ($parentId === null) {
            foreach ($child->parentIds() as $id) {
                $this->children->unlink($child, $id);
            }
        } else {
            $this->children->unlink($child, (int) $parentId);
        }

        return response('', 204);
    }

    public function uploadPhoto(Request $request, Settings $settings, Uploads $uploads, $id)
    {
        $child = $this->manageable($request, $id);
        $this->validate($request, [
            'photo' => ['required', 'file', 'image', 'mimes:jpeg,png', 'max:'.$settings->int('photo_max_kb')],
        ]);

        $previous = $child->photo_path;
        $child->photo_path = $uploads->store($request->file('photo'), 'children');
        $child->save();
        $uploads->delete($previous);

        return JsonApiResponse::make((new Document($request))->resource($child));
    }

    public function deletePhoto(Request $request, Uploads $uploads, $id)
    {
        $child = $this->manageable($request, $id);
        $uploads->delete($child->photo_path);
        $child->photo_path = null;
        $child->save();

        return response('', 204);
    }

    /**
     * Sus hijos, o cualquiera con children.manage «all».
     */
    private function manageable(Request $request, $id): Child
    {
        $child = Child::findOrFail($id);
        $user = $request->user();

        if (! $this->children->isParent($child, $user) && ! $this->permissions->can($user, 'children.manage')) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'Ese niño no está entre sus hijos.');
        }

        return $child;
    }

    /**
     * Los suyos y los de los padres de su ámbito de children.view.
     */
    private function visible(Request $request): Builder
    {
        $user = $request->user();
        $query = Child::query();
        $scope = $this->permissions->scope($user, 'children.view');

        if ($scope['all'] || $this->permissions->can($user, 'children.manage')) {
            return $query;
        }

        $parents = Worker::query()->select('user_id')->where(function ($query) use ($scope) {
            $query->whereIn('entity_id', $scope['entities'] ?: [0])->orWhereIn('itinerary_id', $scope['itineraries'] ?: [0]);
        });

        return $query->where(function (Builder $query) use ($user, $parents) {
            $query->whereIn('children.id', ChildParent::where('user_id', $user->id)->select('child_id'))
                ->orWhereIn('children.id', ChildParent::whereIn('user_id', $parents)->select('child_id'));
        });
    }
}
