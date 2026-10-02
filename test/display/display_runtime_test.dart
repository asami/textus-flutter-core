import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('projection and receipt lifecycle', () {
    test('DS01 initial query is reactive and never reads Detail', () async {
      // Given a new fixed-flow session and a gated collection reply.
      final ports = RecordingPorts();
      final gate = PortGate();
      ports.displayHandler = (request) async {
        gate.entered.complete();
        await gate.release.future;
        return ports.reply(request);
      };
      final session = makeSession(ports);
      final snapshots = <DisplaySessionState>[];
      session.addListener(() => snapshots.add(session.state));
      // When the consumer queries without constructing any request metadata.
      final pending = session.query();
      await gate.entered.future;
      // Then loading is observable and no eager Detail was requested.
      expect(session.state.busy, isTrue);
      expect(session.state.list.phase, DisplaySessionReadPhase.loading);
      expect(session.state.detail.phase, DisplaySessionReadPhase.idle);
      expect(ports.calls.single.kind, DisplayRequestKind.query);
      expect(ports.calls.single.metadata.observedRevision, isNull);
      expect(ports.calls.single.metadata.context, session.state.context);
      // Given the collection call is pending.
      // When its valid producer reply is released.
      gate.release.complete();
      await pending;
      // Then the ordered typed List is ready without selecting a resource.
      expect(session.state.list.phase, DisplaySessionReadPhase.ready);
      expect(
        session.state.list.data!.model.items.map((row) => row.resourceId),
        ['opaque:first', 'opaque:other'],
      );
      expect(session.state.selectedResourceId, isNull);
      expect(snapshots.first.list.phase, DisplaySessionReadPhase.loading);
      expect(snapshots.last.busy, isFalse);
      session.dispose();
    });

    test('DS02 explicit read admits opaque identity typed values and scoped inputs', () async {
      // Given a collection-ready neutral session.
      final ports = RecordingPorts();
      final session = makeSession(ports);
      await loadList(session);
      // When the opaque resource is explicitly read.
      await session.read('opaque:first');
      // Then the Detail contains typed values, scoped bindings and exact provenance.
      final detail = session.state.detail.data!;
      expect(session.state.selectedResourceId, 'opaque:first');
      expect(
        detail.model.sections.single.fields.map(
          (field) => field.value.runtimeType,
        ),
        [
          TextDisplayValue,
          TextDisplayValue,
          TextDisplayValue,
          NumberDisplayValue,
          BoolDisplayValue,
          TimestampDisplayValue,
          MissingDisplayValue,
        ],
      );
      expect(detail.bindings.first.locator, input('name', 'x').locator);
      expect(
        detail.bindings.first.inputValue,
        const TextDisplayValue('Original'),
      );
      expect(detail.provenance.revision, '1');
      expect(detail.provenance.sourceId, 'source');
      expect(ports.calls.last.metadata.observedRevision, isNull);
      expect(session.state.canMutate, isTrue);
      session.dispose();
    });

    for (final active in [false, true]) {
      test(
        'DS03 ${active ? 'active Detail' : 'no focus'} reload is bounded',
        () async {
          // Given a session with the separately named accepted-focus variant.
          final ports = RecordingPorts();
          final session = makeSession(ports);
          if (active) {
            await loadActive(session);
          } else {
            await loadList(session);
          }
          final before = ports.calls.length;
          // When the consumer explicitly reloads once.
          await session.reload();
          // Then the exact safe call order depends on accepted focus only.
          expect(
            ports.calls.skip(before).map((call) => call.kind),
            active
                ? [DisplayRequestKind.read, DisplayRequestKind.query]
                : [DisplayRequestKind.query],
          );
          expect(
            session.state.selectedResourceId,
            active ? 'opaque:first' : null,
          );
          session.dispose();
        },
      );
    }

    test('DS04 changed receipt is published before gated refresh and duplicate Save fails', () async {
      // Given a coherent session whose first post-command read is gated.
      final ports = RecordingPorts();
      final session = makeSession(ports);
      await loadActive(session);
      final gate = PortGate();
      ports.displayHandler = (request) async {
        if (request.kind == DisplayRequestKind.update) {
          ports.revision = 2;
        }
        if (request.kind == DisplayRequestKind.read) {
          gate.entered.complete();
          await gate.release.future;
        }
        return ports.reply(request);
      };
      // When one changed update reaches the gated safe refresh.
      final pending = session.update(
        observedRevision: 1,
        fields: [input('name', 'Changed')],
      );
      await gate.entered.future;
      // Then receipt and commit floor are visible while busy and projection remain pending.
      expect(session.state.command.phase, DisplaySessionCommandPhase.settled);
      expect(session.state.command.mutation!.committedRevision, 2);
      expect(session.state.committedRevisions['opaque:first'], 2);
      expect(session.state.busy, isTrue);
      expect(session.state.projectionPending, isTrue);
      // Given the same update refresh remains reserved.
      // When another Save is attempted.
      final duplicate = session.update(observedRevision: 1, fields: []);
      // Then it fails before another raw command call.
      await expectLater(duplicate, throwsStateError);
      expect(
        ports.calls.where((call) => call.kind == DisplayRequestKind.update),
        hasLength(1),
      );
      // Given the first receipt already exists.
      // When the pending refresh reply is released.
      gate.release.complete();
      await pending;
      // Then one read and one query complete a coherent projection without replay.
      expect(session.state.canMutate, isTrue);
      expect(ports.calls.map((call) => call.kind), [
        DisplayRequestKind.query,
        DisplayRequestKind.read,
        DisplayRequestKind.update,
        DisplayRequestKind.read,
        DisplayRequestKind.query,
      ]);
      session.dispose();
    });

    test('DS05 semantic changed update refreshes exact bytes and preserves other fields', () async {
      // Given a public semantic source and coherent common session.
      final source = semanticSource();
      final session = sourceSession(source);
      await loadActive(session);
      final previous = source.resources;
      const title = '  改訂\nΩ\u0085　 ';
      // When a valid source update changes one input field.
      await session.update(observedRevision: 1, fields: [input('name', title)]);
      // Then real source and both refreshed projections agree at revision two.
      expect(source.resources.first.sourceRevision, 2);
      expect(
        source.resources.first.fields['name'],
        const TextDisplayValue(title),
      );
      expect(
        source.resources.first.fields['note'],
        previous.first.fields['note'],
      );
      expect(
        source.resources.first.fields['state'],
        previous.first.fields['state'],
      );
      expect(source.resources[1].fields, previous[1].fields);
      expect(session.state.detail.data!.sourceRevision, 2);
      expect(
        valueOf(session.state.detail.data!, 'name'),
        const TextDisplayValue(title),
      );
      expect(session.state.list.data!.model.items.first.sourceRevision, 2);
      expect(
        session.state.list.data!.model.items.first.fields.first.value,
        const TextDisplayValue(title),
      );
      expect(
        session.state.command.mutation!.outcome,
        DisplayCommandOutcome.changed,
      );
      expect(session.state.canMutate, isTrue);
      session.dispose();
    });

    test('DS06 noOp retains exact caller revision and creates no commit', () async {
      // Given a current source resource and unchanged semantic inputs.
      final source = semanticSource();
      final session = sourceSession(source);
      await loadActive(session);
      // When the exact observed revision is submitted with no semantic changes.
      await session.update(observedRevision: 1, fields: []);
      // Then noOp settles at the current floor with one bounded safe refresh.
      expect(
        session.state.command.mutation!.outcome,
        DisplayCommandOutcome.noOp,
      );
      expect(session.state.command.mutation!.currentRevision, 1);
      expect(session.state.committedRevisions, isEmpty);
      expect(session.state.minimumRevisions['opaque:first'], 1);
      expect(source.calls[2].request.metadata.observedRevision, 1);
      expect(source.calls.skip(2).map((call) => call.kind), [
        DisplayRequestKind.update,
        DisplayRequestKind.read,
        DisplayRequestKind.query,
      ]);
      expect(session.state.canMutate, isTrue);
      session.dispose();
    });

    test(
      'DS07 rejection preserves exact global and scoped errors without reload',
      () async {
        // Given a coherent session and a decoded rejection with both error scopes.
        final ports = RecordingPorts();
        final session = makeSession(ports);
        await loadActive(session);
        final detail = session.state.detail.data;
        final errors = [
          DisplayFieldError(
            locator: null,
            code: 'global',
            message: 'Global message',
          ),
          DisplayFieldError(
            locator: input('name', '').locator,
            code: 'required',
            message: 'Scoped message',
          ),
        ];
        ports.displayHandler = (request) async => mutationWire(
          request.metadata.context,
          outcome: DisplayCommandOutcome.rejected,
          errors: errors,
        );
        // When the source rejects the submitted update.
        await session.update(observedRevision: 1, fields: [input('name', '')]);
        // Then errors and focus are preserved with zero automatic reads.
        expect(
          session.state.command.mutation!.fieldErrors.map(
            (error) => error.toJson(),
          ),
          errors.map((error) => error.toJson()),
        );
        expect(session.state.command.mutation!.message, 'receipt message');
        expect(session.state.detail.data, same(detail));
        expect(session.state.selectedResourceId, 'opaque:first');
        expect(session.state.committedRevisions, isEmpty);
        expect(ports.calls, hasLength(3));
        session.dispose();
      },
    );

    test('DS08 conflict floor needs explicit reload and caller revision is never replaced', () async {
      // Given a source advanced externally after the session observed revision one.
      final source = semanticSource();
      final session = sourceSession(source);
      await loadActive(session);
      // When another admitted public source request changes that resource.
      await source.update(
        DisplayUpdateRequest(
          resourceType: 'type',
          resourceId: 'opaque:first',
          metadata: DisplayRequestMetadata(
            context: baseContext(),
            observedRevision: 1,
          ),
          fields: [input('name', 'External')],
        ),
      );
      // Then the source is two while the session still holds revision one.
      expect(source.resources.first.sourceRevision, 2);
      expect(session.state.detail.data!.sourceRevision, 1);
      // Given stale positive caller revision one remains eligible to send.
      // When the session submits it unchanged.
      await session.update(
        observedRevision: 1,
        fields: [input('name', 'Client')],
      );
      // Then conflict raises the floor and never implicitly refreshes or commits.
      expect(
        session.state.command.mutation!.outcome,
        DisplayCommandOutcome.conflict,
      );
      expect(session.state.minimumRevisions['opaque:first'], 2);
      expect(session.state.projectionPending, isTrue);
      expect(source.callCount, 4);
      expect(source.calls.last.request.metadata.observedRevision, 1);
      // Given the conflict preserved its receipt and stale projection.
      // When the consumer explicitly reloads.
      await session.reload();
      // Then fresh projection permits editing while the historical conflict is intact.
      expect(session.state.canMutate, isTrue);
      expect(
        session.state.command.mutation!.outcome,
        DisplayCommandOutcome.conflict,
      );
      expect(
        valueOf(session.state.detail.data!, 'name'),
        const TextDisplayValue('External'),
      );
      // Given a coherent new projection but a stale caller observation.
      // When a later explicit command again supplies revision one.
      await session.update(observedRevision: 1, fields: []);
      // Then the source receives exactly one rather than a substituted revision two.
      expect(source.calls.last.request.metadata.observedRevision, 1);
      expect(session.state.command.sequence, 2);
      expect(
        session.state.command.mutation!.outcome,
        DisplayCommandOutcome.conflict,
      );
      session.dispose();
    });

    for (final kind in [
      DisplaySessionCommandKind.create,
      DisplaySessionCommandKind.delete,
    ]) {
      test('DS09 unsupported ${kind.name} is a separate settled capability', () async {
        // Given a coherent source-backed session for the named capability.
        final source = semanticSource();
        final session = sourceSession(source);
        await loadActive(session);
        final before = source.callCount;
        // When that typed public capability is explicitly requested.
        if (kind == DisplaySessionCommandKind.create) {
          await session.create(fields: [input('name', 'New')]);
        } else {
          await session.delete(observedRevision: 1);
        }
        // Then unsupported is visible with no advancement or automatic reload.
        expect(session.state.command.kind, kind);
        expect(session.state.command.phase, DisplaySessionCommandPhase.settled);
        expect(
          session.state.command.mutation!.outcome,
          DisplayCommandOutcome.unsupported,
        );
        expect(source.callCount, before + 1);
        expect(source.calls.last.kind.name, kind.name);
        expect(
          source.calls.last.request.metadata.observedRevision,
          kind == DisplaySessionCommandKind.create ? null : 1,
        );
        expect(source.resources.first.sourceRevision, 1);
        expect(session.state.committedRevisions, isEmpty);
        session.dispose();
      });
    }

    test('DS10 ordered duplicate locators and text bytes are defensively copied', () async {
      // Given a coherent session and a mutable ordered input list.
      final ports = RecordingPorts();
      final session = makeSession(ports);
      await loadActive(session);
      const text = ' 改訂\nΩ\u0085　 ';
      final fields = [
        input('name', text),
        input('note', ''),
        input('name', 'duplicate'),
      ];
      ports.displayHandler = (request) async => mutationWire(
        request.metadata.context,
        outcome: DisplayCommandOutcome.rejected,
      );
      // When update is invoked and the caller immediately clears its list.
      final pending = session.update(observedRevision: 1, fields: fields);
      fields.clear();
      await pending;
      // Then typed request order, duplicates and bytes survived independently.
      final request = ports.calls.last as DisplayUpdateRequest;
      expect(request.fields.map((field) => field.locator.fieldId), [
        'name',
        'note',
        'name',
      ]);
      expect(request.fields.map((field) => field.value), [
        const TextDisplayValue(text),
        const TextDisplayValue(''),
        const TextDisplayValue('duplicate'),
      ]);
      expect(() => request.fields.clear(), throwsUnsupportedError);
      expect(request.metadata.observedRevision, 1);
      session.dispose();
    });
  });

  group('safe refresh and command uncertainty', () {
    for (final omitted in [false, true]) {
      test(
        'DS11 ${omitted ? 'omitted' : 'stale included'} changed Detail stays pending',
        () async {
          // Given coherent old projections and a changed receipt at revision two.
          final ports = RecordingPorts();
          final session = makeSession(ports);
          await loadActive(session);
          ports.displayHandler = (request) async =>
              request.kind == DisplayRequestKind.update
              ? mutationWire(
                  request.metadata.context,
                  revision: 2,
                  includedRevision: omitted ? null : 1,
                )
              : ports.reply(request);
          // When the update refresh returns only old revision one projections.
          await session.update(
            observedRevision: 1,
            fields: [input('name', 'New')],
          );
          // Then the accepted receipt survives and editing remains pending.
          expect(session.state.command.mutation!.committedRevision, 2);
          expect(session.state.detail.data!.sourceRevision, 1);
          expect(session.state.projectionPending, isTrue);
          expect(session.state.canMutate, isFalse);
          // Given fresh projection revision two becomes available.
          ports.revision = 2;
          // When the consumer explicitly reloads once.
          await session.reload();
          // Then the exact commit floor and both projection parts are satisfied.
          expect(session.state.canMutate, isTrue);
          expect(session.state.committedRevisions['opaque:first'], 2);
          expect(
            ports.calls.where((call) => call.kind == DisplayRequestKind.update),
            hasLength(1),
          );
          session.dispose();
        },
      );
    }

    for (final failedKind in [
      DisplayRequestKind.read,
      DisplayRequestKind.query,
    ]) {
      test('DS12 successful receipt survives refresh ${failedKind.name} failure', () async {
        // Given a changed command with one explicitly injected refresh failure.
        final ports = RecordingPorts();
        final session = makeSession(ports);
        await loadActive(session);
        var fail = true;
        ports.displayHandler = (request) async {
          if (request.kind == DisplayRequestKind.update) {
            ports.revision = 2;
          }
          if (request.kind == failedKind && fail) {
            fail = false;
            throw const DisplayTransportException(
              DisplayTransportFailure.unavailable,
              'refresh failed',
            );
          }
          return ports.reply(request);
        };
        // When the changed command completes its one bounded refresh.
        await session.update(
          observedRevision: 1,
          fields: [input('name', 'New')],
        );
        // Then command stays settled/committed while its projection remains pending.
        expect(session.state.command.phase, DisplaySessionCommandPhase.settled);
        expect(session.state.command.failure, isNull);
        expect(session.state.committedRevisions['opaque:first'], 2);
        expect(session.state.projectionPending, isTrue);
        expect(ports.calls.skip(3).map((call) => call.kind), [
          DisplayRequestKind.read,
          DisplayRequestKind.query,
        ]);
        // Given only the named safe read failed, and a fresh reply now exists.
        // When the matching explicit retry is requested.
        if (failedKind == DisplayRequestKind.read) {
          await session.retryDetail();
        } else {
          await session.retryList();
        }
        // Then that missing part completes coherence without replaying the command.
        expect(session.state.canMutate, isTrue);
        expect(session.state.command.mutation!.committedRevision, 2);
        expect(
          ports.calls.where((call) => call.kind == DisplayRequestKind.update),
          hasLength(1),
        );
        session.dispose();
      });
    }

    test(
      'DS13 held semantic projections require release and explicit reload',
      () async {
        // Given a real semantic source whose current projection is held.
        final source = semanticSource();
        final session = sourceSession(source);
        await loadActive(session);
        source.holdProjection();
        // When one update commits beneath the held projection.
        await session.update(
          observedRevision: 1,
          fields: [input('name', 'Committed')],
        );
        // Then semantic source advances while the session stays pending at old evidence.
        expect(source.resources.first.sourceRevision, 2);
        expect(session.state.committedRevisions['opaque:first'], 2);
        expect(session.state.detail.data!.sourceRevision, 1);
        expect(session.state.projectionPending, isTrue);
        // Given projection remains deliberately held.
        // When a first explicit stale reload is attempted.
        await session.reload();
        // Then it cannot clear pending or lower the known floor.
        expect(session.state.projectionPending, isTrue);
        expect(session.state.minimumRevisions['opaque:first'], 2);
        // Given projection still remains held after the first reload.
        // When a second explicit stale reload is attempted.
        await session.reload();
        // Then it likewise cannot make stale editing eligible.
        expect(session.state.canMutate, isFalse);
        expect(session.state.committedRevisions['opaque:first'], 2);
        // Given the source owner releases its held projection.
        source.releaseProjection();
        // When the consumer explicitly reloads again.
        await session.reload();
        // Then both actual projections meet floor two with only one source command.
        expect(session.state.canMutate, isTrue);
        expect(session.state.detail.data!.sourceRevision, 2);
        expect(
          source.calls.where((call) => call.kind == DisplayRequestKind.update),
          hasLength(1),
        );
        session.dispose();
      },
    );

    for (final detailAhead in [true, false]) {
      test(
        'DS14 ${detailAhead ? 'Detail ahead of List' : 'List ahead of Detail'} needs exact equality',
        () async {
          // Given a coherent session and a changed ordinary Operation floor two.
          final ports = RecordingPorts();
          final session = makeSession(ports);
          await loadActive(session);
          ports.revision = 2;
          // When the separate command commits without any Display request.
          await session.executeOperation(
            operationId: 'advance',
            observedRevision: 1,
          );
          // Then the receipt establishes a pending projection obligation.
          expect(session.state.projectionPending, isTrue);
          expect(ports.calls, hasLength(2));
          // Given the named projection part is newer than the other.
          ports.displayHandler = (request) async =>
              request.kind == DisplayRequestKind.read
              ? detailWire(
                  request.metadata.context,
                  revision: detailAhead ? 3 : 2,
                )
              : listWire(
                  request.metadata.context,
                  revision: detailAhead ? 2 : 3,
                );
          // When the consumer explicitly reloads both parts.
          await session.reload();
          // Then even above-floor revisions are pending unless row and Detail match exactly.
          expect(session.state.minimumRevisions['opaque:first'], 3);
          expect(session.state.projectionPending, isTrue);
          expect(session.state.canMutate, isFalse);
          // Given both parts can now report revision three.
          ports.revision = 3;
          ports.displayHandler = null;
          // When another explicit coherent reload occurs.
          await session.reload();
          // Then the obligation clears without changing the earlier commit floor two.
          expect(session.state.canMutate, isTrue);
          expect(session.state.committedRevisions['opaque:first'], 2);
          session.dispose();
        },
      );
    }

    test('DS15 higher committed floor survives old replies and codec or read failure', () async {
      // Given a coherent session and a changed Operation receipt at floor five.
      final ports = RecordingPorts();
      final session = makeSession(ports);
      await loadActive(session);
      ports.revision = 5;
      // When the separate Operation accepts that commit.
      await session.executeOperation(
        operationId: 'advance',
        observedRevision: 1,
      );
      // Then floor five is retained as accepted commit evidence.
      expect(session.state.committedRevisions['opaque:first'], 5);
      // Given older projection replies are available.
      ports.revision = 2;
      // When those replies are explicitly reloaded.
      await session.reload();
      // Then older evidence cannot lower either tracked floor.
      expect(session.state.minimumRevisions['opaque:first'], 5);
      expect(session.state.committedRevisions['opaque:first'], 5);
      expect(session.state.projectionPending, isTrue);
      // Given the next collection reply is malformed.
      ports.displayHandler = (request) async => <String, Object?>{};
      // When collection retry receives it.
      await session.retryList();
      // Then codec failure preserves both floors and the Operation receipt.
      expect(session.state.list.failure!.kind, DisplaySessionFailureKind.codec);
      expect(session.state.minimumRevisions['opaque:first'], 5);
      expect(session.state.command.operation!.committedRevision, 5);
      // Given the next active read has a declared delivery failure.
      ports.displayHandler = (request) async =>
          throw const DisplayTransportException(
            DisplayTransportFailure.unavailable,
            'read failed',
          );
      // When Detail is explicitly retried.
      await session.retryDetail();
      // Then read failure also preserves the higher command floor.
      expect(
        session.state.detail.failure!.kind,
        DisplaySessionFailureKind.unavailable,
      );
      expect(session.state.committedRevisions['opaque:first'], 5);
      session.dispose();
    });

    test('DS16 changed Operation never implicitly reloads Display', () async {
      // Given a coherent session backed by a semantic source.
      final source = semanticSource();
      final session = sourceSession(source);
      await loadActive(session);
      final before = source.callCount;
      // When the separate Operation changes the source.
      await session.executeOperation(
        operationId: 'advance',
        observedRevision: 1,
      );
      // Then only Operation crosses, receipt is visible and projection remains old.
      expect(source.callCount, before);
      expect(source.operationCallCount, 1);
      expect(session.state.command.operation!.committedRevision, 2);
      expect(session.state.detail.data!.sourceRevision, 1);
      expect(session.state.projectionPending, isTrue);
      // Given the Operation receipt requires safe projection evidence.
      // When the consumer explicitly reloads.
      await session.reload();
      // Then the transitioned label and removed action are projected at revision two.
      expect(
        valueOf(session.state.detail.data!, 'status'),
        const TextDisplayValue('Done'),
      );
      expect(session.state.detail.data!.model.actions, isEmpty);
      expect(session.state.canMutate, isTrue);
      expect(source.operationCallCount, 1);
      session.dispose();
    });

    for (final outcome in [
      DisplayCommandOutcome.rejected,
      DisplayCommandOutcome.conflict,
      DisplayCommandOutcome.unsupported,
    ]) {
      test(
        'DS17 ${outcome.name} Operation has its own result and no Display calls',
        () async {
          // Given a coherent session and the named decoded Operation outcome.
          final ports = RecordingPorts();
          final session = makeSession(ports);
          await loadActive(session);
          ports.operationHandler = (request) async => operationWire(
            request.metadata.context,
            outcome: outcome,
            revision: outcome == DisplayCommandOutcome.conflict ? 2 : 1,
          );
          // When the ordinary Operation is explicitly attempted.
          await session.executeOperation(
            operationId: 'advance',
            observedRevision: 1,
          );
          // Then its settled result does not become a Display mutation or reload.
          expect(session.state.command.operation!.outcome, outcome);
          expect(session.state.command.mutation, isNull);
          expect(
            session.state.command.phase,
            DisplaySessionCommandPhase.settled,
          );
          expect(ports.calls, hasLength(2));
          expect(ports.operations, hasLength(1));
          expect(session.state.committedRevisions, isEmpty);
          expect(
            session.state.minimumRevisions['opaque:first'],
            outcome == DisplayCommandOutcome.conflict ? 2 : 1,
          );
          expect(
            session.state.projectionPending,
            outcome == DisplayCommandOutcome.conflict,
          );
          session.dispose();
        },
      );
    }

    for (final operation in [false, true]) {
      for (final failure in DisplayTransportFailure.values) {
        test(
          '${operation ? 'DS19' : 'DS18'} ${failure.name} ${operation ? 'Operation' : 'update'} is uncertain without replay',
          () async {
            // Given a coherent session and an explicit named command delivery failure.
            final ports = RecordingPorts();
            final session = makeSession(ports);
            await loadActive(session);
            if (operation) {
              ports.operationHandler = (request) async =>
                  throw DisplayTransportException(failure, 'lost command');
            } else {
              ports.displayHandler = (request) async =>
                  throw DisplayTransportException(failure, 'lost command');
            }
            // When that command crosses its own raw port once.
            if (operation) {
              await session.executeOperation(
                operationId: 'advance',
                observedRevision: 1,
              );
            } else {
              await session.update(observedRevision: 1, fields: []);
            }
            // Then failure is historical uncertainty with no fabricated receipt/commit/refresh.
            expect(
              session.state.command.phase,
              DisplaySessionCommandPhase.failed,
            );
            expect(
              session.state.command.failure!.kind,
              failure == DisplayTransportFailure.unavailable
                  ? DisplaySessionFailureKind.unavailable
                  : DisplaySessionFailureKind.ambiguous,
            );
            expect(session.state.command.mutation, isNull);
            expect(session.state.command.operation, isNull);
            expect(session.state.committedRevisions, isEmpty);
            expect(session.state.commandUncertain, isTrue);
            expect(session.state.projectionPending, isTrue);
            expect(ports.calls, hasLength(operation ? 2 : 3));
            expect(ports.operations, hasLength(operation ? 1 : 0));
            // Given command uncertainty blocks further command admission.
            final before = session.state;
            // When another explicit Save is attempted.
            final duplicate = session.update(observedRevision: 1, fields: []);
            // Then it fails before either state replacement or another raw call.
            await expectLater(duplicate, throwsStateError);
            expect(session.state, same(before));
            expect(ports.calls, hasLength(operation ? 2 : 3));
            session.dispose();
          },
        );
      }
    }

    for (final listFirst in [true, false]) {
      test(
        'DS20 ${listFirst ? 'List' : 'Detail'} first safe retry preserves command failure',
        () async {
          // Given an explicit ambiguous command with no accepted receipt.
          final ports = RecordingPorts();
          final session = makeSession(ports);
          await loadActive(session);
          ports.displayHandler = (request) async =>
              throw const DisplayTransportException(
                DisplayTransportFailure.ambiguous,
                'unknown',
              );
          // When one update loses its delivery result.
          await session.update(observedRevision: 1, fields: []);
          // Then outcome remains failed and uncertain.
          expect(
            session.state.command.phase,
            DisplaySessionCommandPhase.failed,
          );
          final command = session.state.command;
          // Given a coherent safe source projection is now available.
          ports.displayHandler = null;
          // When only the separately named first part is explicitly retried.
          if (listFirst) {
            await session.retryList();
          } else {
            await session.retryDetail();
          }
          // Then one successful part cannot clear the two-part obligation.
          expect(session.state.projectionPending, isTrue);
          expect(session.state.command, same(command));
          // Given the complementary safe part is still required.
          // When that part is explicitly retried.
          if (listFirst) {
            await session.retryDetail();
          } else {
            await session.retryList();
          }
          // Then coherence permits a new edit without inventing the historical receipt.
          expect(session.state.canMutate, isTrue);
          expect(session.state.commandUncertain, isFalse);
          expect(session.state.command, same(command));
          expect(session.state.committedRevisions, isEmpty);
          // Given a later explicit new command is eligible.
          ports.displayHandler = (request) async => mutationWire(
            request.metadata.context,
            outcome: DisplayCommandOutcome.rejected,
          );
          // When it is submitted separately.
          await session.update(observedRevision: 1, fields: []);
          // Then exactly the new attempt settles with the next sequence.
          expect(session.state.command.sequence, 2);
          expect(
            session.state.command.mutation!.outcome,
            DisplayCommandOutcome.rejected,
          );
          session.dispose();
        },
      );
    }
  });

  group('whole reply admission', () {
    for (final variant in ['wrong kind', 'wrong resource', 'malformed body']) {
      test('DS21 $variant mutation rejects the whole reply', () async {
        // Given a coherent session and the named invalid raw mutation envelope.
        final ports = RecordingPorts();
        final session = makeSession(ports);
        await loadActive(session);
        final oldDetail = session.state.detail.data;
        final oldContext = session.state.context;
        ports.displayHandler = (request) async {
          final wire = mutationWire(request.metadata.context, revision: 2);
          if (variant == 'wrong kind') {
            wire['kind'] = 'detail';
          }
          if (variant == 'wrong resource') {
            wire['data'] = mutationResult(
              revision: 2,
              resourceId: 'wrong',
            ).toJson();
          }
          if (variant == 'malformed body') {
            wire['data'] = <String, Object?>{};
          }
          return wire;
        };
        // When the command receives that raw envelope after dispatch.
        await session.update(observedRevision: 1, fields: []);
        // Then no receipt, replacement context or included projection is adopted.
        expect(
          session.state.command.failure!.kind,
          DisplaySessionFailureKind.codec,
        );
        expect(session.state.command.mutation, isNull);
        expect(session.state.detail.data, same(oldDetail));
        expect(session.state.context, oldContext);
        expect(session.state.commandUncertain, isTrue);
        expect(session.state.committedRevisions, isEmpty);
        expect(ports.calls, hasLength(3));
        session.dispose();
      });
    }

    for (final variant in ['wrong resource', 'illicit Display member']) {
      test('DS22 $variant Operation rejects the whole reply', () async {
        // Given coherent projections and the named invalid separate Operation envelope.
        final ports = RecordingPorts();
        final session = makeSession(ports);
        await loadActive(session);
        final oldDetail = session.state.detail.data;
        ports.operationHandler = (request) async {
          final wire = operationWire(
            request.metadata.context,
            revision: 2,
            resourceId: variant == 'wrong resource' ? 'wrong' : 'opaque:first',
          );
          if (variant == 'illicit Display member') {
            wire['display'] = detailData(request.metadata.context).toJson();
          }
          return wire;
        };
        // When the separate command receives that envelope.
        await session.executeOperation(
          operationId: 'advance',
          observedRevision: 1,
        );
        // Then codec failure leaves the command uncertain without Display adoption/calls.
        expect(
          session.state.command.failure!.kind,
          DisplaySessionFailureKind.codec,
        );
        expect(session.state.command.operation, isNull);
        expect(session.state.detail.data, same(oldDetail));
        expect(session.state.commandUncertain, isTrue);
        expect(session.state.committedRevisions, isEmpty);
        expect(ports.calls, hasLength(2));
        session.dispose();
      });
    }

    for (final variant in ['resourceType', 'screen', 'detailScreen']) {
      test('DS23 wrong List $variant preserves accepted projection', () async {
        // Given accepted List/Detail and an otherwise valid mismatched List.
        final ports = RecordingPorts();
        final session = makeSession(ports);
        await loadActive(session);
        final previous = session.state.list.data;
        ports.displayHandler = (request) async => listWire(
          request.metadata.context,
          type: variant == 'resourceType' ? 'wrong' : 'type',
          screen: variant == 'screen' ? 'wrong' : 'collection',
          detailScreen: variant == 'detailScreen' ? 'wrong' : 'detail',
        );
        // When an explicit query receives the wrong configured envelope identity.
        await session.query();
        // Then failure does not adopt data or change accepted focus.
        expect(session.state.list.phase, DisplaySessionReadPhase.failed);
        expect(
          session.state.list.failure!.kind,
          DisplaySessionFailureKind.codec,
        );
        expect(session.state.list.data, same(previous));
        expect(session.state.selectedResourceId, 'opaque:first');
        expect(session.state.command.sequence, 0);
        session.dispose();
      });
    }

    for (final variant in ['resource', 'screen']) {
      test('DS24 wrong Detail $variant never changes accepted focus', () async {
        // Given an accepted focus and an otherwise valid wrong-resource/screen reply.
        final ports = RecordingPorts();
        final session = makeSession(ports);
        await loadActive(session);
        final previous = session.state.detail.data;
        ports.displayHandler = (request) async => detailWire(
          request.metadata.context,
          id: variant == 'resource' ? 'opaque:first' : 'opaque:other',
          screen: variant == 'screen' ? 'wrong' : 'detail',
          revision: 4,
        );
        // When a different opaque resource is explicitly requested.
        await session.read('opaque:other');
        // Then the accepted selection/data remain the preceding resource.
        expect(
          session.state.detail.failure!.kind,
          DisplaySessionFailureKind.codec,
        );
        expect(session.state.detail.data, same(previous));
        expect(session.state.selectedResourceId, 'opaque:first');
        expect(session.state.minimumRevisions['opaque:first'], 1);
        session.dispose();
      });
    }

    for (final command in [false, true]) {
      test(
        'DS25 malformed known context ${command ? 'command' : 'read'} is codec failure',
        () async {
          // Given a coherent flow and a malformed typed locale in the next raw reply.
          final ports = RecordingPorts();
          final session = makeSession(ports);
          await loadActive(session);
          final previous = session.state.detail.data;
          ports.displayHandler = (request) async {
            final wire = command
                ? mutationWire(request.metadata.context, revision: 2)
                : detailWire(request.metadata.context);
            final context = wire['context']! as Map<String, Object?>;
            final families = context['families']! as List;
            final locale = families.first as Map<String, Object?>;
            locale['payload'] = <String, Object?>{'localeTag': 42};
            return wire;
          };
          // When the named public method receives that malformed known family.
          if (command) {
            await session.update(observedRevision: 1, fields: []);
          } else {
            await session.retryDetail();
          }
          // Then decoding fails before context/projection/receipt adoption.
          expect(
            command
                ? session.state.command.failure!.kind
                : session.state.detail.failure!.kind,
            DisplaySessionFailureKind.codec,
          );
          expect(session.state.detail.data, same(previous));
          expect(session.state.commandUncertain, command);
          expect(session.state.committedRevisions, isEmpty);
          expect(session.state.context, baseContext());
          session.dispose();
        },
      );
    }

    test('DS26 constructor and retained snapshots are immutable without eager work', () async {
      // Given mutable initial family input and instrumented ports/clock.
      final families = baseContext().families.toList();
      final initial = contextWith(baseContext(), families: families);
      final ports = RecordingPorts();
      var clockCalls = 0;
      // When the session is constructed and the caller clears its original family list.
      final session = makeSession(
        ports,
        context: initial,
        clock: () {
          clockCalls++;
          return DateTime.utc(2026, 10, 2);
        },
      );
      families.clear();
      final empty = session.state;
      // Then construction invokes no clock/port and exposes immutable empty snapshots.
      expect(clockCalls, 0);
      expect(ports.calls, isEmpty);
      expect(ports.operations, isEmpty);
      expect(empty.context.families, hasLength(2));
      expect(empty.command.sequence, 0);
      expect(empty.list.phase, DisplaySessionReadPhase.idle);
      expect(() => empty.context.families.clear(), throwsUnsupportedError);
      expect(() => empty.diagnostics.clear(), throwsUnsupportedError);
      expect(() => empty.minimumRevisions.clear(), throwsUnsupportedError);
      expect(() => empty.committedRevisions.clear(), throwsUnsupportedError);
      // Given the original empty snapshot is retained.
      // When a collection projection is explicitly queried.
      await session.query();
      // Then the original snapshot remains empty while new data collections are immutable.
      expect(empty.list.data, isNull);
      expect(empty.minimumRevisions, isEmpty);
      expect(
        () => session.state.list.data!.model.items.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => session.state.minimumRevisions['x'] = 9,
        throwsUnsupportedError,
      );
      session.dispose();
    });
  });

  group('fixed context continuation', () {
    for (final variant in [
      'source',
      'component',
      'producer',
      'required expired',
      'required unsupported',
      'required unknown',
      'local clock',
    ]) {
      test('DS27 $variant fails before the first raw port', () async {
        // Given a structurally valid initial context with the named admission defect.
        final ports = RecordingPorts();
        var context = baseContext(assigned: true);
        var clock = DateTime.utc(2026, 10, 2);
        if (variant == 'source') {
          context = contextWith(context, source: 'wrong');
        }
        if (variant == 'component') {
          context = contextWith(context, component: 'wrong');
        }
        if (variant == 'producer') {
          context = replaceFamily(
            context,
            familyCopy(context.families.first, producer: 'wrong'),
          );
        }
        if (variant == 'required expired') {
          context = replaceFamily(
            context,
            familyCopy(
              context.families.last,
              expiresAt: DateTime.utc(2026, 10, 1),
            ),
          );
        }
        if (variant == 'required unsupported') {
          context = replaceFamily(
            context,
            familyCopy(
              context.families.last,
              version: 2,
              payload: OpaquePresentationPayload({'future': true}),
            ),
          );
        }
        if (variant == 'required unknown') {
          context = contextWith(
            context,
            families: [...context.families, unknownFamily(required: true)],
          );
        }
        if (variant == 'local clock') {
          clock = DateTime(2026, 10, 2);
        }
        final session = makeSession(
          ports,
          context: context,
          clock: () => clock,
        );
        final original = session.state.context;
        // When query first attempts request-time admission.
        await session.query();
        // Then the exact policy failure is visible without port or context adoption.
        final expected = {
          'source': 'source-mismatch',
          'component': 'component-mismatch',
          'producer': 'producer-not-allowed',
          'required expired': 'expired',
          'required unsupported': 'unsupported-version',
          'required unknown': 'unknown-family',
          'local clock': 'clock-not-utc',
        }[variant];
        expect(
          session.state.list.failure!.kind,
          DisplaySessionFailureKind.context,
        );
        expect(session.state.contextFailure!.contextCode, expected);
        expect(session.state.context, same(original));
        expect(ports.calls, isEmpty);
        expect(session.state.commandUncertain, isFalse);
        if (variant == 'local clock') {
          // Given a corrected explicit UTC clock after a pre-port clock failure.
          clock = DateTime.utc(2026, 10, 2);
          // When the consumer explicitly retries the safe List request.
          await session.retryList();
          // Then the transient request-time clock denial can be re-admitted.
          expect(session.state.list.phase, DisplaySessionReadPhase.ready);
          expect(session.state.contextFailure, isNull);
          expect(ports.calls, hasLength(1));
        }
        session.dispose();
      });
    }

    for (final method in ['query', 'update', 'Operation']) {
      test(
        'DS28 required expiry during $method prevents reply adoption',
        () async {
          // Given a required family valid at dispatch but expired when its reply arrives.
          var clock = DateTime.utc(2026, 10, 2);
          final ports = RecordingPorts();
          final initial = replaceFamily(
            baseContext(assigned: true),
            familyCopy(
              baseContext(assigned: true).families.last,
              expiresAt: DateTime.utc(2026, 10, 3),
            ),
          );
          final session = makeSession(
            ports,
            context: initial,
            clock: () => clock,
          );
          if (method != 'query') {
            await loadActive(session);
          }
          final previous = session.state.detail.data;
          ports.displayHandler = (request) async {
            clock = DateTime.utc(2026, 10, 4);
            return ports.reply(request);
          };
          ports.operationHandler = (request) async {
            clock = DateTime.utc(2026, 10, 4);
            return operationWire(request.metadata.context, revision: 2);
          };
          // When the named method receives the now-expired required context.
          if (method == 'query') {
            await session.query();
          } else if (method == 'update') {
            await session.update(observedRevision: 1, fields: []);
          } else {
            await session.executeOperation(
              operationId: 'advance',
              observedRevision: 1,
            );
          }
          // Then receipt/data adoption is denied; dispatched commands remain uncertain.
          expect(session.state.contextFailure!.contextCode, 'expired');
          expect(session.state.context, initial);
          expect(session.state.detail.data, same(previous));
          expect(session.state.commandUncertain, method != 'query');
          expect(session.state.command.mutation, isNull);
          expect(session.state.command.operation, isNull);
          expect(session.state.committedRevisions, isEmpty);
          expect(
            ports.calls,
            hasLength(
              method == 'query'
                  ? 1
                  : method == 'update'
                  ? 3
                  : 2,
            ),
          );
          session.dispose();
        },
      );
    }

    for (final variant in [
      'assignment',
      'locale',
      'flow',
      'source',
      'component',
      'new-family',
      'expiry metadata',
    ]) {
      test(
        'DS29 response $variant replacement latches incompatibility',
        () async {
          // Given accepted focus/context and an otherwise valid incompatible response.
          final initial = baseContext(assigned: true);
          final ports = RecordingPorts();
          final session = makeSession(ports, context: initial);
          await loadActive(session);
          final previous = session.state.list.data;
          final previousDetail = session.state.detail.data;
          final replacement = incompatibleContext(initial, variant);
          ports.displayHandler = (request) async => listWire(replacement);
          // When an explicit query receives that replacement.
          await session.query();
          // Then the context policy latches and preserves last admitted focus/projections.
          expect(
            session.state.list.failure!.kind,
            DisplaySessionFailureKind.context,
          );
          expect(session.state.contextFailure, isNotNull);
          expect(session.state.context, initial);
          expect(session.state.list.data, same(previous));
          expect(session.state.detail.data, same(previousDetail));
          expect(session.state.selectedResourceId, 'opaque:first');
          expect(session.state.canMutate, isFalse);
          // Given incompatible response context is latched for this fixed instance.
          final before = ports.calls.length;
          ports.displayHandler = null;
          // When an explicit safe reload is attempted with otherwise valid producer replies.
          await session.reload();
          // Then no later raw call can resume the incompatible instance.
          expect(ports.calls, hasLength(before));
          expect(session.state.context, initial);
          expect(session.state.contextFailure, isNotNull);
          session.dispose();
        },
      );
    }

    test(
      'DS30 only producer attempt replacement continues through every boundary',
      () async {
        // Given a fixed assigned flow and a producer supplying successive attempts.
        final ports = RecordingPorts();
        final initial = baseContext(assigned: true);
        var attempt = 1;
        ports.displayHandler = (request) async {
          if (request.kind == DisplayRequestKind.update) {
            ports.revision = 2;
          }
          return ports.reply(
            request,
            context: withAttempt(
              request.metadata.context,
              'attempt-${++attempt}',
            ),
          );
        };
        ports.operationHandler = (request) async {
          ports.revision = 3;
          return operationWire(
            withAttempt(request.metadata.context, 'attempt-${++attempt}'),
            revision: 3,
          );
        };
        final session = makeSession(ports, context: initial);
        await loadActive(session);
        // When a changed update and its bounded refresh consume producer replacements.
        await session.update(observedRevision: 1, fields: []);
        // Then each request carries the preceding reply attempt and assignment stays fixed.
        expect(
          ports.calls.map((request) => attemptOf(request.metadata.context)),
          ['attempt-1', 'attempt-2', 'attempt-3', 'attempt-4', 'attempt-5'],
        );
        expect(attemptOf(session.state.context), 'attempt-6');
        expect(session.state.context.families.last, initial.families.last);
        // Given the next ordinary Operation uses the last admitted producer attempt.
        // When that separate operation is explicitly executed.
        await session.executeOperation(
          operationId: 'advance',
          observedRevision: 2,
        );
        // Then it carries attempt six and admits seven without Display calls.
        expect(
          attemptOf(ports.operations.single.metadata.context),
          'attempt-6',
        );
        expect(attemptOf(session.state.context), 'attempt-7');
        expect(ports.calls, hasLength(5));
        // Given the Operation projection remains pending.
        // When the consumer explicitly reloads the active resource and collection.
        await session.reload();
        // Then the new producer attempts continue in sequence through both safe calls.
        expect(
          ports.calls
              .skip(5)
              .map((request) => attemptOf(request.metadata.context)),
          ['attempt-7', 'attempt-8'],
        );
        expect(attemptOf(session.state.context), 'attempt-9');
        expect(session.state.context.families.last, initial.families.last);
        expect(session.state.canMutate, isTrue);
        session.dispose();
      },
    );

    for (final variant in [
      'expired',
      'unsupported-version',
      'unknown-family',
    ]) {
      test(
        'DS31 optional initial $variant is omitted with retained diagnostic',
        () async {
          // Given an optional family with the separately named omission reason.
          final ports = RecordingPorts();
          final initial = optionalContext(variant);
          final session = makeSession(ports, context: initial);
          // When the first query admits its reduced request context.
          await session.query();
          // Then the omitted family never crosses the port and the reason remains visible.
          expect(session.state.diagnostics.single.code, variant);
          expect(
            ports.calls.single.metadata.context.families.any(
              (family) =>
                  family.namespace ==
                  session.state.diagnostics.single.namespace,
            ),
            isFalse,
          );
          expect(session.state.list.phase, DisplaySessionReadPhase.ready);
          // Given the session has already removed the optional family.
          // When a later explicit List retry uses that reduced context.
          await session.retryList();
          // Then the same bounded diagnostic remains rather than disappearing/duplicating.
          expect(session.state.diagnostics, hasLength(1));
          expect(session.state.diagnostics.single.code, variant);
          expect(ports.calls.last.metadata.context, session.state.context);
          session.dispose();
        },
      );
    }

    test('DS32 optional expiry while read is pending accepts omission and retains evidence', () async {
      // Given a locale family that will expire during an explicitly gated read.
      var clock = DateTime.utc(2026, 10, 2);
      final initial = replaceFamily(
        baseContext(),
        familyCopy(
          baseContext().families.first,
          expiresAt: DateTime.utc(2026, 10, 3),
        ),
      );
      final ports = RecordingPorts();
      final session = makeSession(ports, context: initial, clock: () => clock);
      await loadList(session);
      final gate = PortGate();
      ports.displayHandler = (request) async {
        gate.entered.complete();
        await gate.release.future;
        return detailWire(
          contextWith(
            request.metadata.context,
            families: request.metadata.context.families
                .where(
                  (family) => family.namespace != 'textus.presentation.locale',
                )
                .toList(),
          ),
        );
      };
      // When read is pending and the optional family's clock crosses expiry.
      final pending = session.read('opaque:first');
      await gate.entered.future;
      clock = DateTime.utc(2026, 10, 4);
      gate.release.complete();
      await pending;
      // Then the omission is admitted and its reason is retained despite absence from reply.
      expect(session.state.detail.phase, DisplaySessionReadPhase.ready);
      expect(session.state.diagnostics.single.code, 'expired');
      expect(session.state.context.families, hasLength(1));
      // Given subsequent calls use the reduced producer continuation.
      ports.displayHandler = null;
      // When a later explicit collection retry occurs.
      await session.retryList();
      // Then the omitted family stays absent and its diagnostic remains visible.
      expect(ports.calls.last.metadata.context.families, hasLength(1));
      expect(session.state.diagnostics.single.code, 'expired');
      session.dispose();
    });

    test('DS33 allowlisted opaque extension is carried and wholly replaced', () async {
      // Given an explicitly supported bounded optional extension with old keys.
      final extension = unknownFamily(
        values: {
          'old': 'value',
          'nested': {'keep': true},
        },
      );
      final initial = contextWith(
        baseContext(),
        families: [...baseContext().families, extension],
      );
      final policy = contextPolicy(extension: true);
      final ports = RecordingPorts();
      ports.displayHandler = (request) async => listWire(
        replaceFamily(
          request.metadata.context,
          familyCopy(
            extension,
            payload: OpaquePresentationPayload({
              'new': ['bounded', 2],
            }),
          ),
        ),
      );
      final session = makeSession(ports, context: initial, policy: policy);
      // When the producer replaces the whole optional payload in its reply.
      await session.query();
      // Then old keys are absent and no deep merge or diagnostic is invented.
      final payload =
          session.state.context.families.last.payload
              as OpaquePresentationPayload;
      expect(payload.values, {
        'new': ['bounded', 2],
      });
      expect(payload.values.containsKey('old'), isFalse);
      expect(session.state.diagnostics, isEmpty);
      // Given the new producer payload is the last admitted continuation.
      ports.displayHandler = null;
      // When a later explicit safe query is performed.
      await session.retryList();
      // Then the request carries exactly that immutable replacement.
      expect(ports.calls.last.metadata.context.families.last.payload, payload);
      expect(() => payload.values.clear(), throwsUnsupportedError);
      session.dispose();
    });

    test(
      'DS34 neutral locale correlation flow crosses all common boundaries',
      () async {
        // Given a neutral context with no supplied assignment and coherent projections.
        final ports = RecordingPorts();
        final session = makeSession(ports);
        await loadActive(session);
        ports.revision = 2;
        // When an explicit update refreshes through the common session.
        await session.update(observedRevision: 1, fields: []);
        // Then the same neutral context is retained on every Display request.
        expect(
          ports.calls.every(
            (request) => request.metadata.context == baseContext(),
          ),
          isTrue,
        );
        expect(
          session.state.context.families.any(
            (family) => family.payload is SuppliedArmPresentationPayload,
          ),
          isFalse,
        );
        // Given a separate neutral Operation can be explicitly dispatched.
        ports.revision = 3;
        // When that Operation is executed.
        await session.executeOperation(
          operationId: 'advance',
          observedRevision: 2,
        );
        // Then neutral context is admitted with zero automatic Display calls.
        expect(ports.operations.single.metadata.context, baseContext());
        expect(ports.calls, hasLength(5));
        // Given the neutral Operation requires explicit projection refresh.
        // When Reload is explicitly requested.
        await session.reload();
        // Then safe refresh clears pending with no synthesized assignment.
        expect(session.state.canMutate, isTrue);
        expect(session.state.context, baseContext());
        session.dispose();
      },
    );

    test('DS35 independent sessions interleave without identity or failure inheritance', () async {
      // Given independent source/component/flow configurations and one gated query.
      final portsA = RecordingPorts();
      final portsB = RecordingPorts();
      final contextA = baseContext(assigned: true);
      final contextB = baseContext(
        flow: 'flow-b',
        source: 'source-b',
        component: 'component-b',
      );
      final gate = PortGate();
      portsA.displayHandler = (request) async {
        gate.entered.complete();
        await gate.release.future;
        return listWire(contextWith(contextA, component: 'incompatible'));
      };
      final a = makeSession(portsA, context: contextA);
      final b = makeSession(
        portsB,
        context: contextB,
        source: 'source-b',
        component: 'component-b',
      );
      // When A remains pending while B completes its own query and read.
      final pending = a.query();
      await gate.entered.future;
      await loadActive(b);
      // Then B has only its own fixed identity/context and coherent focus.
      expect(b.state.context, contextB);
      expect(b.state.contextFailure, isNull);
      expect(b.state.canMutate, isTrue);
      expect(
        portsB.calls.every((request) => request.metadata.context == contextB),
        isTrue,
      );
      // Given A receives a context incompatibility while B already completed.
      // When A's gated reply is released.
      gate.release.complete();
      await pending;
      // Then A's failure does not change B's source, component, continuation or permissions.
      expect(a.state.contextFailure, isNotNull);
      expect(b.state.contextFailure, isNull);
      expect(b.state.context, contextB);
      expect(b.sourceId, 'source-b');
      expect(b.componentId, 'component-b');
      expect(b.state.canMutate, isTrue);
      a.dispose();
      b.dispose();
    });
  });

  group('disposal reentry and local preconditions', () {
    for (final stage in [
      'query',
      'read',
      'update',
      'Operation',
      'first refresh',
    ]) {
      test(
        'DS36 dispose during $stage prevents late publication and continuation',
        () async {
          // Given a session with the separately named next raw call controllably gated.
          final ports = RecordingPorts();
          final session = makeSession(ports);
          if (stage != 'query') {
            await loadActive(session);
          }
          final gate = PortGate();
          ports.displayHandler = (request) async {
            if (request.kind == DisplayRequestKind.update) {
              ports.revision = 2;
            }
            final target = stage == 'first refresh'
                ? DisplayRequestKind.read
                : stage == 'Operation'
                ? null
                : DisplayRequestKind.values.byName(stage);
            if (request.kind == target) {
              gate.entered.complete();
              await gate.release.future;
            }
            return ports.reply(request);
          };
          ports.operationHandler = (request) async {
            gate.entered.complete();
            await gate.release.future;
            return operationWire(request.metadata.context, revision: 2);
          };
          var notifications = 0;
          session.addListener(() => notifications++);
          // When the named activity crosses its first gated boundary.
          final pending = callActivity(session, stage);
          await gate.entered.future;
          // Then the activity has reserved busy and crossed its own exact port.
          expect(session.state.busy, isTrue);
          expect(
            stage == 'Operation' ? ports.operations.length : ports.calls.length,
            stage == 'query' || stage == 'Operation'
                ? 1
                : stage == 'first refresh'
                ? 4
                : 3,
          );
          // Given a raw call already started and its snapshot is retained.
          final retained = session.state;
          final count = ports.calls.length;
          final notified = notifications;
          // When the consumer disposes twice and then the port completes.
          session.dispose();
          session.dispose();
          gate.release.complete();
          await pending;
          // Then no late snapshot/notification or next Display call is published.
          expect(session.isDisposed, isTrue);
          expect(session.state, same(retained));
          expect(notifications, notified);
          expect(ports.calls, hasLength(count));
          expect(retained.busy, isTrue);
          expect(
            retained.committedRevisions['opaque:first'],
            stage == 'first refresh' ? 2 : null,
          );
        },
      );
    }

    for (final method in ['query', 'read', 'update', 'Operation']) {
      test('DS37 busy $method reentry fails before another port', () async {
        // Given a coherent session and the named activity's first reply held.
        final ports = RecordingPorts();
        final session = makeSession(ports);
        await loadActive(session);
        final gate = PortGate();
        ports.displayHandler = (request) async {
          if (request.kind.name == method) {
            gate.entered.complete();
            await gate.release.future;
          }
          return ports.reply(request);
        };
        ports.operationHandler = (request) async {
          gate.entered.complete();
          await gate.release.future;
          return operationWire(request.metadata.context);
        };
        // When the first named activity reserves and crosses its port.
        final first = callActivity(session, method);
        await gate.entered.future;
        // Then its busy snapshot is visible.
        expect(session.state.busy, isTrue);
        // Given the first activity remains pending.
        final retained = session.state;
        final displayCount = ports.calls.length;
        final operationCount = ports.operations.length;
        // When the same public activity is reentered.
        final reentered = callActivity(session, method);
        // Then it fails without altering the first activity or crossing another port.
        await expectLater(reentered, throwsStateError);
        expect(session.state, same(retained));
        expect(ports.calls, hasLength(displayCount));
        expect(ports.operations, hasLength(operationCount));
        // Given the first activity's valid producer reply becomes available.
        // When the held reply is released.
        gate.release.complete();
        await first;
        // Then the original activity can complete normally with only one command attempt.
        expect(session.state.busy, isFalse);
        expect(
          session.state.command.sequence,
          method == 'update' || method == 'Operation' ? 1 : 0,
        );
        session.dispose();
      });
    }

    test('DS38 first notification disposal prevents first raw call', () async {
      // Given a new session whose loading listener explicitly discards the flow.
      final ports = RecordingPorts();
      final session = makeSession(ports);
      session.addListener(session.dispose);
      // When query reserves busy and publishes its first notification.
      await session.query();
      // Then listener disposal suppresses the not-yet-started raw call.
      expect(session.isDisposed, isTrue);
      expect(ports.calls, isEmpty);
      expect(session.state.list.phase, DisplaySessionReadPhase.loading);
      expect(session.state.busy, isTrue);
    });

    test('DS38 first running notification reentry obeys busy', () async {
      // Given coherent projections and a listener that attempts one synchronous Save reentry.
      final ports = RecordingPorts();
      final session = makeSession(ports);
      await loadActive(session);
      Future<void>? assertion;
      session.addListener(() {
        if (session.state.command.phase == DisplaySessionCommandPhase.running &&
            assertion == null) {
          // Given the original command has already reserved this session.
          // When the running notification listener synchronously submits another Save.
          final reentered = session.update(observedRevision: 1, fields: []);
          // Then the listener's second command fails before another raw call.
          assertion = expectLater(reentered, throwsStateError);
        }
      });
      // When the original explicit command publishes running and then completes.
      await session.update(observedRevision: 1, fields: []);
      await assertion;
      // Then only the original command was dispatched and sequenced.
      expect(assertion, isNotNull);
      expect(session.state.command.sequence, 1);
      expect(
        ports.calls.where(
          (request) => request.kind == DisplayRequestKind.update,
        ),
        hasLength(1),
      );
      session.dispose();
    });

    test('DS39 invalid configured IDs have no eager side effects', () {
      // Given instrumented dependencies and each of the five configured string positions.
      final ports = RecordingPorts();
      var clockCalls = 0;
      for (final position in [
        'resourceType',
        'source',
        'component',
        'listScreen',
        'detailScreen',
      ]) {
        // Given the named configuration position contains only whitespace.
        // When construction attempts to validate that position.
        DisplaySession construct() => makeSession(
          ports,
          type: position == 'resourceType' ? ' ' : 'type',
          source: position == 'source' ? ' ' : 'source',
          component: position == 'component' ? ' ' : 'component',
          listScreen: position == 'listScreen' ? ' ' : 'collection',
          detailScreen: position == 'detailScreen' ? ' ' : 'detail',
          clock: () {
            clockCalls++;
            return DateTime.utc(2026, 10, 2);
          },
        );
        // Then it rejects locally with no clock or raw dependency effect.
        expect(construct, throwsArgumentError);
        expect(clockCalls, 0);
        expect(ports.calls, isEmpty);
      }
    });

    test('DS39 invalid method resource ID preserves state and ports', () async {
      // Given a coherent session with its accepted state retained.
      final ports = RecordingPorts();
      final session = makeSession(ports);
      await loadActive(session);
      final retained = session.state;
      // When read receives a whitespace-only opaque resource identifier.
      final attempt = session.read(' \n ');
      // Then the failed Future has no state or port effect.
      await expectLater(attempt, throwsArgumentError);
      expect(session.state, same(retained));
      expect(ports.calls, hasLength(2));
      session.dispose();
    });

    test('DS39 invalid operation ID preserves state and ports', () async {
      // Given a coherent active Detail eligible for an Operation.
      final ports = RecordingPorts();
      final session = makeSession(ports);
      await loadActive(session);
      final retained = session.state;
      // When Operation is invoked with a blank configured binding ID.
      final attempt = session.executeOperation(
        operationId: ' ',
        observedRevision: 1,
      );
      // Then argument rejection does not sequence or dispatch a command.
      await expectLater(attempt, throwsArgumentError);
      expect(session.state, same(retained));
      expect(ports.operations, isEmpty);
      session.dispose();
    });

    test('DS39 nonpositive caller revision preserves every command boundary', () async {
      // Given a coherent session and all three revision-bearing public methods.
      final ports = RecordingPorts();
      final session = makeSession(ports);
      await loadActive(session);
      final retained = session.state;
      for (final kind in ['update', 'delete', 'Operation']) {
        // Given the named method receives a nonpositive caller observation.
        // When that public method is explicitly invoked.
        final attempt = kind == 'update'
            ? session.update(observedRevision: 0, fields: [])
            : kind == 'delete'
            ? session.delete(observedRevision: -1)
            : session.executeOperation(
                operationId: 'advance',
                observedRevision: 0,
              );
        // Then it fails before sequencing, notification or raw dispatch.
        await expectLater(attempt, throwsArgumentError);
        expect(session.state, same(retained));
        expect(ports.calls, hasLength(2));
        expect(ports.operations, isEmpty);
      }
      session.dispose();
    });

    for (final method in ['query', 'read', 'update', 'Operation']) {
      test('DS40 unexpected raw $method exception remains visible', () async {
        // Given a coherent session with a historical settled unsupported command.
        final ports = RecordingPorts();
        final session = makeSession(ports);
        await loadActive(session);
        // When the public unsupported delete capability is explicitly attempted.
        await session.delete(observedRevision: 1);
        // Then it supplies command history for the later raw failure to preserve.
        expect(
          session.state.command.mutation!.outcome,
          DisplayCommandOutcome.unsupported,
        );
        final historical = session.state.command;
        ports.displayHandler = (request) async =>
            throw StateError('raw defect');
        ports.operationHandler = (request) async =>
            throw StateError('raw defect');
        // Given an unexpected exception is configured on the named raw boundary.
        // When that activity is explicitly attempted.
        await callActivity(session, method);
        // Then reads preserve command history while commands become uncertain failures.
        final command = method == 'update' || method == 'Operation';
        final failure = command
            ? session.state.command.failure
            : method == 'query'
            ? session.state.list.failure
            : session.state.detail.failure;
        expect(failure!.kind, DisplaySessionFailureKind.unexpected);
        expect(failure.message, contains('raw defect'));
        expect(session.state.commandUncertain, command);
        if (!command) {
          expect(session.state.command, same(historical));
        }
        expect(session.state.committedRevisions, isEmpty);
        session.dispose();
      });
    }

    test(
      'DS41 missing active Detail is a no-effect precondition failure',
      () async {
        // Given only a ready collection with no accepted Detail.
        final ports = RecordingPorts();
        final session = makeSession(ports);
        await loadList(session);
        final retained = session.state;
        // When a resource command attempts to infer an absent active resource.
        final attempt = session.update(observedRevision: 1, fields: []);
        // Then it fails locally without state or port change.
        await expectLater(attempt, throwsStateError);
        expect(session.state, same(retained));
        expect(ports.calls, hasLength(1));
        // Given there is still no accepted Detail to retry.
        // When retryDetail is explicitly attempted.
        final retry = session.retryDetail();
        // Then it likewise fails before any raw call or state effect.
        await expectLater(retry, throwsStateError);
        expect(session.state, same(retained));
        expect(ports.calls, hasLength(1));
        session.dispose();
      },
    );

    for (final variant in ['resource switch', 'mutation']) {
      test(
        'DS41 pending $variant is a no-effect precondition failure',
        () async {
          // Given coherent focus and an Operation that will establish a projection obligation.
          final ports = RecordingPorts();
          final session = makeSession(ports);
          await loadActive(session);
          ports.revision = 2;
          // When the separate Operation accepts a changed receipt.
          await session.executeOperation(
            operationId: 'advance',
            observedRevision: 1,
          );
          // Then pending is observable before any safe refresh.
          expect(session.state.projectionPending, isTrue);
          final retained = session.state;
          // Given the projection obligation is still outstanding.
          // When the named forbidden continuation is explicitly attempted.
          final attempt = variant == 'resource switch'
              ? session.read('opaque:other')
              : session.update(observedRevision: 1, fields: []);
          // Then it has exactly no raw or snapshot effect.
          await expectLater(attempt, throwsStateError);
          expect(session.state, same(retained));
          expect(ports.calls, hasLength(2));
          expect(ports.operations, hasLength(1));
          session.dispose();
        },
      );
    }

    test('DS41 disposed method is a no-effect precondition failure', () async {
      // Given a discarded fixed-flow session and its retained empty state.
      final ports = RecordingPorts();
      final session = makeSession(ports);
      session.dispose();
      final retained = session.state;
      // When the consumer tries to query the disposed instance.
      final attempt = session.query();
      // Then the failed Future cannot resume or mutate that instance.
      await expectLater(attempt, throwsStateError);
      expect(session.state, same(retained));
      expect(ports.calls, isEmpty);
    });

    test(
      'DS42 explicit new session after discard has its own empty fixed flow',
      () async {
        // Given an accepted old flow that the framework explicitly discards.
        final oldPorts = RecordingPorts();
        final old = makeSession(oldPorts, context: baseContext(assigned: true));
        await loadActive(old);
        old.dispose();
        final ports = RecordingPorts();
        final initial = baseContext(flow: 'fresh-flow');
        // When the framework constructs a new session from a separate supplied context.
        final fresh = makeSession(ports, context: initial);
        // Then no command, focus, revision or old assignment is inherited.
        expect(fresh.flowId, 'fresh-flow');
        expect(fresh.state.context, initial);
        expect(fresh.state.selectedResourceId, isNull);
        expect(fresh.state.command.sequence, 0);
        expect(fresh.state.minimumRevisions, isEmpty);
        expect(fresh.state.list.data, isNull);
        expect(ports.calls, isEmpty);
        // Given the original instance remains disposed.
        final retained = old.state;
        // When an old-flow query is attempted.
        final resume = old.query();
        // Then it cannot resume or publish and does not affect the fresh instance.
        await expectLater(resume, throwsStateError);
        expect(old.state, same(retained));
        expect(fresh.state.minimumRevisions, isEmpty);
        // Given the fresh independent instance is explicitly queried.
        // When its own first collection request is dispatched.
        await fresh.query();
        // Then only its own fixed context crosses the new port.
        expect(ports.calls.single.metadata.context, initial);
        expect(oldPorts.calls, hasLength(2));
        fresh.dispose();
      },
    );

    for (final kind in [
      DisplaySessionCommandKind.create,
      DisplaySessionCommandKind.delete,
    ]) {
      for (final outcome in [
        DisplayCommandOutcome.changed,
        DisplayCommandOutcome.noOp,
        DisplayCommandOutcome.conflict,
      ]) {
        test(
          'DS43 unexpected ${kind.name} ${outcome.name} is uncertain prototype failure',
          () async {
            // Given coherent projections and an unexpected success/conflict for a bounded capability.
            final ports = RecordingPorts();
            final session = makeSession(ports);
            await loadActive(session);
            final previous = session.state.detail.data;
            ports.displayHandler = (request) async => mutationWire(
              request.metadata.context,
              outcome: outcome,
              revision: 2,
            );
            // When the named create/delete port returns that decoded but forbidden receipt.
            if (kind == DisplaySessionCommandKind.create) {
              await session.create(fields: []);
            } else {
              await session.delete(observedRevision: 1);
            }
            // Then it is visible codec/contract uncertainty without invented receipt or reload.
            expect(
              session.state.command.failure!.kind,
              DisplaySessionFailureKind.codec,
            );
            expect(
              session.state.command.phase,
              DisplaySessionCommandPhase.failed,
            );
            expect(session.state.command.mutation, isNull);
            expect(session.state.commandUncertain, isTrue);
            expect(session.state.projectionPending, isTrue);
            expect(session.state.detail.data, same(previous));
            expect(session.state.committedRevisions, isEmpty);
            expect(session.state.minimumRevisions['opaque:first'], 1);
            expect(ports.calls, hasLength(3));
            session.dispose();
          },
        );
      }
    }
  });
}

