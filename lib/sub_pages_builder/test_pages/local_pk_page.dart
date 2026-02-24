import 'dart:math';

import 'package:arabic_learning/funcs/local_pk_server.dart';
import 'package:arabic_learning/funcs/ui.dart';
import 'package:arabic_learning/vars/config_structure.dart';
import 'package:arabic_learning/vars/statics_var.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';


class LocalPKSelectPage extends StatefulWidget {
  const LocalPKSelectPage({super.key});

  @override
  State<StatefulWidget> createState() => _LocalPKSelectPage();
}
class _LocalPKSelectPage extends State<LocalPKSelectPage> {
  final TextEditingController connectpwdController = TextEditingController();
  final MobileScannerController scannerController = MobileScannerController();
  bool isconnecting = false;
  bool isScaning = false;

  Future<void> connecting(BuildContext context) async {
    if(isconnecting || connectpwdController.text.isEmpty) return;
    setState(() {
      isconnecting = true;
    });
    late final int statue;
    try {
      statue = await context.read<PKServer>().testConnect(connectpwdController.text);
    } catch (e) {
      if(context.mounted) alart(context, "连接发生错误: $e");
    }
    if(!context.mounted) return;
    if(statue == 0){
      PKServer notifier = context.read<PKServer>();
      Navigator.push(
        context, 
        MaterialPageRoute(builder: (context) => ChangeNotifierProvider.value(
          value: notifier,
          child: ClientWatingPage(),
        ))
      );
    } else if (statue == 1) {
      alart(context, "联机口令错误");
    } else if (statue == 2) {
      alart(context, "连接服务端失败\n请检查是否在同一局域网内及对方防火墙是否放行");
    } else if (statue == 3) {
      alart(context, "版本校验不通过: 双方版本不一致");
    } else if (statue == 4) {
      alart(context, "本地与服务端无可使用的相同词库");
    }
    if(isScaning) scannerController.dispose();
    setState(() {
      isconnecting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    MediaQueryData mediaQuery = MediaQuery.of(context);
    PKServer notifier = context.read<PKServer>();
    return Scaffold(
      appBar: AppBar(title: Text("局域网联机")),
      body: Column(
        children: [
          SizedBox(height: mediaQuery.size.height * 0.05),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              fixedSize: Size(mediaQuery.size.width * 0.8, mediaQuery.size.height * 0.1),
              shape: RoundedRectangleBorder(borderRadius: StaticsVar.br)
            ),
            onPressed: (){
              Navigator.push(
                context, 
                MaterialPageRoute(
                  builder: (context) => ChangeNotifierProvider.value(
                    value: notifier,
                    child: ServerHostWatingPage(),
                  )
                )
              );
            }, 
            icon: Icon(Icons.manage_accounts, size: 36),
            label: Text("我做房主", style: TextStyle(fontSize: 24))
          ),
          Divider(height: mediaQuery.size.height * 0.05, thickness: 3),
          Text("我加入联机", style: Theme.of(context).textTheme.headlineMedium),
          TextField(
            autocorrect: false,
            controller: connectpwdController,
            expands: false,
            maxLines: 1,
            keyboardType: TextInputType.visiblePassword,
            decoration: InputDecoration(
              labelText: "联机口令",
              border: OutlineInputBorder(
                borderRadius: StaticsVar.br,
                borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
              ),
              suffix: ElevatedButton(
                onPressed: () async {
                  connecting(context);
                }, 
                child: Text("加入")
              ),
            ),
            onSubmitted: (text) async {
              connecting(context);
            },
          ),
          SizedBox(height: mediaQuery.size.height * 0.02),
          ElevatedButton.icon(
            onPressed: () {
              if(isScaning) scannerController.stop();
              setState(() {
                isScaning = !isScaning;
              });
            }, 
            icon: Icon(isScaning ? Icons.stop : Icons.qr_code_scanner),
            label: Text(isScaning ? "停止扫描" : "扫描二维码")
          ),
          if(isScaning) SizedBox(
            width: mediaQuery.size.width * 0.8,
            height: mediaQuery.size.height * 0.4,
            child: MobileScanner(
              controller: scannerController,
              fit: BoxFit.scaleDown,
              onDetect: (barcodes) {
                if(5 > (barcodes.barcodes.first.rawValue??"").length || 8 < (barcodes.barcodes.first.rawValue??"").length) return;
                connectpwdController.text = barcodes.barcodes.first.rawValue??"";
                connecting(context);
              },
            ),
          ),
          if(isconnecting) CircularProgressIndicator()
        ],
      ),
    );
  }
}

