import 'dart:async';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:mcp_dart/src/server/iostream.dart';

/// Creates and returns an MCP server with stdin/stdout transport.
Future<McpServer> getServer() async {
  final mcpServer = McpServer(
    Implementation(name: "example-dart-iostream-server", version: "1.0.0"),
    options: ServerOptions(capabilities: ServerCapabilities()),
  );

  mcpServer.tool(
    "calculate",
    description: 'Perform basic arithmetic operations',
    inputSchemaProperties: {
      'operation': {
        'type': 'string',
        'enum': ['add', 'subtract', 'multiply', 'divide'],
      },
      'a': {'type': 'number'},
      'b': {'type': 'number'},
    },
    callback: ({args, extra}) async {
      final operation = args!['operation'];
      final a = args['a'];
      final b = args['b'];
      return CallToolResult(
        content: [
          TextContent(
            text: switch (operation) {
              'add' => 'Result: ${a + b}',
              'subtract' => 'Result: ${a - b}',
              'multiply' => 'Result: ${a * b}',
              'divide' => 'Result: ${a / b}',
              _ => throw Exception('Invalid operation'),
            },
          ),
        ],
      );
    },
  );
  return mcpServer;
}

