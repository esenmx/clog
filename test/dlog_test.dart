library dlog_test;

import 'dart:async';

import 'package:dlog/dlog.dart';
import 'package:test/test.dart';

void main() {
  final hierarchicalLoggingEnabledDefault = hierarchicalLoggingEnabled;

  test('levels are comparable', () {
    final unsorted = [
      Level.error,
      Level.info,
      Level.off,
      Level.debug,
      Level.warn,
      Level.trace,
      Level.wtf,
    ];

    const sorted = Level.values;

    expect(unsorted, isNot(orderedEquals(sorted)));

    unsorted.sort();
    expect(unsorted, orderedEquals(sorted));
  });

  test('logger name cannot start with a "." ', () {
    expect(() => Logger('.c'), throwsArgumentError);
  });

  test('logger name cannot end with a "."', () {
    expect(() => Logger('a.'), throwsArgumentError);
    expect(() => Logger('a..d'), throwsArgumentError);
  });

  test('root level has proper defaults', () {
    expect(Logger.root, isNotNull);
    expect(Logger.root.parent, null);
    expect(Logger.root.level, defaultLevel);
  });

  test('logger naming is hierarchical', () {
    final c = Logger('a.b.c');
    expect(c.name, equals('c'));
    expect(c.parent!.name, equals('b'));
    expect(c.parent!.parent!.name, equals('a'));
    expect(c.parent!.parent!.parent!.name, equals(''));
    expect(c.parent!.parent!.parent!.parent, isNull);
  });

  test('logger full name', () {
    final c = Logger('a.b.c');
    expect(c.fullName, equals('a.b.c'));
    expect(c.parent!.fullName, equals('a.b'));
    expect(c.parent!.parent!.fullName, equals('a'));
    expect(c.parent!.parent!.parent!.fullName, equals(''));
    expect(c.parent!.parent!.parent!.parent, isNull);
  });

  test('logger parent-child links are correct', () {
    final a = Logger('a');
    final b = Logger('a.b');
    final c = Logger('a.c');
    expect(a, same(b.parent));
    expect(a, same(c.parent));
    expect(a.children['b'], same(b));
    expect(a.children['c'], same(c));
  });

  test('loggers are singletons', () {
    final a1 = Logger('a');
    final a2 = Logger('a');
    final b = Logger('a.b');
    final root = Logger.root;
    expect(a1, same(a2));
    expect(a1, same(b.parent));
    expect(root, same(a1.parent));
    expect(root, same(Logger('')));
  });

  test('cannot directly manipulate Logger.children', () {
    final loggerAB = Logger('a.b');
    final loggerA = loggerAB.parent!;

    expect(loggerA.children['b'], same(loggerAB), reason: 'can read Children');

    expect(() {
      loggerAB.children['test'] = Logger('Fake1234');
    }, throwsUnsupportedError, reason: 'Children is read-only');
  });

  test('stackTrace gets throw to LogRecord', () {
    Logger.root.level = Level.info;

    final records = <LogRecord>[];

    final sub = Logger.root.onRecord.listen(records.add);

    try {
      throw UnsupportedError('test exception');
    } catch (error, stack) {
      Logger.root.log(Level.error, 'error', error, stack);
      Logger.root.w('warn', error, stack);
    }

    Logger.root.log(Level.wtf, 'wtf');

    sub.cancel();

    expect(records, hasLength(3));

    final error = records[0];
    expect(error.message, 'error');
    expect(error.error is UnsupportedError, isTrue);
    expect(error.stackTrace is StackTrace, isTrue);

    final warn = records[1];
    expect(warn.message, 'warn');
    expect(warn.error is UnsupportedError, isTrue);
    expect(warn.stackTrace is StackTrace, isTrue);

    final wtf = records[2];
    expect(wtf.message, 'wtf');
    expect(wtf.error, isNull);
    expect(wtf.stackTrace, isNull);
  });

  group('zone gets recorded to LogRecord', () {
    test('root zone', () {
      final root = Logger.root;

      final recordingZone = Zone.current;
      final records = <LogRecord>[];
      root.onRecord.listen(records.add);
      root.i('hello');

      expect(records, hasLength(1));
      expect(records.first.zone, equals(recordingZone));
    });

    test('child zone', () {
      final root = Logger.root;

      late Zone recordingZone;
      final records = <LogRecord>[];
      root.onRecord.listen(records.add);

      runZoned(() {
        recordingZone = Zone.current;
        root.i('hello');
      });

      expect(records, hasLength(1));
      expect(records.first.zone, equals(recordingZone));
    });

    test('custom zone', () {
      final root = Logger.root;

      late Zone recordingZone;
      final records = <LogRecord>[];
      root.onRecord.listen(records.add);

      runZoned(() {
        recordingZone = Zone.current;
      });

      runZoned(() => root.log(Level.info, 'hello', null, null, recordingZone));

      expect(records, hasLength(1));
      expect(records.first.zone, equals(recordingZone));
    });
  });

  group('detached loggers', () {
    tearDown(() {
      hierarchicalLoggingEnabled = hierarchicalLoggingEnabledDefault;
      Logger.root.level = defaultLevel;
    });

    test('create new instances of Logger', () {
      final a1 = Logger.detached('a');
      final a2 = Logger.detached('a');
      final a = Logger('a');

      expect(a1, isNot(a2));
      expect(a1, isNot(a));
      expect(a2, isNot(a));
    });

    test('parent is null', () {
      final a = Logger.detached('a');
      expect(a.parent, null);
    });

    test('children is empty', () {
      final a = Logger.detached('a');
      expect(a.children, {});
    });

    test('have levels independent of the root level', () {
      void testDetachedLoggerLevel(bool withHierarchy) {
        hierarchicalLoggingEnabled = withHierarchy;

        const newRootLevel = Level.trace;
        const newDetachedLevel = Level.off;

        Logger.root.level = newRootLevel;

        final detached = Logger.detached('a');
        expect(detached.level, defaultLevel);
        expect(Logger.root.level, newRootLevel);

        detached.level = newDetachedLevel;
        expect(detached.level, newDetachedLevel);
        expect(Logger.root.level, newRootLevel);
      }

      testDetachedLoggerLevel(false);
      testDetachedLoggerLevel(true);
    });

    test('log messages regardless of hierarchy', () {
      void testDetachedLoggerOnRecord(bool withHierarchy) {
        var calls = 0;
        void handler(_) => calls += 1;

        hierarchicalLoggingEnabled = withHierarchy;

        final detached = Logger.detached('a');
        detached.level = Level.trace;
        detached.onRecord.listen(handler);

        Logger.root.i('foo');
        expect(calls, 0);

        detached.i('foo');
        detached.i('foo');
        expect(calls, 2);
      }

      testDetachedLoggerOnRecord(false);
      testDetachedLoggerOnRecord(true);
    });
  });

  group('mutating levels', () {
    final root = Logger.root;
    final a = Logger('a');
    final b = Logger('a.b');
    final c = Logger('a.b.c');
    final d = Logger('a.b.c.d');
    final e = Logger('a.b.c.d.e');

    setUp(() {
      hierarchicalLoggingEnabled = true;
      root.level = Level.info;
      a.level = null;
      b.level = null;
      c.level = null;
      d.level = null;
      e.level = null;
      root.clearListeners();
      a.clearListeners();
      b.clearListeners();
      c.clearListeners();
      d.clearListeners();
      e.clearListeners();
      hierarchicalLoggingEnabled = false;
      root.level = Level.info;
    });

    test('cannot set level if hierarchy is disabled', () {
      expect(() => a.level = Level.info, throwsUnsupportedError);
    });

    test('cannot set the level to null on the root logger', () {
      expect(() => root.level = null, throwsUnsupportedError);
    });

    test('cannot set the level to null on a detached logger', () {
      expect(() => Logger.detached('l').level = null, throwsUnsupportedError);
    });

    test('loggers effective level - no hierarchy', () {
      expect(root.level, equals(Level.info));
      expect(a.level, equals(Level.info));
      expect(b.level, equals(Level.info));

      root.level = Level.off;

      expect(root.level, equals(Level.off));
      expect(a.level, equals(Level.off));
      expect(b.level, equals(Level.off));
    });

    test('loggers effective level - with hierarchy', () {
      hierarchicalLoggingEnabled = true;
      expect(root.level, equals(Level.info));
      expect(a.level, equals(Level.info));
      expect(b.level, equals(Level.info));
      expect(c.level, equals(Level.info));

      root.level = Level.off;
      b.level = Level.info;

      expect(root.level, equals(Level.off));
      expect(a.level, equals(Level.off));
      expect(b.level, equals(Level.info));
      expect(c.level, equals(Level.info));
    });

    test('loggers effective level - with changing hierarchy', () {
      hierarchicalLoggingEnabled = true;
      d.level = Level.off;
      hierarchicalLoggingEnabled = false;

      expect(root.level, Level.info);
      expect(d.level, root.level);
      expect(e.level, root.level);
    });

    test('isLoggable is appropriate', () {
      hierarchicalLoggingEnabled = true;
      root.level = Level.wtf;
      c.level = Level.trace;
      e.level = Level.off;

      expect(root.isLoggable(Level.off), isTrue);
      expect(root.isLoggable(Level.wtf), isTrue);
      expect(root.isLoggable(Level.warn), isFalse);
      expect(c.isLoggable(Level.trace), isTrue);
      expect(c.isLoggable(Level.info), isTrue);
      expect(e.isLoggable(Level.wtf), isFalse);
    });

    test('add/remove handlers - no hierarchy', () {
      var calls = 0;
      void handler(_) {
        calls++;
      }

      final sub = c.onRecord.listen(handler);
      root.i('foo');
      root.i('foo');
      expect(calls, equals(2));
      sub.cancel();
      root.i('foo');
      expect(calls, equals(2));
    });

    test('add/remove handlers - with hierarchy', () {
      hierarchicalLoggingEnabled = true;
      var calls = 0;
      void handler(_) {
        calls++;
      }

      c.onRecord.listen(handler);
      root.i('foo');
      root.i('foo');
      expect(calls, equals(0));
    });

    test('logging methods store exception', () {
      root.level = Level.trace;
      final rootMessages = [];
      root.onRecord.listen((r) {
        rootMessages.add('${r.level.name}: ${r.message} ${r.error}');
      });

      root.t('1');
      root.d('2');
      root.i('3');
      root.w('4');
      root.e('5');
      root.wtf('6');
      root.t('1', 'a');
      root.d('2', 'b');
      root.i('3', ['c']);
      root.w('4', 'd');
      root.e('5', 'e');
      root.wtf('6', 'f');

      expect(
          rootMessages,
          equals([
            'trace: 1 null',
            'debug: 2 null',
            'info: 3 null',
            'warn: 4 null',
            'error: 5 null',
            'wtf: 6 null',
            'trace: 1 a',
            'debug: 2 b',
            'info: 3 [c]',
            'warn: 4 d',
            'error: 5 e',
            'wtf: 6 f',
          ]));
    });

    test('message logging - no hierarchy', () {
      root.level = Level.warn;
      final rootMessages = [];
      final aMessages = [];
      final cMessages = [];
      c.onRecord.listen((record) {
        cMessages.add('${record.level.name}: ${record.message}');
      });
      a.onRecord.listen((record) {
        aMessages.add('${record.level.name}: ${record.message}');
      });
      root.onRecord.listen((record) {
        rootMessages.add('${record.level.name}: ${record.message}');
      });

      root.i('1');
      root.i('2');
      root.wtf('3');

      b.i('4');
      b.e('5');
      b.w('6');
      b.i('7');

      c.i('8');
      c.w('9');
      c.wtf('10');

      expect(
          rootMessages,
          equals([
            // 'info: 1' is not loggable
            // 'info: 2' is not loggable
            'wtf: 3',
            // 'info: 4' is not loggable
            'error: 5',
            'warn: 6',
            // 'info: 7' is not loggable
            // 'info: 8' is not loggable
            'warn: 9',
            'wtf: 10'
          ]));

      // no hierarchy means we all hear the same thing.
      expect(aMessages, equals(rootMessages));
      expect(cMessages, equals(rootMessages));
    });

    test('message logging - with hierarchy', () {
      hierarchicalLoggingEnabled = true;

      b.level = Level.warn;

      final rootMessages = [];
      final aMessages = [];
      final cMessages = [];
      c.onRecord.listen((record) {
        cMessages.add('${record.level.name}: ${record.message}');
      });
      a.onRecord.listen((record) {
        aMessages.add('${record.level.name}: ${record.message}');
      });
      root.onRecord.listen((record) {
        rootMessages.add('${record.level.name}: ${record.message}');
      });

      root.i('1');
      root.i('2');
      root.wtf('3');

      b.i('4');
      b.e('5');
      b.w('6');
      b.i('7');

      c.i('8');
      c.w('9');
      c.wtf('10');

      expect(
          rootMessages,
          equals([
            'info: 1',
            'info: 2',
            'wtf: 3',
            // 'info: 4' is not loggable
            'error: 5',
            'warn: 6',
            // 'info: 7' is not loggable
            // 'info: 8' is not loggable
            'warn: 9',
            'wtf: 10'
          ]));

      expect(
          aMessages,
          equals([
            // 1,2 and 3 are lower in the hierarchy
            // 'info: 4' is not loggable
            'error: 5',
            'warn: 6',
            // 'info: 7' is not loggable
            // 'info: 8' is not loggable
            'warn: 9',
            'wtf: 10'
          ]));

      expect(
          cMessages,
          equals([
            // 1 - 7 are lower in the hierarchy
            // 'info: 8' is not loggable
            'warn: 9',
            'wtf: 10'
          ]));
    });

    test('message logging - lazy functions', () {
      root.level = Level.info;
      final messages = [];
      root.onRecord.listen((record) {
        messages.add('${record.level.name}: ${record.message}');
      });

      var callCount = 0;
      String myClosure() => '${++callCount}';

      root.i(myClosure);
      root.d(myClosure); // Should not get evaluated.
      root.w(myClosure);

      expect(
          messages,
          equals([
            'info: 1',
            'warn: 2',
          ]));
    });

    test('message logging - calls toString', () {
      root.level = Level.info;
      final messages = [];
      final objects = [];
      final object = Object();
      root.onRecord.listen((record) {
        messages.add('${record.level.name}: ${record.message}');
        objects.add(record.object);
      });

      root.i(5);
      root.i(false);
      root.i([1, 2, 3]);
      root.i(() => 10);
      root.i(object);

      expect(
          messages,
          equals([
            'info: 5',
            'info: false',
            'info: [1, 2, 3]',
            'info: 10',
            "info: Instance of 'Object'"
          ]));

      expect(objects, [
        5,
        false,
        [1, 2, 3],
        10,
        object
      ]);
    });
  });

  group('recordStackTraceAtLevel', () {
    final root = Logger.root;
    tearDown(() {
      recordStackTraceAtLevel = Level.off;
      root.clearListeners();
    });

    test('no stack trace by default', () {
      final records = <LogRecord>[];
      root.onRecord.listen(records.add);
      root.e('hello');
      root.w('hello');
      root.i('hello');
      expect(records, hasLength(3));
      expect(records[0].stackTrace, isNull);
      expect(records[1].stackTrace, isNull);
      expect(records[2].stackTrace, isNull);
    });

    test('trace recorded only on requested levels', () {
      final records = <LogRecord>[];
      recordStackTraceAtLevel = Level.warn;
      root.onRecord.listen(records.add);
      root.e('hello');
      root.w('hello');
      root.i('hello');
      expect(records, hasLength(3));
      expect(records[0].stackTrace, isNotNull);
      expect(records[1].stackTrace, isNotNull);
      expect(records[2].stackTrace, isNull);
    });

    test('provided trace is used if given', () {
      final trace = StackTrace.current;
      final records = <LogRecord>[];
      recordStackTraceAtLevel = Level.warn;
      root.onRecord.listen(records.add);
      root.e('hello');
      root.w('hello', 'a', trace);
      expect(records, hasLength(2));
      expect(records[0].stackTrace, isNot(equals(trace)));
      expect(records[1].stackTrace, trace);
    });

    test('error also generated when generating a trace', () {
      final records = <LogRecord>[];
      recordStackTraceAtLevel = Level.warn;
      root.onRecord.listen(records.add);
      root.e('hello');
      root.w('hello');
      root.i('hello');
      expect(records, hasLength(3));
      expect(records[0].error, isNotNull);
      expect(records[1].error, isNotNull);
      expect(records[2].error, isNull);
    });
  });
}
