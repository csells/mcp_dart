import 'dart:async';

import 'package:mcp_dart/src/server/server.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

class MockTransport extends Transport {
  final List<JsonRpcMessage> sentMessages = [];
  final List<JsonRpcMessage> receivedMessages = [];
  final StreamController<JsonRpcMessage> messageController =
      StreamController<JsonRpcMessage>.broadcast();
  bool isStarted = false;
  bool isClosed = false;
  ClientCapabilities? clientCapabilities;

  @override
  String? get sessionId => null;

  @override
  Future<void> close() async {
    isClosed = true;
    await messageController.close();
    onclose?.call();
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    if (isClosed) {
      throw StateError('Cannot send message on closed transport');
    }
    sentMessages.add(message);

    // Auto-respond to requests for testing purposes
    if (message is JsonRpcRequest) {
      final request = message;
      if (request.method == 'ping') {
        final response = JsonRpcResponse(id: request.id, result: {});
        if (onmessage != null) {
          onmessage!(response);
        }
      } else if (request.method == 'sampling/createMessage') {
        // Only respond if sampling capability is present
        if (clientCapabilities?.sampling != null) {
          final response = JsonRpcResponse(id: request.id, result: {
            'model': 'test-model',
            'role': 'assistant',
            'content': {'type': 'text', 'text': 'Test response'},
          });
          if (onmessage != null) {
            onmessage!(response);
          }
        }
        // Server will handle the error case itself
      } else if (request.method == 'roots/list') {
        // Only respond if roots capability is present
        if (clientCapabilities?.roots != null) {
          final response = JsonRpcResponse(id: request.id, result: {
            'roots': [
              {'uri': 'file:///path/to/root1'},
              {'uri': 'file:///path/to/root2'},
            ],
          });
          if (onmessage != null) {
            onmessage!(response);
          }
        }
        // Server will handle the error case itself
      }
    }
  }

  @override
  Future<void> start() async {
    if (isStarted) {
      throw StateError('Transport already started');
    }
    isStarted = true;
  }

  void receiveMessage(JsonRpcMessage message) {
    receivedMessages.add(message);

    // Store client capabilities from initialize request
    if (message is JsonRpcInitializeRequest) {
      clientCapabilities = message.initParams.capabilities;
    }

    messageController.add(message);
    onmessage?.call(message);
  }

  Stream<JsonRpcMessage> get messages => messageController.stream;
}