final class PortGate {
  final entered = Completer<void>();
  final release = Completer<void>();
}

final class RecordingPorts
    implements DisplayTransport, OrdinaryOperationTransport {
  final List<DisplayRequest> calls = [];
  final List<OrdinaryOperationRequest> operations = [];
  Future<Map<String, Object?>> Function(DisplayRequest)? displayHandler;
  Future<Map<String, Object?>> Function(OrdinaryOperationRequest)?
  operationHandler;
  int revision = 1;

  Map<String, Object?> reply(
    DisplayRequest request, {
    PresentationContext? context,
  }) {
    final continued = context ?? request.metadata.context;
    return switch (request.kind) {
      DisplayRequestKind.query => listWire(continued, revision: revision),
      DisplayRequestKind.read => detailWire(
        continued,
        id: (request as DisplayReadRequest).resourceId,
        revision: revision,
      ),
      DisplayRequestKind.update => mutationWire(
        continued,
        revision: revision,
        includedRevision: revision,
      ),
      DisplayRequestKind.create => mutationWire(
        continued,
        outcome: DisplayCommandOutcome.unsupported,
        revision: null,
        resourceId: 'unsupported:create',
      ),
      DisplayRequestKind.delete => mutationWire(
        continued,
        outcome: DisplayCommandOutcome.unsupported,
        revision: revision,
      ),
    };
  }

  Future<Map<String, Object?>> dispatch(DisplayRequest request) async {
    calls.add(request);
    return displayHandler == null
        ? reply(request)
        : await displayHandler!(request);
  }

  @override
  Future<Map<String, Object?>> query(DisplayQueryRequest request) =>
      dispatch(request);
  @override
  Future<Map<String, Object?>> read(DisplayReadRequest request) =>
      dispatch(request);
  @override
  Future<Map<String, Object?>> update(DisplayUpdateRequest request) =>
      dispatch(request);
  @override
  Future<Map<String, Object?>> create(DisplayCreateRequest request) =>
      dispatch(request);
  @override
  Future<Map<String, Object?>> delete(DisplayDeleteRequest request) =>
      dispatch(request);
  @override
  Future<Map<String, Object?>> execute(OrdinaryOperationRequest request) async {
    operations.add(request);
    return operationHandler == null
        ? operationWire(request.metadata.context, revision: revision)
        : await operationHandler!(request);
  }
}

