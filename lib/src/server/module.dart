/// This module exports key components of the MCP server implementation.
///
/// It includes the main server logic, server-sent events (SSE) handling,
/// MCP protocol utilities, and standard I/O-based server communication.
library;

export 'server.dart'; // Core server implementation for handling MCP logic.
export 'sse.dart'; // Server-Sent Events (SSE) communication.
export 'streamable_https.dart'; // Streamable HTTPS communication.
export 'stdio.dart'; // Standard I/O-based server communication
export 'mcp.dart'; // Utilities and definitions for the MCP protocol.
export 'sse_server_manager.dart'; // Manages SSE connections and routing.
