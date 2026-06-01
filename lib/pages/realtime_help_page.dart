import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../theme/route_in_palette.dart';

const _faqAssetPath = 'server/qna_server/routein_faq.json';
const _apiKeyAssetPath = 'server/API_KEY.txt';
const _imagePromptAssetPath = 'server/image_prompt.md';
const _textPromptAssetPath = 'server/text_prompt.md';
const _defaultGeminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
const _defaultGeminiModel = String.fromEnvironment(
  'GEMINI_MODEL',
  defaultValue: 'gemini-2.5-flash',
);

class RealtimeHelpPage extends StatefulWidget {
  const RealtimeHelpPage({super.key});

  @override
  State<RealtimeHelpPage> createState() => _RealtimeHelpPageState();
}

class _RealtimeHelpPageState extends State<RealtimeHelpPage> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController(
    text: _defaultGeminiApiKey,
  );
  final ImagePicker _imagePicker = ImagePicker();
  late final Future<List<RealtimeFaqItem>> _faqItemsFuture = _loadFaqItems();
  late final Future<String> _imagePromptFuture = _loadImagePrompt();
  late final Future<String> _textPromptFuture = _loadTextPrompt();

  final List<_ChatMessage> _messages = const [
    _ChatMessage(
      text:
          '안녕하세요. FAQ를 바탕으로 지하철 이용 중 생긴 문제를 도와드릴게요. Gemini API 키를 넣으면 FAQ 내용을 참고해 더 자연스럽게 답변합니다.',
      isUser: false,
    ),
  ].toList();

  bool _isSending = false;
  _SelectedImage? _selectedImage;

  @override
  void initState() {
    super.initState();
    _loadApiKeyFromAsset();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: RouteInPalette.white,
        appBar: AppBar(
          title: const Text('실시간 문제 해결'),
          actions: [
            IconButton(
              onPressed: _showApiKeyDialog,
              icon: const Icon(Icons.key_rounded),
              tooltip: 'Gemini API 키 설정',
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.chat_bubble_outline_rounded), text: '챗봇'),
              Tab(icon: Icon(Icons.help_outline_rounded), text: 'FAQ'),
            ],
          ),
        ),
        body: FutureBuilder<List<RealtimeFaqItem>>(
          future: _faqItemsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _FaqLoadError(error: snapshot.error.toString());
            }

            final faqItems = snapshot.data ?? const [];

            return TabBarView(
              children: [
                _ChatbotPanel(
                  messages: _messages,
                  controller: _messageController,
                  isSending: _isSending,
                  hasApiKey: _apiKeyController.text.trim().isNotEmpty,
                  selectedImage: _selectedImage,
                  onSend: () => _sendMessage(faqItems),
                  onPickImage: _pickImage,
                  onRemoveImage: _removeImage,
                  onQuickQuestion: (question) =>
                      _askQuickQuestion(question, faqItems),
                ),
                _FaqPanel(items: faqItems),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<List<RealtimeFaqItem>> _loadFaqItems() async {
    final faqText = await rootBundle.loadString(_faqAssetPath);
    final faqJson = jsonDecode(faqText) as List<dynamic>;

    return faqJson
        .map((item) => RealtimeFaqItem.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<String> _loadImagePrompt() async {
    try {
      return (await rootBundle.loadString(_imagePromptAssetPath)).trim();
    } catch (_) {
      return '';
    }
  }

  Future<String> _loadTextPrompt() async {
    try {
      return (await rootBundle.loadString(_textPromptAssetPath)).trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _loadApiKeyFromAsset() async {
    if (_apiKeyController.text.trim().isNotEmpty) return;

    try {
      final apiKey = (await rootBundle.loadString(_apiKeyAssetPath)).trim();
      if (!mounted || apiKey.isEmpty) return;

      setState(() {
        _apiKeyController.text = apiKey;
      });
    } catch (_) {
      // API key file is optional. Missing or empty files keep FAQ-only mode.
    }
  }

  Future<void> _askQuickQuestion(
    String question,
    List<RealtimeFaqItem> faqItems,
  ) async {
    _messageController.text = question;
    await _sendMessage(faqItems);
  }

  Future<void> _sendMessage(List<RealtimeFaqItem> faqItems) async {
    final text = _messageController.text.trim();
    final selectedImage = _selectedImage;
    if ((text.isEmpty && selectedImage == null) || _isSending) return;

    final matchedFaqs = _findRelevantFaqItems(text, faqItems);

    setState(() {
      _messages.add(
        _ChatMessage(
          text: text.isEmpty ? '첨부한 사진을 확인해 주세요.' : text,
          isUser: true,
          imageLabel: selectedImage?.name,
        ),
      );
      _messageController.clear();
      _selectedImage = null;
      _isSending = true;
    });

    final textPrompt = await _textPromptFuture;
    final imagePrompt = selectedImage == null ? '' : await _imagePromptFuture;
    final reply = await _buildBotReply(
      text.isEmpty ? '첨부한 사진을 보고 현재 문제를 해결해 주세요.' : text,
      matchedFaqs,
      selectedImage,
      textPrompt,
      imagePrompt,
    );

    if (!mounted) return;

    setState(() {
      _messages.add(_ChatMessage(text: reply, isUser: false));
      _isSending = false;
    });
  }

  Future<String> _buildBotReply(
    String question,
    List<RealtimeFaqItem> matchedFaqs,
    _SelectedImage? selectedImage,
    String textPrompt,
    String imagePrompt,
  ) async {
    final apiKey = _apiKeyController.text.trim();

    if (apiKey.isEmpty) {
      final imageNotice = selectedImage == null
          ? ''
          : '\n\n사진 분석은 Gemini API 키가 있을 때만 사용할 수 있어요.';
      return '${_buildLocalFaqReply(matchedFaqs)}$imageNotice';
    }

    try {
      return await _GeminiFaqAnswerer(
        apiKey: apiKey,
        model: _defaultGeminiModel,
      ).answer(
        question: question,
        faqItems: matchedFaqs,
        image: selectedImage,
        textPrompt: textPrompt,
        imagePrompt: imagePrompt,
      );
    } on _GeminiRequestException catch (error) {
      _logGeminiError(error.userMessage);
      return _buildLocalFaqReply(matchedFaqs);
    } catch (error) {
      _logGeminiError(error.toString());
      return _buildLocalFaqReply(matchedFaqs);
    }
  }

  void _logGeminiError(String message) {
    debugPrint('Gemini answer request failed: $message');
  }

  String _buildLocalFaqReply(List<RealtimeFaqItem> matchedFaqs) {
    if (matchedFaqs.isEmpty) {
      return 'FAQ에서 바로 맞는 답을 찾지 못했어요. 질문에 역 이름, 카드/요금/분실물/출구처럼 핵심 단어를 함께 적어 주세요.';
    }

    final item = matchedFaqs.first;
    final steps = item.steps.isEmpty
        ? ''
        : '\n\n해결 순서\n${item.steps.map((step) => '- $step').join('\n')}';

    return '${item.answer}$steps';
  }

  List<RealtimeFaqItem> _findRelevantFaqItems(
    String query,
    List<RealtimeFaqItem> faqItems,
  ) {
    final normalizedQuery = _normalize(query);
    final queryTerms = normalizedQuery
        .split(RegExp(r'\s+'))
        .where((term) => term.length > 1)
        .toSet();

    final scored = <({RealtimeFaqItem item, int score})>[];

    for (final item in faqItems) {
      final searchableText = _normalize(
        '${item.category} ${item.question} ${item.answer}',
      );
      var score = 0;

      if (searchableText.contains(normalizedQuery)) {
        score += 20;
      }

      for (final term in queryTerms) {
        if (item.question.toLowerCase().contains(term)) score += 8;
        if (item.category.toLowerCase().contains(term)) score += 5;
        if (searchableText.contains(term)) score += 2;
      }

      if (score > 0) {
        scored.add((item: item, score: score));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(5).map((entry) => entry.item).toList(growable: false);
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w가-힣\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _showApiKeyDialog() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Gemini API 키'),
          content: TextField(
            controller: _apiKeyController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'API 키',
              hintText: 'AIza...',
              helperText: '비워두면 FAQ 매칭 답변만 사용합니다.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('저장'),
            ),
          ],
        );
      },
    );

    if (!mounted || saved != true) return;
    setState(() {});
  }

  Future<void> _pickImage() async {
    if (_isSending) return;

    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (image == null) return;

    final bytes = await image.readAsBytes();
    if (!mounted) return;

    setState(() {
      _selectedImage = _SelectedImage(
        name: image.name,
        mimeType: image.mimeType ?? _guessMimeType(image.name),
        bytes: bytes,
      );
    });
  }

  void _removeImage() {
    setState(() {
      _selectedImage = null;
    });
  }

  String _guessMimeType(String name) {
    final lowerName = name.toLowerCase();
    if (lowerName.endsWith('.png')) return 'image/png';
    if (lowerName.endsWith('.webp')) return 'image/webp';
    if (lowerName.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }
}

class _ChatbotPanel extends StatelessWidget {
  const _ChatbotPanel({
    required this.messages,
    required this.controller,
    required this.isSending,
    required this.hasApiKey,
    required this.selectedImage,
    required this.onSend,
    required this.onPickImage,
    required this.onRemoveImage,
    required this.onQuickQuestion,
  });

  final List<_ChatMessage> messages;
  final TextEditingController controller;
  final bool isSending;
  final bool hasApiKey;
  final _SelectedImage? selectedImage;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final VoidCallback onRemoveImage;
  final ValueChanged<String> onQuickQuestion;

  static const _quickQuestions = [
    '개찰구에서 카드가 안 찍혀요',
    '지하철 요금이 얼마예요?',
    '출구나 환승 통로를 못 찾겠어요',
    '분실물은 어디에 문의하나요?',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: RouteInPalette.sky,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasApiKey ? 'Gemini + FAQ 답변 모드' : 'FAQ 매칭 답변 모드',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: RouteInPalette.navy,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _quickQuestions.map((question) {
                  return ActionChip(
                    label: Text(question),
                    avatar: const Icon(Icons.flash_on_rounded, size: 18),
                    onPressed: isSending
                        ? null
                        : () => onQuickQuestion(question),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            itemCount: messages.length + (isSending ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == messages.length) {
                return const _ChatBubble(
                  message: _ChatMessage(text: '답변을 준비하고 있어요...', isUser: false),
                );
              }

              return _ChatBubble(message: messages[index]);
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: const BoxDecoration(
              color: RouteInPalette.white,
              border: Border(top: BorderSide(color: RouteInPalette.mist)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: !isSending,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: InputDecoration(
                      hintText: '문제를 입력하세요',
                      filled: true,
                      fillColor: RouteInPalette.mist.withValues(alpha: 0.34),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: isSending ? null : onPickImage,
                  icon: const Icon(Icons.photo_outlined),
                  tooltip: '사진 첨부',
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  onPressed: isSending ? null : onSend,
                  icon: const Icon(Icons.send_rounded),
                  tooltip: '보내기',
                ),
              ],
            ),
          ),
        ),
        if (selectedImage != null)
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              color: RouteInPalette.white,
              child: _SelectedImageBar(
                image: selectedImage!,
                onRemove: isSending ? null : onRemoveImage,
              ),
            ),
          ),
      ],
    );
  }
}

class _SelectedImageBar extends StatelessWidget {
  const _SelectedImageBar({required this.image, required this.onRemove});

  final _SelectedImage image;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: RouteInPalette.sky.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(
              image.bytes,
              width: 42,
              height: 42,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              image.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: RouteInPalette.navy,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
            tooltip: '첨부 삭제',
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alignment = message.isUser
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final background = message.isUser
        ? RouteInPalette.denim
        : RouteInPalette.sky.withValues(alpha: 0.48);
    final foreground = message.isUser
        ? RouteInPalette.white
        : RouteInPalette.ink;

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Text(
              message.imageLabel == null
                  ? message.text
                  : '${message.text}\n\n사진: ${message.imageLabel}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: foreground,
                height: 1.35,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FaqPanel extends StatelessWidget {
  const _FaqPanel({required this.items});

  final List<RealtimeFaqItem> items;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        return _FaqTile(item: item);
      },
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.item});

  final RealtimeFaqItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: RouteInPalette.sky.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => FaqDetailPage(item: item)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: item.color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(item.icon, color: RouteInPalette.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.category,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: RouteInPalette.denim,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.question,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class FaqDetailPage extends StatelessWidget {
  const FaqDetailPage({super.key, required this.item});

  final RealtimeFaqItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: RouteInPalette.white,
      appBar: AppBar(title: Text(item.category)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: item.color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(item.icon, color: RouteInPalette.white, size: 34),
                const SizedBox(height: 14),
                Text(
                  item.question,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: RouteInPalette.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            '답변',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            item.answer,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: RouteInPalette.navy,
              height: 1.45,
            ),
          ),
          if (item.steps.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              '해결 순서',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < item.steps.length; i++) ...[
              _StepRow(number: i + 1, text: item.steps[i]),
              if (i != item.steps.length - 1) const SizedBox(height: 10),
            ],
          ],
          if (item.sourceUrl.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              '출처',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.sourceUrl,
              style: theme.textTheme.bodySmall?.copyWith(
                color: RouteInPalette.denim,
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.check_rounded),
            label: const Text('확인했어요'),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RouteInPalette.sky.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: RouteInPalette.denim,
            foregroundColor: RouteInPalette.white,
            child: Text('$number'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: RouteInPalette.navy,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqLoadError extends StatelessWidget {
  const _FaqLoadError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('FAQ 데이터를 불러오지 못했어요.\n$error', textAlign: TextAlign.center),
      ),
    );
  }
}

class _GeminiFaqAnswerer {
  const _GeminiFaqAnswerer({required this.apiKey, required this.model});

  final String apiKey;
  final String model;

  Future<String> answer({
    required String question,
    required List<RealtimeFaqItem> faqItems,
    required _SelectedImage? image,
    required String textPrompt,
    required String imagePrompt,
  }) async {
    final mergedQuestion = image == null || imagePrompt.isEmpty
        ? question
        : '$question\n\n사진 분석 추가 프롬프트:\n$imagePrompt';
    final parts = <Map<String, dynamic>>[
      {
        'text':
            '사용자 질문: $mergedQuestion\n\n관련 FAQ:\n${faqItems.map((item) => item.toPromptText()).join('\n\n')}',
      },
      if (image != null)
        {
          'inline_data': {
            'mime_type': image.mimeType,
            'data': base64Encode(image.bytes),
          },
        },
    ];

    final response = await http.post(
      Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'systemInstruction': {
          'parts': [
            {
              'text':
                  '너는 한국 지하철 여행 앱 RouteIn의 문제 해결 챗봇이다. 제공된 FAQ와 첨부 사진을 근거로 답하고, 모르면 가까운 역무실이나 공식 고객센터 문의를 안내한다. 답변은 한국어로 짧고 실행 가능하게 작성한다.\n\n$textPrompt',
            },
          ],
        },
        'contents': [
          {'role': 'user', 'parts': parts},
        ],
        'generationConfig': {'temperature': 0.2, 'maxOutputTokens': 2048},
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _GeminiRequestException.fromResponse(response);
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final candidates = decoded['candidates'];
    if (candidates is List) {
      final texts = <String>[];
      final finishReasons = <String>[];
      for (final candidate in candidates) {
        if (candidate is! Map<String, dynamic>) continue;
        final finishReason = candidate['finishReason'];
        if (finishReason is String && finishReason.isNotEmpty) {
          finishReasons.add(finishReason);
        }
        final content = candidate['content'];
        if (content is! Map<String, dynamic>) continue;
        final responseParts = content['parts'];
        if (responseParts is! List) continue;
        for (final part in responseParts) {
          if (part is! Map<String, dynamic>) continue;
          final text = part['text'];
          if (text is String && text.trim().isNotEmpty) {
            texts.add(text.trim());
          }
        }
      }
      if (finishReasons.contains('MAX_TOKENS')) {
        throw const _GeminiRequestException(
          statusCode: 200,
          message: 'Gemini response was truncated by maxOutputTokens.',
          status: 'MAX_TOKENS',
          code: '',
          retryAfter: '',
        );
      }
      if (texts.isNotEmpty) return texts.join('\n');
    }

    throw '응답 본문에서 답변을 찾지 못했습니다.';
  }
}

class _GeminiRequestException implements Exception {
  const _GeminiRequestException({
    required this.statusCode,
    required this.message,
    required this.status,
    required this.code,
    required this.retryAfter,
  });

  factory _GeminiRequestException.fromResponse(http.Response response) {
    var message = utf8.decode(response.bodyBytes);
    var status = '';
    var code = '';

    try {
      final decoded = jsonDecode(message);
      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        message = error['message'] as String? ?? message;
        status = error['status'] as String? ?? '';
        code = error['code']?.toString() ?? '';
      }
    } catch (_) {
      // Non-JSON error bodies are still useful as-is.
    }

    return _GeminiRequestException(
      statusCode: response.statusCode,
      message: message,
      status: status,
      code: code,
      retryAfter: response.headers['retry-after'] ?? '',
    );
  }

  final int statusCode;
  final String message;
  final String status;
  final String code;
  final String retryAfter;

  String get userMessage {
    final details = [
      'HTTP $statusCode',
      if (status.isNotEmpty) 'status=$status',
      if (code.isNotEmpty) 'code=$code',
      if (retryAfter.isNotEmpty) 'retry-after=${retryAfter}s',
    ].join(', ');

    return '$details\n$message';
  }

  @override
  String toString() => userMessage;
}

class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.imageLabel,
  });

  final String text;
  final bool isUser;
  final String? imageLabel;
}

