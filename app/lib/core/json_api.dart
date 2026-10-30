/// Documentos JSON:API: recursos, relaciones, recursos incluidos y errores.
library;

/// Identificador de un recurso (`type` + `id`).
class ResourceId {
  final String type;
  final String id;

  const ResourceId(this.type, this.id);

  Map<String, dynamic> toJson() => {'type': type, 'id': id};

  @override
  bool operator ==(Object other) => other is ResourceId && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);
}

/// Objeto de recurso de JSON:API.
class Resource {
  final String type;
  final String id;
  final Map<String, dynamic> attributes;
  final Map<String, dynamic> relationships;
  final Map<String, dynamic> meta;

  /// Documento del que viene (para resolver relaciones incluidas).
  final JsonApiDocument? document;

  Resource({
    required this.type,
    required this.id,
    this.attributes = const {},
    this.relationships = const {},
    this.meta = const {},
    this.document,
  });

  factory Resource.fromJson(Map<String, dynamic> json, [JsonApiDocument? document]) => Resource(
        type: json['type'] as String,
        id: (json['id'] ?? '').toString(),
        attributes: Map<String, dynamic>.from(json['attributes'] as Map? ?? const {}),
        relationships: Map<String, dynamic>.from(json['relationships'] as Map? ?? const {}),
        meta: Map<String, dynamic>.from(json['meta'] as Map? ?? const {}),
        document: document,
      );

  T? attr<T>(String name) => attributes[name] as T?;

  String? string(String name) => attributes[name]?.toString();

  int? integer(String name) {
    final value = attributes[name];
    return value is int ? value : (value is num ? value.toInt() : int.tryParse('${value ?? ''}'));
  }

  bool boolean(String name) => attributes[name] == true;

  DateTime? date(String name) {
    final value = attributes[name];
    return value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
  }

  /// Identificador de una relación a uno.
  ResourceId? relId(String name) {
    final data = (relationships[name] as Map?)?['data'];
    if (data is Map && data['type'] != null && data['id'] != null) {
      return ResourceId(data['type'] as String, data['id'].toString());
    }
    return null;
  }

  /// Recurso incluido de una relación a uno, si vino en "included".
  Resource? related(String name) {
    final id = relId(name);
    return id == null ? null : document?.find(id);
  }
}

/// Error de JSON:API.
class JsonApiError {
  final String status;
  final String code;
  final String title;
  final String? detail;
  final String? pointer;
  final String? parameter;
  final Map<String, dynamic> meta;

  JsonApiError({
    required this.status,
    required this.code,
    required this.title,
    this.detail,
    this.pointer,
    this.parameter,
    this.meta = const {},
  });

  factory JsonApiError.fromJson(Map<String, dynamic> json) {
    final source = Map<String, dynamic>.from(json['source'] as Map? ?? const {});
    return JsonApiError(
      status: '${json['status'] ?? ''}',
      code: '${json['code'] ?? 'ERROR'}',
      title: '${json['title'] ?? 'Error'}',
      detail: json['detail'] as String?,
      pointer: source['pointer'] as String?,
      parameter: source['parameter'] as String?,
      meta: Map<String, dynamic>.from(json['meta'] as Map? ?? const {}),
    );
  }

  String get message => detail ?? title;
}

/// Documento JSON:API de respuesta.
class JsonApiDocument {
  final dynamic _data;
  final Map<String, dynamic> meta;
  final Map<String, dynamic> links;
  final Map<ResourceId, Resource> _included = {};
  late final List<Resource> resources;

  JsonApiDocument.fromJson(Map<String, dynamic> json)
      : _data = json['data'],
        meta = Map<String, dynamic>.from(json['meta'] as Map? ?? const {}),
        links = Map<String, dynamic>.from(json['links'] as Map? ?? const {}) {
    for (final item in (json['included'] as List? ?? const [])) {
      final resource = Resource.fromJson(Map<String, dynamic>.from(item as Map), this);
      _included[ResourceId(resource.type, resource.id)] = resource;
    }
    if (_data is List) {
      resources = _data.map((item) => Resource.fromJson(Map<String, dynamic>.from(item as Map), this)).toList();
    } else if (_data is Map) {
      resources = [Resource.fromJson(Map<String, dynamic>.from(_data), this)];
    } else {
      resources = const [];
    }
  }

  /// El recurso principal de un documento con un único recurso.
  Resource get resource => resources.first;

  Resource? find(ResourceId id) {
    for (final resource in resources) {
      if (resource.type == id.type && resource.id == id.id) return resource;
    }
    return _included[id];
  }

  Iterable<Resource> included(String type) => _included.values.where((resource) => resource.type == type);

  bool get hasNext => links['next'] != null;

  int get total => (meta['total'] as num?)?.toInt() ?? resources.length;
}

/// Construye el objeto "data" de un documento de entrada.
Map<String, dynamic> resourceData(
  String type, {
  String? id,
  Map<String, dynamic>? attributes,
  Map<String, ResourceId?>? relationships,
}) {
  return {
    'data': {
      'type': type,
      'id': ?id,
      'attributes': ?attributes,
      if (relationships != null)
        'relationships': {
          for (final entry in relationships.entries) entry.key: {'data': entry.value?.toJson()},
        },
    },
  };
}
