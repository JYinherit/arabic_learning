import 'dart:io' show HttpServer;
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data' show Uint8List;
import 'package:arabic_learning/funcs/utili.dart';
import 'package:arabic_learning/vars/config_structure.dart';
import 'package:arabic_learning/vars/global.dart';
import 'package:logging/logging.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:arabic_learning/vars/statics_var.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:dio/dio.dart' as dio;

class PKServer with ChangeNotifier{

  // both
  bool connected = false;
  final Logger logger = Logger("PKServer");
  late final String? _localIP;
  late int rndSeed;
  List<SourceItem> selectableSource = [];
  ClassSelection? classSelection;
  late Global global;
  final NetworkInfo _networkInfo = NetworkInfo();
  DateTime? startTime;
  bool preparedP1 = false;
  bool preparedP2 = false;
  late final PKState pkState;

  // server
  bool started = false;
  Duration? delay;
  late final HttpServer _server;
  late final int _port;

  // client
  late final String serverAddress;
  final dio.Dio client = dio.Dio();

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

  Future<void> init(Global outerglobal) async {
    _localIP = await _networkInfo.getWifiIP();
    logger.finer("获取到局域网IP: $_localIP");
    global = outerglobal;
  }

  Future<bool> startHost() async {
    if(started) return true;
    _port = Random().nextInt(55535)+10000;
    logger.fine("正在启动服务，随机端口: $_port");
    final router = Router();

    router.get('/api/check', (Request req) {
      logger.fine("收到check请求");
      return Response.ok(
        '{"version":${StaticsVar.appVersion}}',
        headers: {'Content-Type': 'application/json'},
      );
    });

    router.post('/api/testDictSum', (Request req) async {
      if(connected == true) return Response.forbidden("");
      Map<String, dynamic> body = json.decode(await req.readAsString());
      logger.fine("收到testDictSum请求，负载: $body");
      // {
      //  "dictSum": ["SHA256", ...]
      // }
      List sumList = body["dictSum"];
      selectableSource.clear();
      for(SourceItem source in global.wordData.classes) {
        if(sumList.contains(source.getHash(global.wordData.words))) selectableSource.add(source);
        logger.fine("计算得到${source.sourceJsonFileName}在哈希中有匹配");
      }
      if(selectableSource.isNotEmpty) connected = true;
      notifyListeners();
      return Response.ok(json.encode({
        "accept": selectableSource.isNotEmpty,
        "allowed": List<String>.generate(selectableSource.length, (int index) => selectableSource[index].getHash(global.wordData.words), growable: false)
        }),
        headers: {'Content-Type': 'application/json'}
      );
    });

    router.get('/api/selection', (Request req) {
      logger.fine("收到selection请求");
      if(classSelection == null) {
        logger.fine("房主暂未完成选择，statue: false");
        return Response.ok(json.encode({"statue": false}), headers: {'Content-Type': 'application/json'});
      }
      rndSeed = Random().nextInt(1024);
      logger.finer("随机种子: $rndSeed");
      return Response.ok(
        json.encode(
          {
            "statue": true,
            "selected": List<String>.generate(classSelection!.selectedClass.length, (int index) => classSelection!.selectedClass[index].getHash(), growable: false),
            "seed": rndSeed
          }
        ),
        headers: {'Content-Type': 'application/json'},
      );
    });

    router.post('/api/prepare', (Request req) async {
      Map<String, dynamic> body = json.decode(await req.readAsString());
      logger.fine("收到prepare请求，负载 $body");

      if(body["time"] != null && delay == null) {
        delay = DateTime.tryParse(body["time"])!.difference(DateTime.now());
        logger.info("已加载双端延迟补偿: ${delay!.inSeconds}秒");
      }
      if(body["prepared"]) {
        preparedP2 = true;
        logger.fine("对方准备完毕");
        if(preparedP1 && startTime == null) {
          startTime = DateTime.now().add(Duration(seconds: 5));
          pkState = PKState(
            testWords: getSelectedWords(global.wordData, classSelection!.selectedClass, doShuffle: true, shuffleSeed: rndSeed), 
            selfProgress: [], 
            sideProgress: []
          );
          logger.fine("已生成开始时间: $startTime(添加delay后为: ${startTime?.add(delay!).toIso8601String()}); PKState已初始化");
        }
        notifyListeners();
      }
      
      
      return Response.ok(json.encode({
        "prepared": preparedP1,
        "start": startTime?.add(delay!).toIso8601String()
        }),
        headers: {'Content-Type': 'application/json'}
      );
    });

    router.post('/api/sync', (Request req) async {
      Map<String, dynamic> body = json.decode(await req.readAsString());
      logger.finer("收到sync请求，负载: $body");
      bool changed = false;
      if(body["progress"] != null && body["progress"].length != pkState.sideProgress.length) {
        pkState.sideProgress = List.generate(body["progress"].length, (int index) => body["progress"][index] as bool);
        logger.fine("已更新本地PKState.sideProgress");
        changed = true;
      }
      if(pkState.sideProgress.length == pkState.testWords.length && body["tooken"] != null) {
        pkState.sideTookenTime = body["tooken"] - delay!.inSeconds;
        logger.fine("已更新本地PKState.sideTookenTime");
        changed = true;
      }
      if(changed) notifyListeners();
      if(pkState.selfTookenTime != null) logger.fine("回报本地tokenTime: ${pkState.selfTookenTime}");
      return Response.ok(json.encode({
        "progress": pkState.selfProgress,
        "tooken": pkState.selfTookenTime
        }),
        headers: {'Content-Type': 'application/json'}
      );
    });

    router.get('/api/done', (Request req) async {
      logger.info("收到done请求");
      Future.delayed(Duration(seconds: 1), () {
        stopHost();
      });
      notifyListeners();
      return Response.ok(null);
    });

    _server = await io.serve(
      router.call,
      '0.0.0.0', // 局域网可访问
      _port,
    );

    logger.fine("服务端已启动");
    started = true;
    return true;
  }

