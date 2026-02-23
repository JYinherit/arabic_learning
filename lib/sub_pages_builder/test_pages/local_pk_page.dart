import 'package:arabic_learning/funcs/local_pk_server.dart';
import 'package:arabic_learning/funcs/ui.dart';
import 'package:arabic_learning/vars/statics_var.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';


class LocalPKSelectPage extends StatefulWidget {
  const LocalPKSelectPage({super.key});

  @override
  State<StatefulWidget> createState() => _LocalPKSelectPage();
}
class _LocalPKSelectPage extends State<LocalPKSelectPage> {
  final TextEditingController connectpwdController = TextEditingController();
  bool isconnecting = false;

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
              fixedSize: Size(mediaQuery.size.width * 0.8, mediaQuery.size.height * 0.2),
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
            label: Text("我做房主（邀请别人）", style: TextStyle(fontSize: 36))
          ),
          Divider(height: mediaQuery.size.height * 0.1, thickness: 3),
          Text("我加入联机", style: Theme.of(context).textTheme.displaySmall),
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
                  if(isconnecting) return;
                  setState(() {
                    isconnecting = true;
                  });
                  int statue = await context.read<PKServer>().testConnect(connectpwdController.text);
                }, 
                child: Text("加入")
              ),
            ),
            onSubmitted: (text) async {
              if(isconnecting) return;
              setState(() {
                isconnecting = true;
              });
              int statue = await context.read<PKServer>().testConnect(text);
            },
          ),
          SizedBox(height: mediaQuery.size.height * 0.1),
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
              onPressed: (){
                popSelectClasses(context, forceSelectRange: context.read<PKServer>().selectableSource);
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
                  ? Text("联机口令: ${context.read<PKServer>().connectpwd}", style: Theme.of(context).textTheme.displayMedium)
                  : CircularProgressIndicator(semanticsLabel: "服务加载中")
          ),
        );
      }
    );
  }
}