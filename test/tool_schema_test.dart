import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Tool Schema Required Fields Tests', () {
    test('ToolInputSchema preserves required fields during serialization', () {
      final schema = ToolInputSchema(
        properties: {
          'operation': {'type': 'string'},
          'a': {'type': 'number'},
          'b': {'type': 'number'},
        },
        required: ['operation', 'a'],
      );

      final json = schema.toJson();
      expect(json['type'], equals('object'));
      expect(json['properties'], isA<Map<String, dynamic>>());
      expect(json['required'], equals(['operation', 'a']));
    });

    test('ToolInputSchema preserves required fields during deserialization',
        () {
      final json = {
        'type': 'object',
        'properties': {
          'operation': {'type': 'string'},
          'a': {'type': 'number'},
          'b': {'type': 'number'},
        },
        'required': ['operation', 'a'],
      };

      final schema = ToolInputSchema.fromJson(json);
      expect(schema.type, equals('object'));
      expect(schema.properties, equals(json['properties']));
      expect(schema.required, equals(['operation', 'a']));
    });

    test('ToolInputSchema handles empty required array', () {
      final schema = ToolInputSchema(
        properties: {
          'optional': {'type': 'string'}
        },
        required: [],
      );

      final json = schema.toJson();
      // Empty required array should not be included in JSON
      expect(json.containsKey('required'), isFalse);
    });

    test('ToolInputSchema handles null required field', () {
      final schema = ToolInputSchema(
        properties: {
          'optional': {'type': 'string'}
        },
        required: null,
      );

      final json = schema.toJson();
      expect(json.containsKey('required'), isFalse);
    });

    test('ToolOutputSchema preserves required fields during serialization', () {
      final schema = ToolOutputSchema(
        properties: {
          'result': {'type': 'string'},
          'status': {'type': 'number'},
        },
        required: ['result'],
      );

      final json = schema.toJson();
      expect(json['type'], equals('object'));
      expect(json['properties'], isA<Map<String, dynamic>>());
      expect(json['required'], equals(['result']));
    });

    test('ToolOutputSchema preserves required fields during deserialization',
        () {
      final json = {
        'type': 'object',
        'properties': {
          'result': {'type': 'string'},
          'status': {'type': 'number'},
        },
        'required': ['result'],
      };

      final schema = ToolOutputSchema.fromJson(json);
      expect(schema.type, equals('object'));
      expect(schema.properties, equals(json['properties']));
      expect(schema.required, equals(['result']));
    });

    test('Tool preserves input schema required fields end-to-end', () {
      final tool = Tool(
        name: 'calculate',
        description: 'Performs mathematical calculations',
        inputSchema: ToolInputSchema(
          properties: {
            'operation': {'type': 'string'},
            'a': {'type': 'number'},
            'b': {'type': 'number'},
          },
          required: ['operation', 'a'],
        ),
      );

      final json = tool.toJson();
      expect(json['name'], equals('calculate'));
      expect(json['inputSchema']['required'], equals(['operation', 'a']));

      final deserialized = Tool.fromJson(json);
      expect(deserialized.name, equals('calculate'));
      expect(deserialized.inputSchema.required, equals(['operation', 'a']));
    });

    test('Tool preserves output schema required fields end-to-end', () {
      final tool = Tool(
        name: 'calculate',
        inputSchema: ToolInputSchema(),
        outputSchema: ToolOutputSchema(
          properties: {
            'result': {'type': 'number'},
            'equation': {'type': 'string'},
          },
          required: ['result'],
        ),
      );

      final json = tool.toJson();
      expect(json['outputSchema']['required'], equals(['result']));

      final deserialized = Tool.fromJson(json);
      expect(deserialized.outputSchema?.required, equals(['result']));
    });

    test('ListToolsResult preserves tool required fields', () {
      final tools = [
        Tool(
          name: 'search',
          inputSchema: ToolInputSchema(
            properties: {
              'query': {'type': 'string'},
              'limit': {'type': 'number'},
            },
            required: ['query'],
          ),
        ),
        Tool(
          name: 'create',
          inputSchema: ToolInputSchema(
            properties: {
              'name': {'type': 'string'},
              'data': {'type': 'object'},
            },
            required: ['name', 'data'],
          ),
        ),
      ];

      final result = ListToolsResult(tools: tools);
      final json = result.toJson();

      expect(json['tools'][0]['inputSchema']['required'], equals(['query']));
      expect(json['tools'][1]['inputSchema']['required'],
          equals(['name', 'data']));

      final deserialized = ListToolsResult.fromJson(json);
      expect(deserialized.tools[0].inputSchema.required, equals(['query']));
      expect(
          deserialized.tools[1].inputSchema.required, equals(['name', 'data']));
    });

    test('Real-world MCP server tool schema example', () {
      // Example from a real MCP server like Hugging Face
      final serverResponse = {
        'tools': [
          {
            'name': 'space_search',
            'description': 'Search for Hugging Face Spaces',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'query': {
                  'type': 'string',
                  'description': 'Search query for spaces'
                },
                'limit': {
                  'type': 'integer',
                  'description': 'Maximum number of results',
                  'default': 10
                }
              },
              'required': ['query']
            }
          }
        ]
      };

      final result = ListToolsResult.fromJson(serverResponse);
      final tool = result.tools.first;

      expect(tool.name, equals('space_search'));
      expect(tool.inputSchema.required, equals(['query']));
      expect(tool.inputSchema.properties?['query']?['type'], equals('string'));
      expect(tool.inputSchema.properties?['limit']?['default'], equals(10));

      // Verify round-trip maintains required fields
      final serialized = result.toJson();
      expect(
          serialized['tools'][0]['inputSchema']['required'], equals(['query']));
    });

    test('Backward compatibility with existing code without required fields',
        () {
      // Existing code that doesn't specify required fields should still work
      final tool = Tool(
        name: 'legacy-tool',
        inputSchema: ToolInputSchema(
          properties: {
            'param': {'type': 'string'}
          },
        ),
      );

      final json = tool.toJson();
      expect(json['name'], equals('legacy-tool'));
      expect(json['inputSchema'].containsKey('required'), isFalse);

      final deserialized = Tool.fromJson(json);
      expect(deserialized.name, equals('legacy-tool'));
      expect(deserialized.inputSchema.required, isNull);
    });

    test('JSON Schema from external server without required fields', () {
      // Some servers might not include required fields
      final externalToolJson = {
        'name': 'external-tool',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'param': {'type': 'string'}
          },
          // No 'required' field
        },
      };

      final tool = Tool.fromJson(externalToolJson);
      expect(tool.name, equals('external-tool'));
      expect(tool.inputSchema.required, isNull);

      // Should still serialize correctly
      final serialized = tool.toJson();
      expect(serialized['inputSchema'].containsKey('required'), isFalse);
    });
  });

  group('LLM Integration Tests', () {
    test('Tool schema is compatible with OpenAI function calling format', () {
      final tool = Tool(
        name: 'get_weather',
        description: 'Get weather information for a location',
        inputSchema: ToolInputSchema(
          properties: {
            'location': {
              'type': 'string',
              'description': 'The city and state, e.g. San Francisco, CA'
            },
            'unit': {
              'type': 'string',
              'enum': ['celsius', 'fahrenheit'],
              'description': 'Temperature unit'
            }
          },
          required: ['location'],
        ),
      );

      // Convert to OpenAI function calling format
      final openaiFunction = {
        'type': 'function',
        'function': {
          'name': tool.name,
          'description': tool.description,
          'parameters': tool.inputSchema.toJson(),
        }
      };

      final function = openaiFunction['function'] as Map<String, dynamic>;
      final parameters = function['parameters'] as Map<String, dynamic>;
      final properties = parameters['properties'] as Map<String, dynamic>;
      final location = properties['location'] as Map<String, dynamic>;

      expect(function['name'], equals('get_weather'));
      expect(parameters['type'], equals('object'));
      expect(parameters['required'], equals(['location']));
      expect(location['type'], equals('string'));
    });

    test('Tool schema is compatible with Anthropic Claude format', () {
      final tool = Tool(
        name: 'analyze_code',
        description: 'Analyze code for potential issues',
        inputSchema: ToolInputSchema(
          properties: {
            'code': {'type': 'string', 'description': 'The code to analyze'},
            'language': {
              'type': 'string',
              'description': 'Programming language'
            },
            'strict': {
              'type': 'boolean',
              'description': 'Enable strict mode',
              'default': false
            }
          },
          required: ['code', 'language'],
        ),
      );

      // Convert to Anthropic tool format
      final anthropicTool = {
        'name': tool.name,
        'description': tool.description,
        'input_schema': tool.inputSchema.toJson(),
      };

      expect(anthropicTool['name'], equals('analyze_code'));
      final inputSchema = anthropicTool['input_schema'] as Map<String, dynamic>;
      final properties = inputSchema['properties'] as Map<String, dynamic>;
      final strict = properties['strict'] as Map<String, dynamic>;

      expect(inputSchema['required'], equals(['code', 'language']));
      expect(strict['default'], equals(false));
    });
  });
}
