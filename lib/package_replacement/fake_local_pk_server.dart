import 'package:arabic_learning/vars/config_structure.dart';
import 'package:arabic_learning/vars/global.dart';
import 'package:flutter/material.dart';

class PKServer with ChangeNotifier{
  bool get connected => false;

  List<SourceItem> selectableSource = [];

  String? connectpwd = "";

  bool get started => false;

  DateTime? startTime;

  ClassSelection? classSelection;

  bool preparedP1 = false;
  bool preparedP2 = false;

  int? get rndSeed => null;

  late PKState pkState;

  Future<int> testConnect(String text) async {return 0;}

  void watingSelection(BuildContext context, Future<dynamic> Function() param1) {}

  void stopHost() {}

  void renew() {}

  Future<bool>? startHost() async {return false;}

  void watingPrepare(BuildContext context) {}

  void initPK(BuildContext context) {}

  double calculatePt(List selfProgress, int param1) {return 0;}

  void updateState(bool bool) {}

  Future<void> init(Global read) async {}

}

class PKState {
  final List<WordItem> testWords = [];

  int? selfTookenTime;

  int? sideTookenTime;

  List<bool> selfProgress = [];

  List<bool> sideProgress = [];
}