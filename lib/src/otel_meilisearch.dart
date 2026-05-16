// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

import 'otel_meilisearch_suppression.dart';

const _tracerName = 'dartastic_otel_libs_meilisearch';
const _systemValue = 'meilisearch';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

/// Pair returned from `tracedMeilisearchSearch` callback.
class MeilisearchSearchResult<T> {
  const MeilisearchSearchResult({
    required this.value,
    this.estimatedTotalHits,
    this.processingTimeMs,
  });
  final T value;
  final int? estimatedTotalHits;
  final int? processingTimeMs;
}

/// Wraps a Meilisearch `search` request in a CLIENT span.
Future<T> tracedMeilisearchSearch<T>({
  required String index,
  required String query,
  required Future<MeilisearchSearchResult<T>> Function() invoke,
  int? limit,
  int? offset,
}) async {
  if (meilisearchInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final m = <String, Object>{
    'db.system': _systemValue,
    'db.operation': 'search',
    'db.collection.name': index,
    'meilisearch.index': index,
    'meilisearch.query': query,
  };
  if (limit != null) m['meilisearch.limit'] = limit;
  if (offset != null) m['meilisearch.offset'] = offset;

  final span = _tracer().startSpan(
    'meilisearch search $index',
    kind: SpanKind.client,
    attributes: OTel.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    final extras = <Attribute<Object>>[];
    if (r.estimatedTotalHits != null) {
      extras.add(OTel.attributeInt(
        'meilisearch.estimated_total_hits',
        r.estimatedTotalHits!,
      ));
    }
    if (r.processingTimeMs != null) {
      extras.add(OTel.attributeInt(
        'meilisearch.processing_time_ms',
        r.processingTimeMs!,
      ));
    }
    if (extras.isNotEmpty) span.addAttributes(OTel.attributes(extras));
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}

/// Wraps a Meilisearch index operation (addDocuments/updateDocuments
/// /deleteDocuments) in a CLIENT span. Records the task uid the
/// server returns so async tasks can be correlated later.
Future<T> tracedMeilisearchIndexOp<T>({
  required String operation,
  required String index,
  required Future<T> Function() invoke,
  int? documentCount,
  int Function(T value)? taskUidOf,
}) async {
  if (meilisearchInstrumentationSuppressed()) {
    return invoke();
  }
  final m = <String, Object>{
    'db.system': _systemValue,
    'db.operation': operation,
    'db.collection.name': index,
    'meilisearch.index': index,
  };
  if (documentCount != null) {
    m['meilisearch.document_count'] = documentCount;
  }

  final span = _tracer().startSpan(
    'meilisearch $operation $index',
    kind: SpanKind.client,
    attributes: OTel.attributesFromMap(m),
  );
  try {
    final v = await invoke();
    if (taskUidOf != null) {
      span.addAttributes(OTel.attributes([
        OTel.attributeInt('meilisearch.task_uid', taskUidOf(v)),
      ]));
    }
    return v;
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}