void main() {
  group('Server Tests', () {
    late Server server;
    late MockTransport transport;
    late Implementation serverInfo;

    setUp(() {
      serverInfo = const Implementation(name: 'TestServer', version: '1.0.0');
      server = Server(serverInfo);
      transport = MockTransport();
    });

    tearDown(() async {
      if (transport.isStarted && !transport.isClosed) {
        await transport.close();
      }
    });

    test('Server initialization with default options', () {
      expect(server.getCapabilities(), isNotNull);
      expect(server.getClientCapabilities(), isNull);
      expect(server.getClientVersion(), isNull);
    });

    test('Server initialization with custom options', () {
      final capabilities = ServerCapabilities(
        logging: {
          "supportedLevels": ["info", "error"]
        },
        tools: ServerCapabilitiesTools(),
      );
      final options = ServerOptions(
        capabilities: capabilities,
        instructions: 'Test instructions',
      );

      final customServer = Server(serverInfo, options: options);
      expect(customServer.getCapabilities().logging, isNotNull);
      expect(customServer.getCapabilities().tools, isNotNull);
    });

    test('Register capabilities before connecting', () {
      final newCapabilities = ServerCapabilities(
        prompts: ServerCapabilitiesPrompts(listChanged: true),
        resources:
            ServerCapabilitiesResources(subscribe: true, listChanged: true),
      );

      server.registerCapabilities(newCapabilities);

      final serverCapabilities = server.getCapabilities();
      expect(serverCapabilities.prompts?.listChanged, isTrue);
      expect(serverCapabilities.resources?.subscribe, isTrue);
      expect(serverCapabilities.resources?.listChanged, isTrue);
    });

    test('Cannot register capabilities after connecting to transport',
        () async {
      await server.connect(transport);

      final newCapabilities = ServerCapabilities(
        prompts: ServerCapabilitiesPrompts(listChanged: true),
      );

      expect(() => server.registerCapabilities(newCapabilities),
          throwsA(isA<StateError>()));
    });

    test('Handles initialize request correctly', () async {
      await server.connect(transport);

      bool initialized = false;
      server.oninitialized = () {
        initialized = true;
      };

      final clientCapabilities = ClientCapabilities(
        roots: ClientCapabilitiesRoots(),
        sampling: {},
      );

      final initParams = InitializeRequestParams(
        protocolVersion: latestProtocolVersion,
        capabilities: clientCapabilities,
        clientInfo: const Implementation(name: 'TestClient', version: '1.0.0'),
      );

      final initRequest = JsonRpcInitializeRequest(
        id: 1,
        initParams: initParams,
      );

      // Send initialize request to the server
      transport.receiveMessage(initRequest);

      // Wait for sent messages to be processed
      await Future.delayed(const Duration(milliseconds: 50));

      // Check that server responded with initialize result
      expect(transport.sentMessages.length, 1);
      expect(
          transport.sentMessages.first.runtimeType
              .toString()
              .contains('JsonRpcResponse'),
          isTrue);

      final response = transport.sentMessages.first as JsonRpcResponse;
      expect(response.id, 1);

      final result = response.result;
      expect(result['protocolVersion'], equals(latestProtocolVersion));
      expect(result['serverInfo']['name'], equals('TestServer'));
      expect(result['serverInfo']['version'], equals('1.0.0'));

      // Check client capabilities are stored
      expect(server.getClientCapabilities(), isNotNull);
      expect(server.getClientCapabilities()?.sampling, isNotNull);
      expect(server.getClientCapabilities()?.roots, isNotNull);

      // Check client version is stored
      expect(server.getClientVersion(), isNotNull);
      expect(server.getClientVersion()?.name, equals('TestClient'));

      // Send initialized notification
      final initializedNotif = JsonRpcInitializedNotification();
      transport.receiveMessage(initializedNotif);

      // Wait for notification to be processed
      await Future.delayed(const Duration(milliseconds: 50));

      // Check that oninitialized callback was called
      expect(initialized, isTrue);
    });

    test(
        'Falls back to latest protocol version if requested version is not supported',
        () async {
      await server.connect(transport);

      final clientCapabilities = ClientCapabilities();

      final initParams = InitializeRequestParams(
        protocolVersion: "999.999", // Unsupported version
        capabilities: clientCapabilities,
        clientInfo: const Implementation(name: 'TestClient', version: '1.0.0'),
      );

      final initRequest = JsonRpcInitializeRequest(
        id: 1,
        initParams: initParams,
      );

      // Send initialize request to the server
      transport.receiveMessage(initRequest);

      // Wait for sent messages to be processed
      await Future.delayed(const Duration(milliseconds: 50));

      final response = transport.sentMessages.first as JsonRpcResponse;
      final result = response.result;

      // Should fall back to latest version
      expect(result['protocolVersion'], isNot(equals("999.999")));
    });

    test('Can send ping requests to client', () async {
      await server.connect(transport);

      // Initialize client capabilities
      await _initializeClient(transport, server);

      // Send ping request
      final result = await server.ping();

      // Verify request was sent
      expect(
        transport.sentMessages
            .any((msg) => msg is JsonRpcRequest && msg.method == "ping"),
        isTrue,
      );

      // Verify response was received
      expect(result, isA<EmptyResult>());
    });

    test('Can send createMessage request when client has sampling capability',
        () async {
      await server.connect(transport);

      // Initialize with client capabilities including sampling
      await _initializeClient(transport, server, withSampling: true);

      // Create message params
      final createParams = CreateMessageRequestParams(
        messages: [
          SamplingMessage(
            role: SamplingMessageRole.user,
            content: SamplingTextContent(text: 'Test content'),
          )
        ],
        maxTokens: 100,
      );

      // Send create message request
      final result = await server.createMessage(createParams);

      // Verify request was sent
      expect(
        transport.sentMessages.any((msg) =>
            msg is JsonRpcRequest && msg.method == "sampling/createMessage"),
        isTrue,
      );

      // Verify response was processed correctly
      expect(result.role, equals(SamplingMessageRole.assistant));
      expect((result.content as SamplingTextContent).text,
          equals('Test response'));
    });

    test('Cannot send createMessage request without client sampling capability',
        () async {
      await server.connect(transport);

      // Initialize with client capabilities WITHOUT sampling
      await _initializeClient(transport, server, withSampling: false);

      // Attempt to send create message request should throw synchronously
      expect(() => server.assertCapabilityForMethod('sampling/createMessage'),
          throwsA(isA<McpError>()));
    });

    test('Can send listRoots request when client has roots capability',
        () async {
      await server.connect(transport);

      // Initialize with client capabilities including roots
      await _initializeClient(transport, server, withRoots: true);

      // Send listRoots request
      final result = await server.listRoots();

      // Verify request was sent
      expect(
        transport.sentMessages
            .any((msg) => msg is JsonRpcRequest && msg.method == "roots/list"),
        isTrue,
      );

      // Verify response was processed correctly
      expect(result.roots.length, equals(2));
      expect(result.roots[0].uri, equals('file:///path/to/root1'));
      expect(result.roots[1].uri, equals('file:///path/to/root2'));
    });

    test('Cannot send listRoots request without client roots capability',
        () async {
      await server.connect(transport);

      // Initialize with client capabilities WITHOUT roots
      await _initializeClient(transport, server, withRoots: false);

      // Attempt to check capability directly should throw
      expect(() => server.assertCapabilityForMethod('roots/list'),
          throwsA(isA<McpError>()));
    });

    test('Server can send resource notifications when capability is registered',
        () async {
      // Create server with resource capabilities
      final capabilities = ServerCapabilities(
        resources:
            ServerCapabilitiesResources(listChanged: true, subscribe: true),
      );
      final options = ServerOptions(capabilities: capabilities);
      final resourceServer = Server(serverInfo, options: options);

      await resourceServer.connect(transport);

      // Send resource list changed notification
      await resourceServer.sendResourceListChanged();

      // Send resource updated notification
      final resourceParams = ResourceUpdatedNotificationParams(
        uri: 'test-resource',
      );
      await resourceServer.sendResourceUpdated(resourceParams);

      // Check notifications were sent
      expect(
        transport.sentMessages.any((msg) =>
            msg is JsonRpcNotification &&
            msg.method == "notifications/resources/list_changed"),
        isTrue,
      );
      expect(
        transport.sentMessages.any((msg) =>
            msg is JsonRpcNotification &&
            msg.method == "notifications/resources/updated"),
        isTrue,
      );
    });

    test('Server cannot send notifications when capability is not registered',
        () {
      // Create server with NO capabilities
      final options = ServerOptions();
      final plainServer = Server(serverInfo, options: options);

      expect(() => plainServer.sendResourceListChanged(),
          throwsA(isA<StateError>()));

      final resourceParams = ResourceUpdatedNotificationParams(
        uri: 'test-resource',
      );
      expect(() => plainServer.sendResourceUpdated(resourceParams),
          throwsA(isA<StateError>()));
      expect(() => plainServer.sendPromptListChanged(),
          throwsA(isA<StateError>()));
      expect(
          () => plainServer.sendToolListChanged(), throwsA(isA<StateError>()));

      // Logging notification requires logging capability
      final logParams = LoggingMessageNotificationParams(
        level: LoggingLevel.info,
        data: 'Test log',
      );
      expect(() => plainServer.sendLoggingMessage(logParams),
          throwsA(isA<StateError>()));
    });

    test('Verify request handler capability assertions', () async {
      // Create server with only tools capability
      final capabilities = ServerCapabilities(
        tools: ServerCapabilitiesTools(),
      );
      final options = ServerOptions(capabilities: capabilities);
      final server = Server(serverInfo, options: options);

      // These should not throw - tools capability is registered
      server.assertRequestHandlerCapability('tools/call');
      server.assertRequestHandlerCapability('tools/list');

      // These should throw - no capability
      expect(() => server.assertRequestHandlerCapability('resources/list'),
          throwsA(isA<StateError>()));
      expect(() => server.assertRequestHandlerCapability('prompts/list'),
          throwsA(isA<StateError>()));
      expect(() => server.assertRequestHandlerCapability('logging/setLevel'),
          throwsA(isA<StateError>()));

      // Core methods should always be allowed
      server.assertRequestHandlerCapability('initialize');
      server.assertRequestHandlerCapability('ping');
      server.assertRequestHandlerCapability('completion/complete');
    });
  });
}

// Helper function to initialize client with specific capabilities
Future<void> _initializeClient(
  MockTransport transport,
  Server server, {
  bool withSampling = false,
  bool withRoots = false,
}) async {
  final clientCapabilities = ClientCapabilities(
    sampling: withSampling ? {} : null,
    roots: withRoots ? ClientCapabilitiesRoots() : null,
  );

  final initParams = InitializeRequestParams(
    protocolVersion: latestProtocolVersion,
    capabilities: clientCapabilities,
    clientInfo: const Implementation(name: 'TestClient', version: '1.0.0'),
  );

  // Process initialize request
  final initRequest = JsonRpcInitializeRequest(id: 1, initParams: initParams);
  transport.receiveMessage(initRequest);

  // Wait for message processing to ensure initialization completes
  await Future.delayed(const Duration(milliseconds: 50));

  // Send initialized notification to complete the handshake
  final initializedNotif = JsonRpcInitializedNotification();
  transport.receiveMessage(initializedNotif);

  // Wait for notification to be processed
  await Future.delayed(const Duration(milliseconds: 50));
}
