<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Child;
use App\Models\ChildParent;
use App\Models\User;
use App\Services\Access;
use App\Services\ChildEligibility;
use App\Services\Children;
use App\Services\Settings;
use App\Services\Uploads;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

/**
 * Hijos (docs/11 §11.11 y §11.50): los padres los añaden, corrigen, desactivan
 * y quitan directamente. El Administrador ve y gestiona todos.
 */
class ChildController extends Controller
{
    public const SORTABLE = ['firstName' => 'first_name', 'firstSurname' => 'first_surname', 'id' => 'id'];

    public function __construct(private Children $children, private Access $access)
    {
    }

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, self::SORTABLE, ['parent', 'active', 'eligible'], [], 'firstName,firstSurname');
        $query = $this->visible($request->user());

        if ($parent = $parameters->filter('parent')) {
            $query->ofParent((int) $parent);
        }

        if ($parameters->filter('active') !== null) {
            $query->where('active', $parameters->filter('active') === 'true');
        }

        if ($parameters->filter('eligible') !== null) {
            $wanted = $parameters->filter('eligible') === 'true';
            $eligibility = app(ChildEligibility::class);
            $ids = (clone $query)->get()->filter(fn (Child $child) => $eligibility->isEligible($child->birth_date) === $wanted)->pluck('id')->all();
            $query = Child::whereIn('id', $ids ?: [0]);
        }

        return $this->paginate($request, $query, $parameters, self::SORTABLE);
    }

    public function show(Request $request, $id)
    {
        return $this->respond($request, $this->visible($request->user())->findOrFail($id));
    }

    /**
     * Añade un hijo: nombres, sexo (por omisión Masculino) y fecha de
     * nacimiento (docs/11 §11.67, sin carné). Si ya lo tiene declarado otra
     * persona (mismos nombres y fecha de nacimiento), se le vincula igualmente
     * y meta.alreadyDeclared = true.
     */
    public function store(Request $request)
    {
        $data = $this->validateResource($request, 'children', UserController::nameRules() + [
            'attributes.sex' => ['sometimes', 'in:F,M'],
            'attributes.birthDate' => ['required', 'date_format:Y-m-d', 'before_or_equal:today'],
        ] + $this->relationshipRules('parent', 'users', 'users', false));
        $user = $request->user();
        $parentId = $this->relationshipId($data, 'parent') ?? (int) $user->id;

        if ($parentId !== (int) $user->id) {
            $this->access->requireAdmin($user, 'Solo puede añadir sus propios hijos.');
        }

        [$child, $alreadyDeclared] = $this->children->add(User::findOrFail($parentId), UserController::names($data['attributes'])
            + ['sex' => $data['attributes']['sex'] ?? 'M', 'birth_date' => $data['attributes']['birthDate']]);
        $document = (new Document($request))->resource($child);
        $document['meta'] = ['alreadyDeclared' => $alreadyDeclared]
            + ($alreadyDeclared ? ['notice' => 'Ese niño ya está declarado por otra persona. Se le asignó también a usted.'] : []);

        return JsonApiResponse::make($document, 201, ['Location' => url('api/v1/children/'.$child->id)]);
    }

    public function update(Request $request, $id)
    {
        $child = $this->manageable($request, $id);
        $data = $this->validateResource($request, 'children', UserController::nameRules('attributes.', false) + [
            'attributes.sex' => ['sometimes', 'in:F,M'],
            'attributes.birthDate' => ['sometimes', 'required', 'date_format:Y-m-d', 'before_or_equal:today'],
            'attributes.active' => ['sometimes', 'boolean'],
        ]);
        $attributes = $data['attributes'] ?? [];
        $person = array_filter(UserController::person($attributes), fn ($v) => $v !== null);
        $child = $this->children->update($child, UserController::names($attributes) + $person,
            array_key_exists('active', $attributes) ? (bool) $attributes['active'] : null);

        return $this->respond($request, $child);
    }

    /**
     * Eliminar = desvincular de quien lo pide (el Administrador lo borra del todo).
     */
    public function destroy(Request $request, $id)
    {
        $child = $this->manageable($request, $id);
        $user = $request->user();

        if ($this->children->isParent($child, $user)) {
            $this->children->unlink($child, (int) $user->id);
        } else {
            $child->delete();
        }

        return $this->noContent();
    }

    public function uploadPhoto(Request $request, Settings $settings, Uploads $uploads, $id)
    {
        $child = $this->manageable($request, $id);
        $this->validateRequest($request, [
            'photo' => ['required', 'file', 'image', 'mimes:jpeg,png', 'max:'.$settings->int('tamano_foto')],
        ]);
        $previous = $child->photo_path;
        $child->photo_path = $uploads->store($request->file('photo'), 'children');
        $child->save();
        $uploads->delete($previous);

        return $this->respond($request, $child->fresh());
    }

    public function deletePhoto(Request $request, Uploads $uploads, $id)
    {
        $child = $this->manageable($request, $id);
        $uploads->delete($child->photo_path);
        $child->photo_path = null;
        $child->save();

        return $this->noContent();
    }

    private function manageable(Request $request, $id): Child
    {
        $child = Child::findOrFail($id);
        $user = $request->user();

        if (! $this->children->isParent($child, $user) && ! $this->access->isAdmin($user)) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'Ese niño no está entre sus hijos.');
        }

        return $child;
    }

    /**
     * Los suyos; el Administrador, todos; el Jefe, también los de las personas de su itinerario.
     */
    private function visible(User $user): Builder
    {
        $query = Child::query();

        if ($this->access->isAdmin($user)) {
            return $query;
        }

        $chiefOf = $this->access->chiefItineraryId($user);
        $parents = \App\Models\WorkerItinerary::where('itinerary_id', $chiefOf ?? 0)->select('user_id');

        return $query->whereIn('id', ChildParent::where('user_id', $user->id)
            ->when($chiefOf !== null, fn ($q) => $q->orWhereIn('user_id', $parents))->select('child_id'));
    }
}