  Future<void> stopHost() async {
    await _server.close();
    logger.info("服务端已关闭");
  }

  List<int>? decodeConnectPwd(String connectpwd){
    logger.info("尝试解码$connectpwd");
    while (connectpwd.length == 7) {
      connectpwd = "$connectpwd=";
    }
    late Uint8List tmp;
    try{
      tmp = base64Decode(connectpwd);
    } catch (e) {
      logger.warning("解码错误");
      return null;
    }
    
    if(tmp.length != 5){
      logger.warning("解码错误");
      return null;
    }
    int comb = (tmp[0] << 32) | (tmp[1] << 24) | (tmp[2] << 16) | (tmp[3] << 8) | tmp[4];
    int port = comb & 0xFFFF;
    int iphex= comb >> 16;
    return [(iphex >> 16) & 0xFF, (iphex >> 8 & 0xFF), iphex & 0xFF, port];
  }

  Future<int> testConnect(String connectpwd) async {
    List<int>? addressinfo = decodeConnectPwd(connectpwd);
    if(addressinfo == null) {
      logger.severe("联机口令解析失败，终止连接");
      return 1;
    }
    serverAddress = "http://${_localIP!.split(".")[0]}.${addressinfo[0]}.${addressinfo[1]}.${addressinfo[2]}:${addressinfo[3]}";
    logger.info("服务端口解析结果: $serverAddress");
    final checkRes = await client.get("$serverAddress/api/check");
    if(checkRes.statusCode != 200) {
      logger.severe("连接服务端失败");
      return 2;
    }
    if(checkRes.data["version"] != StaticsVar.appVersion) {
      logger.severe("版本校验不通过，对方版本为: ${checkRes.data["version"]}，我方为${StaticsVar.appVersion}");
      return 3;
    }
    logger.fine("双端版本校验通过");
    final dictRes = await client.post(
      "$serverAddress/api/testDictSum", 
      data: {
        "dictSum": List<String>.generate(global.wordData.classes.length, (int index) => global.wordData.classes[index].getHash(global.wordData.words), growable: false)
      }
    );
    if(dictRes.statusCode != 200) {
      logger.severe("连接服务端失败");
      return 2;
    }
    if(!dictRes.data["accept"]) {
      logger.severe("本地与服务端无可使用的相同词库");
      return 4;
    }
    selectableSource.clear();
    List remoteDict = dictRes.data["allowed"];
    for(SourceItem source in global.wordData.classes) {
      if(remoteDict.contains(source.getHash(global.wordData.words))) selectableSource.add(source);
    }
    connected = true;
    notifyListeners();
    return 0;
  }

