import 'dart:convert';

import 'package:arabic_learning/funcs/ai_service.dart';
import 'package:arabic_learning/funcs/quiz_bank.dart';
import 'package:arabic_learning/vars/config_structure.dart' show WordItem;
import 'package:arabic_learning/vars/statics_var.dart';
import 'package:flutter/material.dart';

class AiChatPage extends StatefulWidget {
  final WordItem word;
  final QuizType quizType;
  final QuizDifficulty difficulty;
  final String errorMessage;
  final String rawResponse;
  final String systemPrompt;
  final String userPrompt;

  const AiChatPage({
    super.key,
    required this.word,
    required this.quizType,
    required this.difficulty,
    required this.errorMessage,
    required this.rawResponse,
    required this.systemPrompt,
    required this.userPrompt,
  });

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _ChatMessage {
  final String role; // 'user', 'assistant', 'system'
  final String content;
  final bool parsed;

  const _ChatMessage({required this.role, required this.content, this.parsed = false});
}

class _AiChatPageState extends State<AiChatPage> {
  final List<_ChatMessage> _messages = [];
  final List<Map<String, String>> _apiMessages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _loading = false;
  List<QuizItem>? _parsedItems;
  bool _showRaw = false;

  @override
  void initState() {
    super.initState();
    _apiMessages.addAll([
      {'role': 'user', 'content': widget.userPrompt},
      {'role': 'assistant', 'content': widget.rawResponse},
    ]);
    _messages.add(_ChatMessage(
      role: 'system',
      content: 'AI 返回的内容无法解析为有效题目格式。\n\n错误信息：${widget.errorMessage}',
    ));
    _messages.add(_ChatMessage(
      role: 'system',
      content: '已自动向 AI 发送格式修正请求，请稍候…',
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoFix());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    AiService().cancel();
    super.dispose();
  }

  Future<void> _autoFix() async {
    const fixMsg = '你的上一份回复无法被解析为有效的 JSON 格式。'
        '请严格按照格式要求，重新输出只包含有效 JSON 的回复，'
        '不要包含任何 JSON 之外的说明文字（如 ```json 标记、解释文字等）。'
        '直接输出纯 JSON 对象。';
    _apiMessages.add({'role': 'user', 'content': fixMsg});
    _messages.add(_ChatMessage(role: 'user', content: fixMsg));
    await _sendToAi();
  }

  Future<void> _sendToAi() async {
    setState(() => _loading = true);
    _scrollToBottom();
    try {
      final raw = await AiService().sendConversation(
        systemPrompt: widget.systemPrompt,
        messages: List.unmodifiable(_apiMessages),
      );
      if (!mounted) return;

      final parsed = _tryParseQuizResponse(raw, widget.word, widget.quizType, widget.difficulty);
      _apiMessages.add({'role': 'assistant', 'content': raw});
      _messages.add(_ChatMessage(role: 'assistant', content: raw, parsed: parsed != null));
      if (parsed != null) {
        _parsedItems = parsed;
      }
    } on AiException catch (e) {
      if (!mounted) return;
      _messages.add(_ChatMessage(
        role: 'system',
        content: '请求失败：${e.userMessage}',
      ));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _scrollToBottom();
      }
    }
  }

  List<QuizItem>? _tryParseQuizResponse(
    String raw,
    WordItem word,
    QuizType quizType,
    QuizDifficulty difficulty,
  ) {
    Map<String, dynamic>? parsed;
    try {
      parsed = jsonDecode(raw.trim()) as Map<String, dynamic>;
    } catch (_) {
      final m = RegExp(r'```(?:json)?\s*([\s\S]+?)\s*```').firstMatch(raw);
      if (m != null) {
        try {
          parsed = jsonDecode(m.group(1)!.trim()) as Map<String, dynamic>;
        } catch (_) {}
      }
    }
    if (parsed == null) {
      final m = RegExp(r'\{[\s\S]+\}').firstMatch(raw);
      if (m != null) {
        try {
          parsed = jsonDecode(m.group(0)!) as Map<String, dynamic>;
        } catch (_) {}
      }
    }
    if (parsed == null || parsed['questions'] is! List || (parsed['questions'] as List).isEmpty) {
      return null;
    }
    final List<dynamic> questions = parsed['questions'] as List<dynamic>;
    return questions
        .asMap()
        .entries
        .map((e) => QuizItem.fromAiResponse(
              e.value as Map<String, dynamic>,
              word,
              e.key,
              quizType: quizType,
              difficulty: difficulty,
            ))
        .where((q) => q.sentence.isNotEmpty)
        .toList();
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;
    _controller.clear();
    _apiMessages.add({'role': 'user', 'content': text});
    _messages.add(_ChatMessage(role: 'user', content: text));
    _sendToAi();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 格式修正'),
        actions: [
          if (_parsedItems != null)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, _parsedItems),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('使用这些题目'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildErrorCard(theme),
          Expanded(child: _buildChatList(theme)),
          _buildInput(theme),
        ],
      ),
    );
  }

  Widget _buildErrorCard(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withAlpha(120),
        borderRadius: StaticsVar.br,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: StaticsVar.br,
            onTap: () => setState(() => _showRaw = !_showRaw),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, size: 16, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI 原始响应格式异常，正在尝试修正…',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                  Icon(
                    _showRaw ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ],
              ),
            ),
          ),
          if (_showRaw)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 120),
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  widget.rawResponse,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChatList(ThemeData theme) {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _messages.length + (_loading ? 1 : 0),
      itemBuilder: (context, i) {
        if (_loading && i == _messages.length) {
          return _buildTypingIndicator(theme);
        }
        final msg = _messages[i];
        if (msg.role == 'system') {
          return _buildSystemBubble(theme, msg);
        }
        final isUser = msg.role == 'user';
        return _buildChatBubble(theme, msg, isUser);
      },
    );
  }

  Widget _buildSystemBubble(ThemeData theme, _ChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(msg.content, style: const TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
        ),
      ),
    );
  }

  Widget _buildChatBubble(ThemeData theme, _ChatMessage msg, bool isUser) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.primary,
              child: const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: msg.role == 'assistant' && !isUser
                  ? _buildAssistantContent(theme, msg)
                  : Text(msg.content, style: const TextStyle(fontSize: 14)),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildAssistantContent(ThemeData theme, _ChatMessage msg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (msg.parsed)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green, width: 1.5),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 16, color: Colors.green),
                SizedBox(width: 6),
                Text('此回复已成功解析', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
              ],
            ),
          )
        else
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber, size: 14, color: Colors.orange),
                SizedBox(width: 4),
                Text('未能解析', style: TextStyle(fontSize: 11, color: Colors.orange)),
              ],
            ),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: SingleChildScrollView(
            child: Text(msg.content, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
          ),
        ),
      ],
    );
  }

  Widget _buildTypingIndicator(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.primary,
            child: const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const SizedBox(
              width: 40,
              height: 20,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(ThemeData theme) {
    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, MediaQuery.of(context).viewInsets.bottom + 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !_loading,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: _parsedItems != null ? '题目已成功解析，点击上方按钮使用' : '输入消息与 AI 沟通…',
                border: OutlineInputBorder(borderRadius: StaticsVar.br),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                isDense: true,
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _loading || _controller.text.trim().isEmpty ? null : _sendMessage,
            icon: const Icon(Icons.send, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
