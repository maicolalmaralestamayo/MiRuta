<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Notice;
use Carbon\Carbon;
use Illuminate\Http\Request;

/**
 * Avisos del usuario autenticado.
 */
class NoticeController extends Controller
{
    const SORTABLE = ['createdAt' => 'created_at', 'id' => 'id'];

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, self::SORTABLE, ['unread', 'since'], ['application'], '-createdAt');
        $query = Notice::where('worker_id', $request->user()->id);

        if ($parameters->filter('unread') === 'true') {
            $query->whereNull('read_at');
        }

        if ($since = $parameters->filter('since')) {
            $query->where('created_at', '>', Carbon::parse($since));
        }

        $paginator = $parameters->applySort($query, self::SORTABLE)
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator, $parameters->includes()));
    }

    /**
     * Marcar como leído (o como no leído, con readAt = null).
     */
    public function update(Request $request, $id)
    {
        $notice = Notice::where('worker_id', $request->user()->id)->findOrFail($id);
        $data = $this->validateResource($request, 'notices', ['attributes.readAt' => ['present', 'nullable', 'date']]);

        $notice->read_at = $data['attributes']['readAt'] === null ? null : Carbon::now();
        $notice->save();

        return JsonApiResponse::make((new Document($request))->resource($notice));
    }
}
