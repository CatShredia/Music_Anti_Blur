import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'recommend_chat.dart';

/// Открывает окно чата с GigaChat поверх главной страницы.
Future<void> showGigaChatRecommendations(
  BuildContext context,
  RecommendChat chat,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => GigaChatChatSheet(chat: chat),
  );
}

/// Компактная карточка-вход на главной странице.
class GigaChatRecommendCard extends StatelessWidget {
  const GigaChatRecommendCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: VizeColors.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VizeRadii.card),
        side: const BorderSide(color: VizeColors.accentDim),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VizeRadii.card),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: VizeColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: VizeColors.accentDim),
                ),
                child: const Icon(Icons.auto_awesome, size: 20, color: VizeColors.accentMuted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('GigaChat', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(width: 8),
                        const AiBadge(),
                      ],
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Напиши, что слушаешь — подберу похожих исполнителей',
                      style: TextStyle(fontSize: 12.5, height: 1.3, color: VizeColors.accentMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: VizeColors.accentMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Небольшая метка «AI» рядом с названием модели.
class AiBadge extends StatelessWidget {
  const AiBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: VizeColors.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(VizeRadii.pill),
      ),
      child: const Text(
        'AI',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: VizeColors.accentMuted),
      ),
    );
  }
}

/// Окно чата: пишем исполнителей — получаем похожих.
class GigaChatChatSheet extends StatefulWidget {
  const GigaChatChatSheet({super.key, required this.chat});

  final RecommendChat chat;

  @override
  State<GigaChatChatSheet> createState() => _GigaChatChatSheetState();
}

class _GigaChatChatSheetState extends State<GigaChatChatSheet> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.chat.addListener(_scrollToBottom);
    _scrollToBottom();
  }

  @override
  void dispose() {
    widget.chat.removeListener(_scrollToBottom);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) {
        return;
      }
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _submit([String? value]) {
    final text = (value ?? _input.text).trim();
    if (text.isEmpty || widget.chat.busy) {
      return;
    }
    _input.clear();
    widget.chat.send(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final height = ((media.size.height - keyboard) * 0.88)
        .clamp(300.0, media.size.height * 0.92)
        .toDouble();

    return ListenableBuilder(
      listenable: widget.chat,
      builder: (context, _) => Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: Container(
          height: height,
          decoration: const BoxDecoration(
            color: VizeColors.bgElevated,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: VizeColors.stroke)),
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: VizeColors.stroke,
                        borderRadius: BorderRadius.circular(VizeRadii.pill),
                      ),
                    ),
                  ),
                ),
                _header(context),
                const Divider(height: 1, thickness: 1, color: VizeColors.stroke),
                Expanded(child: _messages()),
                if (widget.chat.error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                    child: VizeFormBanner(message: widget.chat.error!),
                  ),
                if (widget.chat.showSuggestions) _suggestions(),
                _composer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 6, 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: VizeColors.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: VizeColors.accentDim),
            ),
            child: const Icon(Icons.auto_awesome, size: 18, color: VizeColors.accentMuted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('GigaChat', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(width: 8),
                    const AiBadge(),
                  ],
                ),
                const SizedBox(height: 1),
                const Text(
                  'Подбор похожих исполнителей',
                  style: TextStyle(fontSize: 12, color: VizeColors.accentMuted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Новый диалог',
            onPressed: widget.chat.canReset ? widget.chat.reset : null,
            icon: const Icon(Icons.refresh, size: 20),
          ),
          IconButton(
            tooltip: 'Закрыть',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _messages() {
    final messages = widget.chat.messages;
    final typing = widget.chat.busy;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      itemCount: messages.length + (typing ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= messages.length) {
          return const _TypingBubble();
        }
        return _Bubble(message: messages[index]);
      },
    );
  }

  Widget _suggestions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final suggestion in RecommendChat.suggestions)
            VizeChip(
              label: suggestion,
              selected: false,
              onTap: () => _submit(suggestion),
            ),
        ],
      ),
    );
  }

  Widget _composer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: (value) => _submit(value),
              decoration: const InputDecoration(
                hintText: 'Кино, Nirvana, Miyagi…',
                counterText: '',
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            height: 48,
            child: Material(
              color: widget.chat.busy ? VizeColors.surface : VizeColors.accent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.chat.busy ? null : () => _submit(),
                child: Center(
                  child: widget.chat.busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: VizeColors.accentMuted,
                          ),
                        )
                      : const Icon(Icons.arrow_upward, color: VizeColors.textOnAccent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final RecommendMessage message;

  @override
  Widget build(BuildContext context) {
    final fromUser = message.fromUser;
    final width = MediaQuery.of(context).size.width;
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        constraints: BoxConstraints(maxWidth: width * 0.78),
        decoration: BoxDecoration(
          color: fromUser ? VizeColors.accent : VizeColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(fromUser ? 16 : 4),
            bottomRight: Radius.circular(fromUser ? 4 : 16),
          ),
          border: fromUser ? null : Border.all(color: VizeColors.stroke),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            fontSize: 14.5,
            height: 1.4,
            color: fromUser ? VizeColors.textOnAccent : VizeColors.text,
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: VizeColors.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: VizeColors.stroke),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: VizeColors.accentMuted),
            ),
            const SizedBox(width: 10),
            const Text(
              'GigaChat подбирает музыку…',
              style: TextStyle(fontSize: 13.5, color: VizeColors.accentMuted),
            ),
          ],
        ),
      ),
    );
  }
}
