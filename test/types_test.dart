import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  group('JsonRpcMessage Tests', () {
    test('JsonRpcInitializeRequest serialization and deserialization', () {
      final request = JsonRpcInitializeRequest(
        id: 1,
        initParams: InitializeRequestParams(
          protocolVersion: latestProtocolVersion,
          capabilities: ClientCapabilities(
            experimental: {'featureX': true},
            sampling: {'enabled': true},
          ),
          clientInfo: Implementation(name: 'test-client', version: '1.0.0'),
        ),
      );

      final json = request.toJson();
      expect(json['jsonrpc'], equals(jsonRpcVersion));
      expect(json['method'], equals('initialize'));
      expect(json['params']['protocolVersion'], equals(latestProtocolVersion));

      final deserialized = JsonRpcInitializeRequest.fromJson(json);
      expect(deserialized.id, equals(request.id));
      expect(deserialized.initParams.protocolVersion,
          equals(latestProtocolVersion));
    });

    test('JsonRpcResponse serialization', () {
      final response = JsonRpcResponse(
        id: 1,
        result: {'key': 'value'},
        meta: {'metaKey': 'metaValue'},
      );

      final json = response.toJson();
      expect(json['jsonrpc'], equals(jsonRpcVersion));
      expect(json['id'], equals(1));
      expect(json['result']['key'], equals('value'));
      expect(json['result']['_meta']['metaKey'], equals('metaValue'));
    });

    test('JsonRpcError serialization and deserialization', () {
      final error = JsonRpcError(
        id: 1,
        error: JsonRpcErrorData(
          code: ErrorCode.invalidRequest.value,
          message: 'Invalid request',
          data: {'details': 'Missing required field'},
        ),
      );

      final json = error.toJson();
      expect(json['jsonrpc'], equals(jsonRpcVersion));
      expect(json['error']['code'], equals(ErrorCode.invalidRequest.value));
      expect(json['error']['message'], equals('Invalid request'));
      expect(
          json['error']['data']['details'], equals('Missing required field'));

      final deserialized = JsonRpcError.fromJson(json);
      expect(deserialized.id, equals(error.id));
      expect(deserialized.error.code, equals(ErrorCode.invalidRequest.value));
      expect(deserialized.error.message, equals('Invalid request'));
      expect(
          deserialized.error.data['details'], equals('Missing required field'));
    });
  });

  group('Capabilities Tests', () {
    test('ServerCapabilities serialization and deserialization', () {
      final capabilities = ServerCapabilities(
        experimental: {'featureY': true},
        logging: {'enabled': true},
        prompts: ServerCapabilitiesPrompts(listChanged: true),
        resources:
            ServerCapabilitiesResources(subscribe: true, listChanged: true),
        tools: ServerCapabilitiesTools(listChanged: true),
      );

      final json = capabilities.toJson();
      expect(json['experimental']['featureY'], equals(true));
      expect(json['logging']['enabled'], equals(true));
      expect(json['prompts']['listChanged'], equals(true));
      expect(json['resources']['subscribe'], equals(true));
      expect(json['tools']['listChanged'], equals(true));

      final deserialized = ServerCapabilities.fromJson(json);
      expect(deserialized.prompts?.listChanged, equals(true));
      expect(deserialized.resources?.subscribe, equals(true));
    });

    test('ClientCapabilities serialization and deserialization', () {
      final capabilities = ClientCapabilities(
        experimental: {'featureZ': true},
        sampling: {'enabled': true},
        roots: ClientCapabilitiesRoots(listChanged: true),
      );

      final json = capabilities.toJson();
      expect(json['experimental']['featureZ'], equals(true));
      expect(json['sampling']['enabled'], equals(true));
      expect(json['roots']['listChanged'], equals(true));

      final deserialized = ClientCapabilities.fromJson(json);
      expect(deserialized.roots?.listChanged, equals(true));
    });
  });

  group('Content Tests', () {
    test('TextContent serialization and deserialization', () {
      final content = TextContent(text: 'Hello, world!');
      final json = content.toJson();
      expect(json['type'], equals('text'));
      expect(json['text'], equals('Hello, world!'));

      final deserialized = TextContent.fromJson(json);
      expect(deserialized.text, equals('Hello, world!'));
    });

    test('ImageContent serialization and deserialization', () {
      final content = ImageContent(data: 'base64data', mimeType: 'image/png');
      final json = content.toJson();
      expect(json['type'], equals('image'));
      expect(json['data'], equals('base64data'));
      expect(json['mimeType'], equals('image/png'));

      final deserialized = ImageContent.fromJson(json);
      expect(deserialized.data, equals('base64data'));
      expect(deserialized.mimeType, equals('image/png'));
    });

    test('AudioContent serialization and deserialization', () {
      final content = AudioContent(data: 'base64data', mimeType: 'audio/wav');
      final json = content.toJson();
      expect(json['type'], equals('audio'));
      expect(json['data'], equals('base64data'));
      expect(json['mimeType'], equals('audio/wav'));

      final deserialized = AudioContent.fromJson(json);
      expect(deserialized.data, equals('base64data'));
      expect(deserialized.mimeType, equals('audio/wav'));
    });

    test('UnknownContent serialization and deserialization', () {
      final content = UnknownContent(type: 'unknown');
      final json = content.toJson();
      expect(json['type'], equals('unknown'));

      final deserialized = UnknownContent(type: 'unknown');
      expect(deserialized.type, equals('unknown'));
    });
  });

  group('Resource Tests', () {
    test('Resource serialization and deserialization', () {
      final resource = Resource(
        uri: 'file://example.txt',
        name: 'Example File',
        description: 'A sample file',
        mimeType: 'text/plain',
      );

      final json = resource.toJson();
      expect(json['uri'], equals('file://example.txt'));
      expect(json['name'], equals('Example File'));
      expect(json['description'], equals('A sample file'));
      expect(json['mimeType'], equals('text/plain'));

      final deserialized = Resource.fromJson(json);
      expect(deserialized.uri, equals('file://example.txt'));
      expect(deserialized.name, equals('Example File'));
    });

    test('ResourceContents serialization and deserialization', () {
      final contents = TextResourceContents(
        uri: 'file://example.txt',
        text: 'Sample text content',
        mimeType: 'text/plain',
      );

      final json = contents.toJson();
      expect(json['uri'], equals('file://example.txt'));
      expect(json['text'], equals('Sample text content'));
      expect(json['mimeType'], equals('text/plain'));

      final deserialized =
          ResourceContents.fromJson(json) as TextResourceContents;
      expect(deserialized.uri, equals('file://example.txt'));
      expect(deserialized.text, equals('Sample text content'));
    });

    test('BlobResourceContents serialization and deserialization', () {
      final contents = BlobResourceContents(
        uri: 'file://example.bin',
        blob: 'base64data',
        mimeType: 'application/octet-stream',
      );

      final json = contents.toJson();
      expect(json['uri'], equals('file://example.bin'));
      expect(json['blob'], equals('base64data'));
      expect(json['mimeType'], equals('application/octet-stream'));

      final deserialized =
          ResourceContents.fromJson(json) as BlobResourceContents;
      expect(deserialized.uri, equals('file://example.bin'));
      expect(deserialized.blob, equals('base64data'));
    });
  });

  group('Prompt Tests', () {
    test('Prompt serialization and deserialization', () {
      final prompt = Prompt(
        name: 'example-prompt',
        description: 'A sample prompt',
        arguments: [
          PromptArgument(
              name: 'arg1', description: 'Argument 1', required: true),
        ],
      );

      final json = prompt.toJson();
      expect(json['name'], equals('example-prompt'));
      expect(json['description'], equals('A sample prompt'));
      expect(json['arguments']?.first['name'], equals('arg1'));

      final deserialized = Prompt.fromJson(json);
      expect(deserialized.name, equals('example-prompt'));
      expect(deserialized.arguments?.first.name, equals('arg1'));
    });

    test('PromptArgument serialization and deserialization', () {
      final argument = PromptArgument(
        name: 'arg1',
        description: 'Argument 1',
        required: true,
      );

      final json = argument.toJson();
      expect(json['name'], equals('arg1'));
      expect(json['description'], equals('Argument 1'));
      expect(json['required'], equals(true));

      final deserialized = PromptArgument.fromJson(json);
      expect(deserialized.name, equals('arg1'));
      expect(deserialized.description, equals('Argument 1'));
      expect(deserialized.required, equals(true));
    });
  });
  group('CreateMessageResult Tests', () {
    test('CreateMessageResult serialization and deserialization', () {
      final result = CreateMessageResult(
        model: 'gpt-4',
        stopReason: StopReason.maxTokens,
        role: SamplingMessageRole.assistant,
        content: SamplingTextContent(text: 'Hello, world!'),
        meta: {'key': 'value'},
      );

      final json = result.toJson();
      expect(json['model'], equals('gpt-4'));
      expect(json['stopReason'], equals(StopReason.maxTokens.toString()));
      expect(json['role'], equals('assistant'));
      expect(json['content']['type'], equals('text'));
      expect(json['content']['text'], equals('Hello, world!'));
      expect(json['_meta'], isNull); // `_meta` is not included in `toJson`

      final deserialized = CreateMessageResult.fromJson({
        'model': 'gpt-4',
        'stopReason': 'maxTokens',
        'role': 'assistant',
        'content': {'type': 'text', 'text': 'Hello, world!'},
        '_meta': {'key': 'value'},
      });

      expect(deserialized.model, equals('gpt-4'));
      expect(deserialized.stopReason, equals(StopReason.maxTokens));
      expect(deserialized.role, equals(SamplingMessageRole.assistant));
      expect(deserialized.content, isA<SamplingTextContent>());
      expect((deserialized.content as SamplingTextContent).text,
          equals('Hello, world!'));
      expect(deserialized.meta, equals({'key': 'value'}));
    });

    test('CreateMessageResult handles custom stopReason', () {
      final result = CreateMessageResult(
        model: 'gpt-4',
        stopReason: 'customReason',
        role: SamplingMessageRole.assistant,
        content: SamplingTextContent(text: 'Custom reason test'),
      );

      final json = result.toJson();
      expect(json['stopReason'], equals('customReason'));

      final deserialized = CreateMessageResult.fromJson({
        'model': 'gpt-4',
        'stopReason': 'customReason',
        'role': 'assistant',
        'content': {'type': 'text', 'text': 'Custom reason test'},
      });

      expect(deserialized.stopReason, equals('customReason'));
    });

    test('CreateMessageResult handles invalid stopReason gracefully', () {
      final deserialized = CreateMessageResult.fromJson({
        'model': 'gpt-4',
        'stopReason': 'invalidReason',
        'role': 'assistant',
        'content': {'type': 'text', 'text': 'Invalid reason test'},
      });

      expect(deserialized.stopReason, equals('invalidReason'));
    });
  });

  group('JsonRpcMessage.fromJson Tests', () {
    test('Parses valid request with method and id', () {
      final json = {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'ping',
      };
      final message = JsonRpcMessage.fromJson(json);
      expect(message, isA<JsonRpcPingRequest>());
      expect((message as JsonRpcPingRequest).id, equals(1));
    });

    test('Parses valid notification without id', () {
      final json = {
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      };
      final message = JsonRpcMessage.fromJson(json);
      expect(message, isA<JsonRpcInitializedNotification>());
    });

    test('Parses valid response with result and meta', () {
      final json = {
        'jsonrpc': '2.0',
        'id': 1,
        'result': {
          'key': 'value',
          '_meta': {'metaKey': 'metaValue'}
        },
      };
      final message = JsonRpcMessage.fromJson(json);
      expect(message, isA<JsonRpcResponse>());
      final response = message as JsonRpcResponse;
      expect(response.id, equals(1));
      expect(response.result, equals({'key': 'value'}));
      expect(response.meta, equals({'metaKey': 'metaValue'}));
    });

    test('Parses valid error response', () {
      final json = {
        'jsonrpc': '2.0',
        'id': 1,
        'error': {'code': -32601, 'message': 'Method not found'},
      };
      final message = JsonRpcMessage.fromJson(json);
      expect(message, isA<JsonRpcError>());
      final error = message as JsonRpcError;
      expect(error.id, equals(1));
      expect(error.error.code, equals(-32601));
      expect(error.error.message, equals('Method not found'));
    });

    test('Throws FormatException for invalid JSON-RPC version', () {
      final json = {
        'jsonrpc': '1.0',
        'id': 1,
        'method': 'ping',
      };
      expect(() => JsonRpcMessage.fromJson(json), throwsFormatException);
    });

    test('Throws UnimplementedError for unknown method', () {
      final json = {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'unknownMethod',
      };
      expect(() => JsonRpcMessage.fromJson(json), throwsUnimplementedError);
    });

    test('Throws FormatException for invalid message format', () {
      final json = {
        'jsonrpc': '2.0',
        'id': 1,
      };
      expect(() => JsonRpcMessage.fromJson(json), throwsFormatException);
    });
  });
}