DisplaySession makeSession(
  RecordingPorts ports, {
  PresentationContext? context,
  PresentationContextPolicy? policy,
  DateTime Function()? clock,
  String type = 'type',
  String source = 'source',
  String component = 'component',
  String listScreen = 'collection',
  String detailScreen = 'detail',
}) => DisplaySession(
  resourceType: type,
  sourceId: source,
  componentId: component,
  listScreenId: listScreen,
  detailScreenId: detailScreen,
  initialContext: context ?? baseContext(),
  contextPolicy: policy ?? contextPolicy(),
  displayTransport: ports,
  operationTransport: ports,
  nowUtc: clock ?? () => DateTime.utc(2026, 10, 2),
);

DisplaySession sourceSession(FixtureDisplaySource source) => DisplaySession(
  resourceType: 'type',
  sourceId: 'source',
  componentId: 'component',
  listScreenId: 'collection',
  detailScreenId: 'detail',
  initialContext: baseContext(),
  contextPolicy: contextPolicy(),
  displayTransport: source,
  operationTransport: FixtureOrdinaryOperationTransport(source: source),
  nowUtc: () => DateTime.utc(2026, 10, 2),
);

Future<void> loadList(DisplaySession session) async {
  // Given the caller's fixed flow has no conflicting activity.
  // When its collection is explicitly queried through the public session.
  await session.query();
  // Then setup has a successfully admitted ready collection.
  expect(session.state.list.phase, DisplaySessionReadPhase.ready);
}