  Future<ClassSelection> watingSelection() async {
    logger.fine("开始等待服务端选择课程");
    while(classSelection == null) {
      await Future.delayed(Duration(seconds: 1));
      try{
        logger.fine("正在检查选择情况");
        final selectionRes = await client.get("$serverAddress/api/selection", options: dio.Options(connectTimeout: Duration(seconds: 1)));
        if(selectionRes.statusCode != 200) throw Exception("Unexcepted statusCode: ${selectionRes.statusCode}");
        Map payload = selectionRes.data;
        logger.finer("此次检查结果: $payload");
        if(!payload["statue"]) continue;
        rndSeed = payload["seed"];
        List<ClassItem> selectedClass = [];
        for(SourceItem sourceItem in selectableSource) {
          for(ClassItem classItem in sourceItem.subClasses){
            if(payload["selected"].contains(classItem.getHash())){
              selectedClass.add(classItem);
            }
          }
        }
        classSelection = ClassSelection(selectedClass: selectedClass, countInReview: false);
      } catch (e) {
        logger.shout("连接服务端发生错误: $e");
        rethrow;
      } 
    }
    return classSelection!;
  }

  Future<void> watingPrepare() async {
    logger.fine("开始等待双端准备");
    while (!preparedP2 || startTime == null) {
      try{
        logger.fine("正在交换等待情况");
        await Future.delayed(Duration(seconds: 1));
        final prepareRes = await client.post(
          "$serverAddress/api/prepare", 
          data: {
            "prepared": preparedP1,
            "time": DateTime.now().toIso8601String()
          }
        );
        if(prepareRes.statusCode != 200) throw Exception("Unexcepted statusCode: ${prepareRes.statusCode}");
        logger.finer("交换结果: ${prepareRes.data}");
        bool changed = false;
        if(preparedP2 != prepareRes.data["prepared"]) {
          preparedP2 = prepareRes.data["prepared"];
          changed = true;
        }
        if(preparedP1 && preparedP2 && prepareRes.data["start"] != null) {
          startTime = DateTime.tryParse(prepareRes.data["start"]) as DateTime;
          changed = true;
        }
        if(changed) notifyListeners();
      } catch (e) {
        logger.shout("连接服务端失败: $e");
        rethrow;
      }
    }
  }

  void initPK() {
    pkState = PKState(
      testWords: getSelectedWords(global.wordData, classSelection!.selectedClass, doShuffle: true, shuffleSeed: rndSeed), 
      selfProgress: [], 
      sideProgress: []
    );
    logger.fine("已完成PKState初始化");
    syncPKState();
  }

  Future<void> syncPKState() async {
    logger.info("开始进行双端状态同步");
    while(true) {
      try{
        await Future.delayed(Duration(milliseconds: 500));
        logger.finer("进行状态数据交换");
        final syncRes = await client.post(
          "$serverAddress/api/sync",
          data: {
            "progress": pkState.selfProgress,
            "tooken": pkState.selfTookenTime
          },
          options: dio.Options(connectTimeout: Duration(seconds: 1))
        );
        if(syncRes.statusCode != 200) throw Exception("Unexcepted statusCode: ${syncRes.statusCode}");
        logger.finer("对方交换结果为: ${syncRes.data}");
        bool changed = false;
        if(syncRes.data["progress"] != null && syncRes.data["progress"].length != pkState.sideProgress.length) {
          pkState.sideProgress = List.generate(syncRes.data["progress"].length, (int index) => syncRes.data["progress"][index] as bool);
          logger.fine("已更新本地PKState.sideProgress");
          changed = true;
        }
        if(pkState.sideProgress.length == pkState.testWords.length && syncRes.data["tooken"] != null) {
          logger.fine("已更新本地PKState.sideTookenTime");
          pkState.sideTookenTime = syncRes.data["tooken"];
          changed = true;
        }
        if(changed) notifyListeners();
        if(pkState.selfTookenTime != null && pkState.sideTookenTime != null) {
          client.get("$serverAddress/api/done");
          logger.fine("已通知服务端联机进程完成");
          break;
        }
      } catch (e) {
        logger.shout("同步状态失败 $e");
      }
    }
  }

  void updateState(bool correct) {
    pkState.selfProgress.add(correct);
    notifyListeners();
  }

  double calculatePt(List<bool> progress, int tookenTime) {
    int correctCount = 0;
    for(bool value in progress) {
      if(value) correctCount++;
    }
    return 750*(correctCount/progress.length) + 250 - tookenTime;
  }
}

class PKState {
  List<WordItem> testWords;
  List<bool> selfProgress;
  int? selfTookenTime;
  List<bool> sideProgress;
  int? sideTookenTime;

  PKState({required this.testWords, required this.selfProgress, required this.sideProgress});
}