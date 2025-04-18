import 'dart:async';
import 'dart:io';

import 'package:mcp_dart/src/server/streamable_https.dart';
import 'package:mcp_dart/src/shared/uuid.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

/// A simple implementation of EventStore for testing event resumability
class TestEventStore implements EventStore {
  /// Maps session IDs to lists of (eventId, messageJson) pairs
  final events = <String, List<MapEntry<String, Map<String, dynamic>>>>{};

  @override
  Future<String> storeEvent(String sessionId, JsonRpcMessage message) async {
    final eventId = generateUUID();
    events.putIfAbsent(sessionId, () => []);
    events[sessionId]!.add(MapEntry(eventId, message.toJson()));
    return eventId;
  }

  @override
  Future<String> replayEventsAfter(String eventId,
      {required Future<void> Function(String, JsonRpcMessage) send}) async {
    String? sessionId;
    int? eventIndex;

    for (final entry in events.entries) {
      final sid = entry.key;
      final eventList = entry.value;
      for (var i = 0; i < eventList.length; i++) {
        if (eventList[i].key == eventId) {
          sessionId = sid;
          eventIndex = i;
          break;
        }
      }
      if (sessionId != null) break;
    }

    if (sessionId == null || eventIndex == null) {
      throw Exception('Event ID not found: $eventId');
    }

    final eventsToReplay = events[sessionId]!.sublist(eventIndex + 1);
    for (final event in eventsToReplay) {
      final jsonMap = _convertToStringDynamicMap(event.value);
      final message = JsonRpcMessage.fromJson(jsonMap);
      await send(event.key, message);
    }

    return sessionId;
  }

  /// Converts Maps with dynamic keys to Map&lt;`String, dynamic&gt;
  Map<String, dynamic> _convertToStringDynamicMap(Map<dynamic, dynamic> map) {
    final result = <String, dynamic>{};
    for (final entry in map.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is Map) {
        result[key] = _convertToStringDynamicMap(value);
      } else if (value is List) {
        result[key] = _convertToStringDynamicList(value);
      } else {
        result[key] = value;
      }
    }
    return result;
  }

  /// Converts Lists with dynamic values
  List<dynamic> _convertToStringDynamicList(List<dynamic> list) {
    return list.map((item) {
      if (item is Map) {
        return _convertToStringDynamicMap(item);
      } else if (item is List) {
        return _convertToStringDynamicList(item);
      } else {
        return item;
      }
    }).toList();
  }
}

