import 'package:flutter/foundation.dart';

import 'gigachat_client.dart';
import 'gigachat_config.dart';

/// Одна реплика в окне чата.
class RecommendMessage {
  const RecommendMessage({required this.text, required this.fromUser});

  final String text;
  final bool fromUser;
}

/// Состояние окна «GigaChat: похожие исполнители».
///
/// Держит историю диалога, поэтому окно можно закрыть и открыть снова —
/// переписка сохранится до перезапуска приложения.
class RecommendChat extends ChangeNotifier {
  RecommendChat({GigaChatClient? client}) : _client = client ?? GigaChatClient();

  /// Общий экземпляр на всё приложение (история живёт между переходами).
  static final RecommendChat shared = RecommendChat();

  static const String greeting =
      'Я подбираю только музыку: напиши исполнителей или группы, которые ты '
      'слушаешь, — предложу похожих и подскажу, с каких песен начать.';

  static const List<String> suggestions = <String>[
    'Кино',
    'Nirvana',
    'Miyagi',
    'Molchat Doma',
  ];

  final GigaChatClient _client;
  final List<RecommendMessage> _messages = <RecommendMessage>[
    const RecommendMessage(text: greeting, fromUser: false),
  ];
  final List<GigaChatMessage> _history = <GigaChatMessage>[];

  bool _busy = false;
  String? _error;

  List<RecommendMessage> get messages => List.unmodifiable(_messages);

  bool get busy => _busy;

  String? get error => _error;

  /// Показать подсказки со стартовыми исполнителями.
  bool get showSuggestions => _messages.length == 1 && !_busy;

  bool get canReset => _messages.length > 1 || _error != null;

  /// Отправляет сообщение пользователя в GigaChat и добавляет ответ.
  Future<void> send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) {
      return;
    }

    _messages.add(RecommendMessage(text: text, fromUser: true));
    _history.add(GigaChatMessage.user(text));
    _error = null;
    _busy = true;
    notifyListeners();

    try {
      final reply = await _client.complete(_trimmedHistory());
      _messages.add(RecommendMessage(text: reply, fromUser: false));
      _history.add(GigaChatMessage.assistant(reply));
      _trimHistory();
    } on GigaChatException catch (error) {
      _error = error.message;
      if (error.status == 401) {
        _client.resetToken();
      }
    } catch (error) {
      _error = 'Не удалось получить ответ GigaChat: $error';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Начинает диалог заново.
  void reset() {
    if (_busy) {
      return;
    }
    _messages
      ..clear()
      ..add(const RecommendMessage(text: greeting, fromUser: false));
    _history.clear();
    _error = null;
    notifyListeners();
  }

  List<GigaChatMessage> _trimmedHistory() {
    if (_history.length <= GigaChatConfig.historyLimit) {
      return List<GigaChatMessage>.from(_history);
    }
    return _history.sublist(_history.length - GigaChatConfig.historyLimit);
  }

  void _trimHistory() {
    while (_history.length > GigaChatConfig.historyLimit) {
      _history.removeAt(0);
    }
  }
}