Future<void> loadActive(DisplaySession session) async {
  await loadList(session);
  // Given the setup collection contains the opaque resource.
  // When that resource is explicitly read through the public session.
  await session.read('opaque:first');
  // Then setup has coherent active Detail and local command eligibility.
  expect(session.state.detail.phase, DisplaySessionReadPhase.ready);
  expect(session.state.canMutate, isTrue);
}

Future<void> callActivity(DisplaySession session, String method) =>
    switch (method) {
      'query' => session.query(),
      'read' => session.read('opaque:first'),
      'update' ||
      'first refresh' => session.update(observedRevision: 1, fields: []),
      'Operation' => session.executeOperation(
        operationId: 'advance',
        observedRevision: 1,
      ),
      _ => throw ArgumentError.value(method),
    };

PresentationContextPolicy contextPolicy({bool extension = false}) =>
    PresentationContextPolicy(
      allowedProducerIds: {'producer'},
      optionalExtensions: extension
          ? [
              PresentationExtensionSupport(
                namespace: 'extension',
                version: 1,
                producerId: 'producer',
              ),
            ]
          : [],
    );

PresentationContext baseContext({
  bool assigned = false,
  String flow = 'flow',
  String source = 'source',
  String component = 'component',
}) => PresentationContext(
  flowId: flow,
  sourceId: source,
  componentId: component,
  families: [
    PresentationContextFamily(
      namespace: 'textus.presentation.locale',
      version: 1,
      producerId: 'producer',
      isRequired: false,
      expiresAt: null,
      payload: LocalePresentationPayload(localeTag: 'en'),
    ),
    PresentationContextFamily(
      namespace: 'textus.presentation.correlation',
      version: 1,
      producerId: 'producer',
      isRequired: false,
      expiresAt: null,
      payload: CorrelationPresentationPayload(
        flowReference: flow,
        attemptReference: 'attempt-1',
      ),
    ),
    if (assigned)
      PresentationContextFamily(
        namespace: 'textus.presentation.arm',
        version: 1,
        producerId: 'producer',
        isRequired: true,
        expiresAt: null,
        payload: SuppliedArmPresentationPayload(
          namespace: 'presentation',
          presentationSet: 'resources',
          armId: 'supplied',
          definitionVersion: 1,
          assignmentReference: 'assignment',
        ),
      ),
  ],
);
PresentationContext contextWith(
  PresentationContext context, {
  String? flow,
  String? source,
  String? component,
  List<PresentationContextFamily>? families,
}) => PresentationContext(
  flowId: flow ?? context.flowId,
  sourceId: source ?? context.sourceId,
  componentId: component ?? context.componentId,
  families:
      families ??
      context.families
          .map(
            (family) =>
                flow != null && family.payload is CorrelationPresentationPayload
                ? familyCopy(
                    family,
                    payload: CorrelationPresentationPayload(
                      flowReference: flow,
                      attemptReference:
                          (family.payload as CorrelationPresentationPayload)
                              .attemptReference,
                    ),
                  )
                : family,
          )
          .toList(),
);
PresentationContextFamily familyCopy(
  PresentationContextFamily family, {
  String? producer,
  int? version,
  DateTime? expiresAt,
  PresentationContextPayload? payload,
}) => PresentationContextFamily(
  namespace: family.namespace,
  version: version ?? family.version,
  producerId: producer ?? family.producerId,
  isRequired: family.isRequired,
  expiresAt: expiresAt ?? family.expiresAt,
  payload: payload ?? family.payload,
);
PresentationContext replaceFamily(
  PresentationContext context,
  PresentationContextFamily replacement,
) => contextWith(
  context,
  families: context.families
      .map(
        (family) =>
            family.namespace == replacement.namespace ? replacement : family,
      )
      .toList(),
);
PresentationContextFamily unknownFamily({
  bool required = false,
  Map<String, Object?> values = const {'unknown': true},
}) => PresentationContextFamily(
  namespace: 'extension',
  version: 1,
  producerId: 'producer',
  isRequired: required,
  expiresAt: null,
  payload: OpaquePresentationPayload(values),
);
PresentationContext optionalContext(String variant) {
  final initial = baseContext();
  return switch (variant) {
    'expired' => replaceFamily(
      initial,
      familyCopy(initial.families.first, expiresAt: DateTime.utc(2026, 10, 1)),
    ),
    'unsupported-version' => replaceFamily(
      initial,
      familyCopy(
        initial.families.first,
        version: 2,
        payload: OpaquePresentationPayload({'future': true}),
      ),
    ),
    'unknown-family' => contextWith(
      initial,
      families: [...initial.families, unknownFamily()],
    ),
    _ => throw ArgumentError.value(variant),
  };
}

