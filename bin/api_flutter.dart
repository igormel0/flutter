import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:mysql1/mysql1.dart';

void main() async {
  final settings = ConnectionSettings(
      host: '127.0.0.1',
      port: 3306,
      user: 'root',
      password: '123321', 
      db: 'novobd');

  final router = Router();

  router.post('/login', (Request request) async {
    MySqlConnection? conn;
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);

      final String usuarioApp = data['usuario'].toString().trim();
      final String senhaApp = data['senha'].toString().trim();

      conn = await MySqlConnection.connect(settings);

      // --- CORREÇÃO DO RANGEERROR ---
      // Criamos a tabela com CHARSET latin1 para garantir que o Dart consiga ler os bytes
      await conn.query("""
        CREATE TABLE IF NOT EXISTS login (
          usuario VARCHAR(50), 
          senha VARCHAR(50)
        ) CHARACTER SET latin1 COLLATE latin1_swedish_ci
      """);

      // Inserimos o admin de teste
      await conn.query("REPLACE INTO login (usuario, senha) VALUES ('admin', '123321')");

      // Buscamos o usuário
      var results = await conn.query(
        'SELECT usuario, senha FROM login WHERE usuario = ? AND senha = ?',
        [usuarioApp, senhaApp],
      );

      print("\n--- [VERIFICAÇÃO] ---");
      print("Tentativa: $usuarioApp");

      if (results.isNotEmpty) {
        print("✅ SUCESSO!");
        return Response.ok(jsonEncode({'status': 'sucesso'}), headers: {'content-type': 'application/json'});
      } else {
        print("❌ NÃO ENCONTRADO");
        return Response.forbidden(jsonEncode({'status': 'erro'}), headers: {'content-type': 'application/json'});
      }
    } catch (e) {
      print("💥 ERRO TÉCNICO: $e");
      return Response.internalServerError(body: jsonEncode({'erro': 'Erro no Banco'}));
    } finally {
      await conn?.close();
    }
  });

  final pipeline = Pipeline().addMiddleware(_fixCors()).addHandler(router.call);
  await io.serve(pipeline, 'localhost', 8081);
  print('🚀 Servidor pronto e protegido contra RangeError!');
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