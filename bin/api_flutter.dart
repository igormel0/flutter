import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:postgres/postgres.dart';

class DatabaseManager {
  final Endpoint endpoint;
  final ConnectionSettings settings;
  Connection? _conn;

  DatabaseManager(this.endpoint, {SslMode? sslMode})
      : settings = ConnectionSettings(sslMode: sslMode ?? SslMode.require);

  // Função mágica que garante uma conexão ativa
  Future<Connection> get connection async {
    try {
      // Se a conexão for nula ou o socket estiver fechado, tenta conectar
      if (_conn == null) {
        _conn = await Connection.open(endpoint, settings: settings);
      }
    } catch (e) {
      print("🔄 Tentando reconectar ao PostgreSQL...");
      _conn = await Connection.open(endpoint, settings: settings);
    }
    return _conn!;
  }
}

void main() async {
  final endpoint = Endpoint(
    host: '127.0.0.1',
    port: 5433,
    database: 'novobd',
    username: 'postgres',
    password: '123321',
  );

  final dbManager = DatabaseManager(endpoint, sslMode: SslMode.disable);

  // Setup inicial
  try {
    final conn = await dbManager.connection;
    await conn.execute("""
      CREATE TABLE IF NOT EXISTS login (
        usuario VARCHAR(50) PRIMARY KEY, 
        senha VARCHAR(50)
      )
    """);
    print("✅ Banco de dados pronto!");
  } catch (e) {
    print("❌ Erro inicial: $e");
  }

  final router = Router();

  router.post('/login', (Request request) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      final String usuarioApp = data['usuario']?.toString().trim() ?? '';
      final String senhaApp = data['senha']?.toString().trim() ?? '';

      // SEMPRE pegamos a conexão através do manager
      final conn = await dbManager.connection;

      var results = await conn.execute(
        'SELECT usuario, senha FROM login WHERE usuario = \$1 AND senha = \$2',
        parameters: [usuarioApp, senhaApp],
      );

      if (results.isNotEmpty) {
        return Response.ok(jsonEncode({'status': 'sucesso'}), headers: {'content-type': 'application/json'});
      } else {
        return Response.forbidden(jsonEncode({'status': 'erro'}), headers: {'content-type': 'application/json'});
      }
    } catch (e) {
      print("💥 Erro na rota: $e");
      return Response.internalServerError(body: jsonEncode({'erro': 'Conexão perdida. Tente novamente.'}));
    }
  });

  final pipeline = Pipeline().addMiddleware(_fixCors()).addHandler(router.call);
  await io.serve(pipeline, '0.0.0.0', 8081);
  print('🚀 Servidor rodando em http://localhost:8081');
}

Middleware _fixCors() {
  return (Handler handler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') return Response.ok('', headers: {'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET, POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type'});
      final response = await handler(request);
      return response.change(headers: {'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET, POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type'});
    };
  };
}