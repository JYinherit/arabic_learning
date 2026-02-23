import 'dart:io' show HttpServer;
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data' show Uint8List;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:arabic_learning/vars/statics_var.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

class PKServer with ChangeNotifier{

  bool started = false;
  late final HttpServer _server;
  late final int _port;
  late final String? _localIP;
  final NetworkInfo _networkInfo = NetworkInfo();

  String? get connectpwd {
    if(!started) return null;
    List<int> tmp = List<int>.generate(3, (int index) => int.parse(_localIP!.split(".")[index + 1]), growable: false);
    int iphex = (((tmp[0] << 16) | (tmp[1] << 8) | tmp[2]) << 16) | (_port & 0xFFFF);
    Uint8List bytes = Uint8List(5);
    bytes[0] = (iphex >> 32) & 0xFF;
    bytes[1] = (iphex >> 24) & 0xFF;
    bytes[2] = (iphex >> 16) & 0xFF;
    bytes[3] = (iphex >> 8) & 0xFF;
    bytes[4] = iphex & 0xFF;
    return base64Encode(bytes).replaceAll("=", "");
  }

  Future<bool> start() async {
    if(started) return true;

    _port = Random().nextInt(55535)+10000;
    final router = Router();

    router.get('/api/check', (Request req) {
      return Response.ok(
        '{"version":${StaticsVar.appVersion}}',
        headers: {'Content-Type': 'application/json'},
      );
    });

    router.post('/api/exchangeDictSum', (Request req) async {
      final body = await req.readAsString();
      return Response.ok('{"received": "$body"}');
    });

    _server = await io.serve(
      router.call,
      '0.0.0.0', // 局域网可访问
      _port,
    );

    _localIP = await _networkInfo.getWifiIP();

    started = true;
    return true;
  }

  Future<void> stop() async {
    await _server.close();
  }
}