PresentationContext incompatibleContext(
  PresentationContext initial,
  String variant,
) => switch (variant) {
  'assignment' => replaceFamily(
    initial,
    familyCopy(
      initial.families.last,
      payload: SuppliedArmPresentationPayload(
        namespace: 'presentation',
        presentationSet: 'resources',
        armId: 'supplied',
        definitionVersion: 1,
        assignmentReference: 'other-assignment',
      ),
    ),
  ),
  'locale' => replaceFamily(
    initial,
    familyCopy(
      initial.families.first,
      payload: LocalePresentationPayload(localeTag: 'ja'),
    ),
  ),
  'flow' => contextWith(initial, flow: 'other-flow'),
  'source' => contextWith(initial, source: 'other-source'),
  'component' => contextWith(initial, component: 'other-component'),
  'new-family' => contextWith(
    initial,
    families: [...initial.families, unknownFamily()],
  ),
  'expiry metadata' => replaceFamily(
    initial,
    familyCopy(initial.families.last, expiresAt: DateTime.utc(2026, 10, 3)),
  ),
  _ => throw ArgumentError.value(variant),
};
PresentationContext withAttempt(PresentationContext context, String attempt) =>
    contextWith(
      context,
      families: context.families
          .map(
            (family) => family.payload is CorrelationPresentationPayload
                ? familyCopy(
                    family,
                    payload: CorrelationPresentationPayload(
                      flowReference: context.flowId,
                      attemptReference: attempt,
                    ),
                  )
                : family,
          )
          .toList(),
    );