class _SelectedImage {
  const _SelectedImage({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
}

class RealtimeFaqItem {
  const RealtimeFaqItem({
    required this.id,
    required this.category,
    required this.question,
    required this.answer,
    required this.steps,
    required this.sourceUrl,
  });

  factory RealtimeFaqItem.fromJson(Map<String, dynamic> json) {
    return RealtimeFaqItem(
      id: json['id'] as int? ?? 0,
      category: json['category'] as String? ?? 'FAQ',
      question: json['question'] as String? ?? '',
      answer: json['answer'] as String? ?? '',
      steps: (json['steps'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      sourceUrl: json['source_url'] as String? ?? '',
    );
  }

  final int id;
  final String category;
  final String question;
  final String answer;
  final List<String> steps;
  final String sourceUrl;

  IconData get icon {
    if (category.contains('요금')) return Icons.payments_outlined;
    if (category.contains('카드')) return Icons.credit_card_rounded;
    if (category.contains('문제')) return Icons.support_agent_rounded;
    if (category.contains('분실')) return Icons.inventory_2_outlined;
    if (category.contains('환승') || category.contains('노선')) {
      return Icons.alt_route_rounded;
    }
    return Icons.help_outline_rounded;
  }

  Color get color {
    if (category.contains('문제')) return RouteInPalette.coral;
    if (category.contains('카드')) return RouteInPalette.denim;
    if (category.contains('요금')) return RouteInPalette.navy;
    return RouteInPalette.denim;
  }

  String toPromptText() {
    final stepText = steps.isEmpty ? '' : '\n해결 순서: ${steps.join(' / ')}';
    return '[$id] 분류: $category\n질문: $question\n답변: $answer$stepText';
  }
}
