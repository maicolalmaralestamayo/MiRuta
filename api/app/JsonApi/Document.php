<?php

namespace App\JsonApi;

use App\Serializers\Serializer;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;
use Illuminate\Pagination\LengthAwarePaginator;
use InvalidArgumentException;

/**
 * Construye documentos JSON:API (data, included, links, meta) a partir de modelos.
 */
class Document
{
    /** @var Request */
    private $request;

    /** @var array [clase del modelo => clase del serializador] */
    private $serializers;

    /** @var array ["tipo:id" => recurso] */
    private $included = [];

    public function __construct(Request $request)
    {
        $this->request = $request;
        $this->serializers = config('jsonapi.serializers', []);
    }

    /**
     * Documento con un único recurso.
     *
     * @param string[] $includes rutas de relaciones a incluir
     */
    public function resource(Model $model, array $includes = []): array
    {
        $document = [
            'data' => $this->resourceObject($model),
            'links' => ['self' => $this->request->fullUrl()],
        ];

        $this->collectIncluded($model, $includes);

        return $this->withIncluded($document);
    }

    /**
     * Documento con una colección paginada.
     *
     * @param string[] $includes
     */
    public function collection(LengthAwarePaginator $paginator, array $includes = []): array
    {
        $data = [];

        foreach ($paginator->items() as $model) {
            $data[] = $this->resourceObject($model);
            $this->collectIncluded($model, $includes);
        }

        return $this->withIncluded([
            'data' => $data,
            'links' => $this->paginationLinks($paginator),
            'meta' => [
                'total' => $paginator->total(),
                'page' => $paginator->currentPage(),
                'size' => $paginator->perPage(),
            ],
        ]);
    }

    private function resourceObject(Model $model): array
    {
        $serializer = $this->serializerFor($model);

        $resource = [
            'type' => $serializer->type(),
            'id' => (string) $model->getKey(),
            'attributes' => $serializer->attributes($model, $this->request),
        ];

        $relationships = [];

        foreach ($serializer->toOneRelationships() as $name => list($type, $foreignKey)) {
            $id = $model->getAttribute($foreignKey);
            $relationships[$name] = [
                'data' => $id === null ? null : ['type' => $type, 'id' => (string) $id],
            ];
        }

        if ($relationships) {
            $resource['relationships'] = $relationships;
        }

        $meta = $serializer->meta($model, $this->request);

        if ($meta) {
            $resource['meta'] = $meta;
        }

        $resource['links'] = ['self' => $serializer->selfLink($model)];

        return $resource;
    }

    /**
     * Recorre las rutas de include (admite rutas con puntos) y añade los
     * recursos relacionados a "included", sin repetir.
     */
    private function collectIncluded(Model $model, array $includes): void
    {
        foreach ($includes as $path) {
            $this->includePath($model, explode('.', $path));
        }
    }

    private function includePath(Model $model, array $segments): void
    {
        $name = array_shift($segments);
        $relationships = $this->serializerFor($model)->toOneRelationships();

        if (! isset($relationships[$name])) {
            return;
        }

        $method = $relationships[$name][2];
        $related = $model->{$method};

        if (! $related instanceof Model) {
            return;
        }

        $key = $this->serializerFor($related)->type().':'.$related->getKey();

        if (! isset($this->included[$key])) {
            $this->included[$key] = $this->resourceObject($related);
        }

        if ($segments) {
            $this->includePath($related, $segments);
        }
    }

    private function withIncluded(array $document): array
    {
        if ($this->included) {
            $document['included'] = array_values($this->included);
        }

        return $document;
    }

    private function paginationLinks(LengthAwarePaginator $paginator): array
    {
        $page = function ($number) use ($paginator) {
            $query = $this->request->query();
            $query['page'] = ['number' => $number, 'size' => $paginator->perPage()];

            return $this->request->url().'?'.http_build_query($query);
        };

        $last = max(1, $paginator->lastPage());
        $current = $paginator->currentPage();

        return [
            'self' => $page($current),
            'first' => $page(1),
            'prev' => $current > 1 ? $page($current - 1) : null,
            'next' => $current < $last ? $page($current + 1) : null,
            'last' => $page($last),
        ];
    }

    private function serializerFor(Model $model): Serializer
    {
        $class = get_class($model);

        if (! isset($this->serializers[$class])) {
            throw new InvalidArgumentException("No hay serializador JSON:API para {$class}.");
        }

        return app($this->serializers[$class]);
    }
}