String attemptOf(PresentationContext context) =>
    (context.families
                .singleWhere(
                  (family) => family.payload is CorrelationPresentationPayload,
                )
                .payload
            as CorrelationPresentationPayload)
        .attemptReference;

DisplayFieldInput input(String fieldId, String text) => DisplayFieldInput(
  locator: DisplayFieldLocator(
    screenId: 'detail',
    sectionId: 'body',
    fieldId: fieldId,
  ),
  value: TextDisplayValue(text),
);
DisplayValue valueOf(DisplayDetailData detail, String id) => detail
    .model
    .sections
    .single
    .fields
    .singleWhere((field) => field.id == id)
    .value;
List<DisplayField> projectedFields({String title = 'Original'}) => [
  DisplayField(
    id: 'name',
    label: 'Name',
    role: 'title',
    value: TextDisplayValue(title),
  ),
  DisplayField(
    id: 'status',
    label: 'State',
    role: 'status',
    value: const TextDisplayValue('Ready'),
  ),
  DisplayField(
    id: 'note',
    label: 'Note',
    role: 'description',
    value: const TextDisplayValue('Note'),
  ),
  DisplayField(
    id: 'count',
    label: 'Count',
    role: 'number',
    value: NumberDisplayValue(7),
  ),
  DisplayField(
    id: 'flag',
    label: 'Flag',
    role: 'flag',
    value: const BoolDisplayValue(true),
  ),
  DisplayField(
    id: 'time',
    label: 'Time',
    role: 'time',
    value: TimestampDisplayValue(DateTime.utc(2026, 10, 2)),
  ),
  DisplayField(
    id: 'absent',
    label: 'Absent',
    role: 'optional',
    value: const MissingDisplayValue(),
  ),
];
DisplayDetailData detailData(
  PresentationContext context, {
  int revision = 1,
  String id = 'opaque:first',
  String screen = 'detail',
}) {
  final fields = projectedFields();
  return DisplayDetailData(
    resourceId: id,
    sourceRevision: revision,
    provenance: DisplayProvenance(
      producerId: 'detail-producer',
      sourceId: context.sourceId,
      revision: revision.toString(),
    ),
    bindings: fields
        .map(
          (field) => DisplayEditBinding(
            locator: DisplayFieldLocator(
              screenId: screen,
              sectionId: 'body',
              fieldId: field.id,
            ),
            writable: field.id == 'name' || field.id == 'note',
            inputValue: field.id == 'name' || field.id == 'note'
                ? field.value
                : const MissingDisplayValue(),
            requiredNonBlank: field.id == 'name',
          ),
        )
        .toList(),
    model: DisplayDetailModel(
      screenId: screen,
      title: 'Resource',
      sections: [DisplaySection(id: 'body', fields: fields)],
      actions: [DisplayAction(id: 'advance', label: 'Advance', enabled: false)],
    ),
  );
}