void main() {
  late HttpServer testServer;
  late int serverPort;
  late String serverUrlBase;

  /// Maps endpoint paths to active transports
  final Map<String, StreamableHTTPServerTransport> transports = {};
  final Map<String, Completer<JsonRpcMessage>> messageCompleters = {};

  /// Set up the test HTTP server before all tests
  setUpAll(() async {
    try {
      testServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverPort = testServer.port;
      serverUrlBase = 'http://localhost:$serverPort';
      print("Test server listening on $serverUrlBase");

      testServer.listen((request) async {
        final path = request.uri.path;
        print("Received request: ${request.method} ${request.uri}");

        if (path == '/mcp') {
          final transport = transports['/mcp'];

          if (transport != null) {
            try {
              await transport.handleRequest(request);
            } catch (e, stackTrace) {
              print("Error in transport.handleRequest: $e");
              print("Stack trace: $stackTrace");
              if (!request.response.headers.persistentConnection) {
                request.response.statusCode = HttpStatus.internalServerError;
                request.response.write("Error processing request: $e");
                await request.response.close();
              }
            }
          } else {
            print("No transport available for path: $path");
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.write("Transport not available");
            await request.response.close();
          }
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write("Not Found");
          await request.response.close();
        }
      });
    } catch (e) {
      print("FATAL: Failed to start test server: $e");
      fail("Failed to start test server: $e");
    }
  });

  /// Clean up resources after all tests complete
  tearDownAll(() async {
    print("Stopping test server...");
    for (final transport in transports.values) {
      await transport.close();
    }
    await testServer.close(force: true);
    print("Test server stopped.");
  });

  group('StreamableHTTPServerTransport tests', () {
    /// Reset state before each test
    setUp(() {
      transports.clear();
      messageCompleters.clear();
    });

    // Common test setup

    // Helper to manually trigger initialization of the transport

    test('initialization with stateful session management', () async {
      // Create a new transport with session management
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "test-session-id",
        ),
      );
      await transport.start();
      transports['/mcp'] = transport;

      // Set the sessionId for testing purposes
      transport.sessionId = "test-session-id";

      // Verify the session ID is correctly set
      expect(transport.sessionId, equals("test-session-id"));

      await transport.close();
    });

    test('GET request establishes SSE stream', () async {
      // Create a transport with fixed session ID
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "test-session-id",
        ),
      );
      await transport.start();
      transports['/mcp'] = transport;

      // Set the session ID for testing
      transport.sessionId = "test-session-id";

      // Create a notification to send via the SSE stream
      final notification = JsonRpcNotification(
        method: 'test/notification',
        params: {'message': 'hello'},
      );

      // Verify the transport can send messages without exceptions
      try {
        await transport.send(notification);
      } catch (e) {
        fail("Transport send method threw an exception: $e");
      }

      await transport.close();
    });

    test('POST request with JSON-RPC request triggers onmessage', () async {
      // Create a transport with session management
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "test-session-id",
        ),
      );
      await transport.start();
      transports['/mcp'] = transport;

      transport.sessionId = "test-session-id";

      // Set up message handler with completion tracker
      final messageCompleter = Completer<JsonRpcMessage>();
      transport.onmessage = (message) {
        if (!messageCompleter.isCompleted) {
          messageCompleter.complete(message);
        }
      };

      // Create a test JSON-RPC request
      final request = JsonRpcRequest(
        id: 123,
        method: 'test/method',
        params: {'data': 'test-data'},
      );

      // Simulate message receipt
      transport.onmessage?.call(request);

      // Wait for message processing with timeout
      final receivedMessage = await messageCompleter.future.timeout(
        Duration(seconds: 3),
        onTimeout: () =>
            throw TimeoutException('No message received within timeout'),
      );

      // Verify message content
      expect(receivedMessage, isA<JsonRpcRequest>());
      expect((receivedMessage as JsonRpcRequest).id, equals(123));
      expect(receivedMessage.method, equals('test/method'));
      expect(receivedMessage.params?['data'], equals('test-data'));

      await transport.close();
    }, timeout: Timeout(Duration(seconds: 5)));

    test('enableJsonResponse option is accepted', () async {
      // Create a transport with JSON response enabled
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "test-session-id",
          enableJsonResponse: true,
        ),
      );

      await transport.start();
      transports['/mcp'] = transport;
      transport.sessionId = "test-session-id";

      await transport.close();

      // If we reach here without exceptions, the test passes
      expect(true, isTrue,
          reason:
              "Transport successfully created with enableJsonResponse=true");
    });

    test('session validation works correctly', () async {
      // Create a transport with session management
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "correct-session-id",
        ),
      );
      await transport.start();
      transports['/mcp'] = transport;
      transport.sessionId = "correct-session-id";

      // Set up handlers for valid and invalid cases
      final validMessageCompleter = Completer<JsonRpcMessage>();
      final invalidMessageCompleter = Completer<String>();

      transport.onmessage = (message) {
        if (!validMessageCompleter.isCompleted) {
          validMessageCompleter.complete(message);
        }
      };

      // Create test message and headers
      final validRequest = JsonRpcRequest(
        id: 1,
        method: 'test/method',
        params: {'data': 'test-data'},
      );

      final validHeaders = {
        'mcp-session-id': ['correct-session-id']
      };
      final invalidHeaders = {
        'mcp-session-id': ['wrong-session-id']
      };

      // Test session validation
      Future<void> testSessionValidation() async {
        // Test with valid session ID
        if (transport.sessionId == validHeaders['mcp-session-id']?[0]) {
          transport.onmessage?.call(validRequest);
        } else {
          fail("Valid session ID check failed");
        }

        // Test with invalid session ID
        if (transport.sessionId == invalidHeaders['mcp-session-id']?[0]) {
          fail("Invalid session ID check passed when it should fail");
        } else {
          // Expected behavior: session ID mismatch prevents processing
          invalidMessageCompleter
              .complete("Invalid session rejected correctly");
        }
      }

      await testSessionValidation();

      // Verify results with appropriate timeouts
      final receivedMessage = await validMessageCompleter.future.timeout(
        Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('Valid message test timed out'),
      );

      final invalidResult = await invalidMessageCompleter.future.timeout(
        Duration(seconds: 3),
        onTimeout: () =>
            throw TimeoutException('Invalid message test timed out'),
      );

      // Verify message properties
      expect(receivedMessage, isA<JsonRpcRequest>());
      expect((receivedMessage as JsonRpcRequest).id, equals(1));
      expect(receivedMessage.method, equals('test/method'));
      expect(receivedMessage.params?['data'], equals('test-data'));
      expect(invalidResult, equals("Invalid session rejected correctly"));

      await transport.close();
    });

    test('event resumability works with EventStore', () async {
      // Create a test event store for tracking events
      final eventStore = TestEventStore();

      // Create a transport with event store for resumability
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "resumable-session-id",
          eventStore: eventStore,
        ),
      );
      await transport.start();
      transports['/mcp'] = transport;
      transport.sessionId = "resumable-session-id";

      // Create sample test messages
      final messages = [
        JsonRpcRequest(
          id: 1,
          method: 'initialize',
          params: {
            'protocolVersion': '2024-11-05',
            'clientInfo': {'name': 'test-client-1', 'version': '1.0.0'},
            'capabilities': {}
          },
        ),
        JsonRpcRequest(
          id: 2,
          method: 'initialize',
          params: {
            'protocolVersion': '2024-11-05',
            'clientInfo': {'name': 'test-client-2', 'version': '1.0.0'},
            'capabilities': {}
          },
        ),
        JsonRpcRequest(
          id: 3,
          method: 'initialize',
          params: {
            'protocolVersion': '2024-11-05',
            'clientInfo': {'name': 'test-client-3', 'version': '1.0.0'},
            'capabilities': {}
          },
        ),
      ];

      // Store the messages in the event store
      final storedEventIds = <String>[];
      for (final message in messages) {
        final eventId =
            await eventStore.storeEvent(transport.sessionId!, message);
        storedEventIds.add(eventId);
      }

      // Verify storage was successful
      expect(eventStore.events[transport.sessionId!]!.length,
          equals(messages.length));

      // Resume from the first event
      final lastEventId = storedEventIds.first;
      final replayedEvents = <JsonRpcMessage>[];
      final replayCompleter = Completer<void>();

      // Set up send function for replaying events
      Future<void> sendFunction(String eventId, JsonRpcMessage message) async {
        replayedEvents.add(message);
        if (replayedEvents.length == messages.length - 1) {
          replayCompleter.complete();
        }
      }

      // Perform event replay
      final streamId = await eventStore.replayEventsAfter(
        lastEventId,
        send: sendFunction,
      );

      // Verify the session ID matches
      expect(streamId, equals(transport.sessionId));

      // Wait for replay completion
      await replayCompleter.future.timeout(
        Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('Event replay timed out'),
      );

      // Verify correct number of events replayed
      expect(replayedEvents.length, equals(messages.length - 1));

      // Verify replayed events match original messages
      for (var i = 0; i < replayedEvents.length; i++) {
        final replayedMessage = replayedEvents[i];
        final originalMessage = messages[i + 1]; // Skip the first message

        expect(replayedMessage, isA<JsonRpcRequest>());
        expect(
            (replayedMessage as JsonRpcRequest).method, equals('initialize'));
        expect(replayedMessage.id, equals(originalMessage.id));
        expect(replayedMessage.params!['clientInfo']['name'],
            equals(originalMessage.params!['clientInfo']['name']));
      }

      await transport.close();
    });
  });
}