class ServerHostWatingPage extends StatefulWidget {
  const ServerHostWatingPage({super.key});

  @override
  State<StatefulWidget> createState() => _ServerHostWatingPage();
}

class _ServerHostWatingPage extends State<ServerHostWatingPage> {
  @override
  Widget build(BuildContext context) {
    MediaQueryData mediaQuery = MediaQuery.of(context);
    return context.watch<PKServer>().connected 
    ? Scaffold(
      appBar: AppBar(title: Text("连接成功")),
      body: Center(
        child: Column(
          children: [
            SizedBox(height: mediaQuery.size.height * 0.1),
            TextContainer(text: "你们双方有一下共有词库，请选择其中的课程开始", style: Theme.of(context).textTheme.headlineMedium),
            SizedBox(height: mediaQuery.size.height * 0.05),
            ...List.generate(context.read<PKServer>().selectableSource.length, (int index) => Text(context.read<PKServer>().selectableSource[index].sourceJsonFileName), growable: false),
            SizedBox(height: mediaQuery.size.height * 0.1),
            ElevatedButton(
              onPressed: () async {
                ClassSelection selection = await popSelectClasses(context, forceSelectRange: context.read<PKServer>().selectableSource, withCache: false, withReviewChoose: false);
                if(!context.mounted) return;
                context.read<PKServer>().classSelection = selection;
                PKServer notifier = context.read<PKServer>();
                Navigator.push(
                  context, 
                  MaterialPageRoute(builder: (context) => ChangeNotifierProvider.value(
                    value: notifier,
                    child: PKPreparePage(),
                  ))
                );
              }, 
              child: Text("开始选课")
            )
          ],
        ),
      ),
    )
    : FutureBuilder(
      future: context.read<PKServer>().startHost(), 
      initialData: false,
      builder: (context, snapshot) {
        return Scaffold(
          appBar: AppBar(title: Text(snapshot.data??false ? "等待其他人进入..." : "正在启动服务")),
          body: Center(
            child: snapshot.data??false
                  ? Center(child: Column(
                    children: [
                      Text("联机口令:\n${context.read<PKServer>().connectpwd}", style: Theme.of(context).textTheme.displayMedium),
                      SizedBox(height: mediaQuery.size.height * 0.1),
                      Container(
                        padding: EdgeInsets.all(8.0),
                        decoration: BoxDecoration(
                          borderRadius: StaticsVar.br,
                          color: Colors.white
                        ),
                        child: QrImageView(
                          data: context.read<PKServer>().connectpwd!,
                          backgroundColor: Colors.white,
                          version: QrVersions.auto,
                          size: min(mediaQuery.size.width, mediaQuery.size.height) * 0.4,
                        ),
                      ),
                    ],
                  ))
                  : CircularProgressIndicator(semanticsLabel: "服务加载中")
          ),
        );
      }
    );
  }
}

class ClientWatingPage extends StatefulWidget {
  const ClientWatingPage({super.key});

  @override
  State<StatefulWidget> createState() => _ClientWatingPage();
}

class _ClientWatingPage extends State<ClientWatingPage> {
  
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: context.read<PKServer>().watingSelection(),
      builder: (context, asyncSnapshot) {
        return asyncSnapshot.hasData 
        ? PKPreparePage()
        : Scaffold(
          appBar: AppBar(title: Text("连接成功")),
          body: Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              Text("正在等待房主选择课程")
            ]
          ))
        );
      }
    );
  }
}

class PKPreparePage extends StatelessWidget {
  const PKPreparePage({super.key});

  @override
  Widget build(BuildContext context) {
    MediaQueryData mediaQuery = MediaQuery.of(context);

    return Scaffold(
      appBar: AppBar(title: Text("请准备")),
      body: Center(
        child: Column(
          children: [
            SizedBox(height: mediaQuery.size.height * 0.05),
            TextContainer(text: "已选择以下课程，准备完成后开始"),
            ...List.generate(context.read<PKServer>().classSelection!.selectedClass.length, (int index) => Text(context.read<PKServer>().classSelection!.selectedClass[index].className), growable: false),
            SizedBox(height: mediaQuery.size.height * 0.1),
            ElevatedButton(
              onPressed: (){
                // TODO
              }, 
              child: Text("准备")
            )
          ],
        ),
      ),
    );
  }
}