Map<String, Object?> detailWire(
  PresentationContext context, {
  int revision = 1,
  String id = 'opaque:first',
  String screen = 'detail',
}) => DisplayDetailResponse(
  context: context,
  data: detailData(context, revision: revision, id: id, screen: screen),
).toJson();
Map<String, Object?> listWire(
  PresentationContext context, {
  int revision = 1,
  String type = 'type',
  String screen = 'collection',
  String detailScreen = 'detail',
}) => DisplayListResponse(
  context: context,
  data: DisplayListData(
    resourceType: type,
    snapshotId: 'non-numeric-snapshot',
    provenance: DisplayProvenance(
      producerId: 'list-producer',
      sourceId: context.sourceId,
      revision: 'non-numeric-snapshot',
    ),
    model: DisplayListModel(
      screenId: screen,
      title: 'Collection',
      detailScreenId: detailScreen,
      items: [
        DisplayResourceSummary(
          resourceId: 'opaque:first',
          sourceRevision: revision,
          fields: [projectedFields().first],
        ),
        DisplayResourceSummary(
          resourceId: 'opaque:other',
          sourceRevision: 4,
          fields: [projectedFields(title: 'Other').first],
        ),
      ],
    ),
  ),
).toJson();
DisplayMutationResult mutationResult({
  DisplayCommandOutcome outcome = DisplayCommandOutcome.changed,
  int? revision = 1,
  String resourceId = 'opaque:first',
  List<DisplayFieldError> errors = const [],
  DisplayDetailData? display,
}) => DisplayMutationResult(
  resourceId: resourceId,
  outcome: outcome,
  currentRevision: revision,
  committedRevision: outcome == DisplayCommandOutcome.changed ? revision : null,
  fieldErrors: errors,
  message: 'receipt message',
  display: display,
);
Map<String, Object?> mutationWire(
  PresentationContext context, {
  DisplayCommandOutcome outcome = DisplayCommandOutcome.changed,
  int? revision = 1,
  int? includedRevision,
  String resourceId = 'opaque:first',
  List<DisplayFieldError> errors = const [],
}) => DisplayMutationResponse(
  context: context,
  result: mutationResult(
    outcome: outcome,
    revision: revision,
    resourceId: resourceId,
    errors: errors,
    display: includedRevision == null
        ? null
        : detailData(context, revision: includedRevision, id: resourceId),
  ),
).toJson();
Map<String, Object?> operationWire(
  PresentationContext context, {
  DisplayCommandOutcome outcome = DisplayCommandOutcome.changed,
  int revision = 1,
  String resourceId = 'opaque:first',
}) => OrdinaryOperationResponse(
  context: context,
  result: DisplayOperationResult(
    resourceId: resourceId,
    outcome: outcome,
    currentRevision: revision,
    committedRevision: outcome == DisplayCommandOutcome.changed
        ? revision
        : null,
    fieldErrors: [],
    message: 'operation message',
  ),
).toJson();

