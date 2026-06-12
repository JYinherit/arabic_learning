import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:arabic_learning/vars/statics_var.dart';
import 'package:arabic_learning/package_replacement/fake_dart_io.dart' if (dart.library.io) 'dart:io' as io;

/// 判断当前平台是否支持 WebView
bool get _supportsWebView => !kIsWeb && (io.Platform.isAndroid || io.Platform.isIOS);

/// 动词输入对话框（工具类，通过静态方法 show 调用）
class VerbInputDialog {
  const VerbInputDialog._();

  /// 弹出动词输入对话框，返回用户输入的动词（null 表示取消）
  static Future<String?> show(BuildContext context) {
    final TextEditingController controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('查询动词变位'),
        content: TextField(
          controller: controller,
          textDirection: TextDirection.rtl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '请输入阿拉伯语动词...',
            hintTextDirection: TextDirection.rtl,
            border: OutlineInputBorder(
              borderRadius: StaticsVar.br,
            ),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(context, value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final String verb = controller.text.trim();
              if (verb.isNotEmpty) {
                Navigator.pop(context, verb);
              }
            },
            child: const Text('查询'),
          ),
        ],
      ),
    );
  }
}

/// 动词变位查询页面
///
/// Android / iOS：应用内 WebView 加载 Qutrub
/// 桌面端 / Web：自动打开外部浏览器后返回
class VerbConjugationPage extends StatefulWidget {
  final String verb;
  const VerbConjugationPage({super.key, required this.verb});

  @override
  State<VerbConjugationPage> createState() => _VerbConjugationPageState();
}

class _VerbConjugationPageState extends State<VerbConjugationPage> {
  WebViewController? _controller;
  bool _isLoading = true;

  String get _qutrubUrl =>
      'https://qutrub.arabeyes.org/index/?verb=${Uri.encodeComponent(widget.verb)}';

  @override
  void initState() {
    super.initState();

    if (_supportsWebView) {
      // 移动端：使用 WebView
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              if (mounted) {
                setState(() => _isLoading = false);
              }
            },
          ),
        )
        ..loadRequest(Uri.parse(_qutrubUrl));
    } else {
      // 桌面端 / Web：打开外部浏览器后自动返回
      WidgetsBinding.instance.addPostFrameCallback((_) {
        launchUrl(Uri.parse(_qutrubUrl), mode: LaunchMode.externalApplication);
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 非 WebView 平台直接返回空壳（已在 initState 中打开浏览器并 pop）
    if (!_supportsWebView) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('动词变位: ${widget.verb}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: '在浏览器中打开',
            onPressed: () {
              launchUrl(
                Uri.parse(_qutrubUrl),
                mode: LaunchMode.externalApplication,
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_controller != null) WebViewWidget(controller: _controller!),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
