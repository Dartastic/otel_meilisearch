// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_meilisearch/otel_meilisearch.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_meilisearch-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};

  test('search records CLIENT span', () async {
    await tracedMeilisearchSearch<String>(
      index: 'movies',
      query: 'dune',
      limit: 10,
      offset: 0,
      invoke: () async => const MeilisearchSearchResult(
        value: 'rows',
        estimatedTotalHits: 42,
        processingTimeMs: 6,
      ),
    );
    final a = attrsOf(spans.findSpanByName('meilisearch search movies')!);
    expect(a['db.system'], 'meilisearch');
    expect(a['db.collection.name'], 'movies');
    expect(a['meilisearch.query'], 'dune');
    expect(a['meilisearch.limit'], 10);
    expect(a['meilisearch.estimated_total_hits'], 42);
    expect(a['meilisearch.processing_time_ms'], 6);
  });

  test('index op records task_uid', () async {
    await tracedMeilisearchIndexOp<int>(
      operation: 'addDocuments',
      index: 'movies',
      documentCount: 1000,
      invoke: () async => 42,
      taskUidOf: (v) => v,
    );
    final a = attrsOf(spans.findSpanByName('meilisearch addDocuments movies')!);
    expect(a['db.operation'], 'addDocuments');
    expect(a['meilisearch.document_count'], 1000);
    expect(a['meilisearch.task_uid'], 42);
  });

  test('suppression skips spans', () async {
    await runWithoutMeilisearchInstrumentationAsync(() async {
      await tracedMeilisearchSearch<String>(
        index: 'm',
        query: 'q',
        invoke: () async => const MeilisearchSearchResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('meilisearch '), isEmpty);
  });
}