FixtureDisplaySource semanticSource() {
  final context = baseContext();
  final fields = projectedFields().take(4).toList();
  final detail = DisplayDetailResponse(
    context: context,
    data: DisplayDetailData(
      resourceId: 'template',
      sourceRevision: 1,
      provenance: DisplayProvenance(
        producerId: 'detail-producer',
        sourceId: 'source',
        revision: '1',
      ),
      bindings: [],
      model: DisplayDetailModel(
        screenId: 'detail',
        title: 'Resource',
        sections: [DisplaySection(id: 'body', fields: fields)],
        actions: [
          DisplayAction(id: 'advance', label: 'Advance', enabled: false),
        ],
      ),
    ),
  );
  final fixture = DisplayPrototypeFixture.fromJson({
    'schema': 'textus.display.fixture.v1',
    'reference': {
      'sampleId': 'source',
      'sampleRevision': 1,
      'provisionalVersion': 1,
      'developmentOnly': true,
    },
    'resourceType': 'type',
    'contexts': {'neutral': context.toJson()},
    'displayResponses': {'rows': listWire(context), 'entry': detail.toJson()},
    'operationResponses': <String, Object?>{},
    'semanticSeed': [
      {
        'resourceId': 'opaque:first',
        'sourceRevision': 1,
        'fields': {
          'name': const TextDisplayValue('Original').toJson(),
          'note': const TextDisplayValue('Note').toJson(),
          'state': const TextDisplayValue('ready').toJson(),
          'count': NumberDisplayValue(7).toJson(),
        },
      },
      {
        'resourceId': 'opaque:other',
        'sourceRevision': 4,
        'fields': {
          'name': const TextDisplayValue('Other').toJson(),
          'note': const TextDisplayValue('Other note').toJson(),
          'state': const TextDisplayValue('done').toJson(),
          'count': NumberDisplayValue(8).toJson(),
        },
      },
    ],
    'projectionBindings': {
      'screenId': 'detail',
      'sectionId': 'body',
      'fields': [
        {
          'fieldId': 'name',
          'semanticField': 'name',
          'writable': true,
          'requiredNonBlank': true,
        },
        {
          'fieldId': 'status',
          'semanticField': 'state',
          'writable': false,
          'requiredNonBlank': false,
          'lookup': {'ready': 'Ready', 'done': 'Done'},
        },
        {
          'fieldId': 'note',
          'semanticField': 'note',
          'writable': true,
          'requiredNonBlank': false,
        },
        {
          'fieldId': 'count',
          'semanticField': 'count',
          'writable': false,
          'requiredNonBlank': false,
        },
      ],
    },
    'operationBindings': {
      'advance': {
        'developmentOnly': true,
        'inputFields': ['resourceId'],
        'expected': {'state': 'ready'},
        'transition': {'state': 'done'},
      },
    },
  });
  return FixtureDisplaySource(
    fixture: fixture,
    listTemplateId: 'rows',
    detailTemplateId: 'entry',
    componentId: 'component',
    contextPolicy: contextPolicy(),
    nowUtc: () => DateTime.utc(2026, 10, 2),
  );
}
