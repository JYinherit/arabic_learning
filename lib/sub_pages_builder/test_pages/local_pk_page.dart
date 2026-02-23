import 'package:arabic_learning/funcs/local_pk_server.dart';
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
                onPressed: () {
                  // TODO
                }, 
                child: Text("加入")
              ),
            ),
            onSubmitted: (text) {
              // TODO
            },
          ),
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
    return FutureBuilder(
      future: context.read<PKServer>().start(), 
      initialData: false,
      builder: (context, snapshot) {
        return Scaffold(
          appBar: AppBar(title: Text(snapshot.data??false ? "等待其他人进入" : "正在启动服务")),
          body: Center(
            child: snapshot.data??false
                  ? Text("联机口令: ${context.read<PKServer>().connectpwd}")
                  : CircularProgressIndicator(semanticsLabel: "服务加载中")
          ),
        );
      }
    );
  }
}