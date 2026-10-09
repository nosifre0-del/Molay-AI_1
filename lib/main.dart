import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MolayApp());

const Color kBg = Color(0xFF09060F);
const Color kPanel = Color(0xFF130B1C);
const Color kPurple = Color(0xFFC78CFF);
const Color kGold = Color(0xFFE8A317);
const Color kBlue = Color(0xFF8CC7FF);

class MolayApp extends StatelessWidget {
  const MolayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Molay AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.dark(primary: kPurple, secondary: kGold),
      ),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const ChatPage(),
    );
  }
}

class Settings {
  String serverUrl;
  String apiKey;
  String model;
  bool speak;
  Settings({
    this.serverUrl = 'http://192.168.1.20:8000',
    this.apiKey = '',
    this.model = '',
    this.speak = true,
  });
}

class Msg {
  final bool fromUser;
  final String text;
  final Uint8List? image;
  Msg(this.fromUser, this.text, {this.image});
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FlutterTts _tts = FlutterTts();
  final List<Msg> _msgs = [
    Msg(false,
        'مولاي، أنا Molay AI v5.\nأستطيع المحادثة والبحث الحي وتوليد الشيفرات والصور عبر الخادم الذي تضبطه.'),
  ];

  Settings _s = Settings();
  String _mode = 'chat'; // chat | code
  bool _liveSearch = true;
  bool _tor = false;
  bool _busy = false;
  String _status = 'جاهز — اضبط عنوان الخادم ومفتاح API أولًا';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------- الإعدادات ----------
  Future<void> _loadSettings() async {
    try {
      final p = await SharedPreferences.getInstance();
      setState(() {
        _s = Settings(
          serverUrl: p.getString('server_url') ?? 'http://192.168.1.20:8000',
          apiKey: p.getString('api_key') ?? '',
          model: p.getString('model') ?? '',
          speak: p.getBool('speak') ?? true,
        );
      });
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('server_url', _s.serverUrl);
      await p.setString('api_key', _s.apiKey);
      await p.setString('model', _s.model);
      await p.setBool('speak', _s.speak);
    } catch (_) {}
  }

  // ---------- الشبكة ----------
  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> payload) async {
    final base = _s.serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final res = await http
        .post(
          Uri.parse('$base$path'),
          headers: {
            'Content-Type': 'application/json',
            'X-API-Key': _s.apiKey,
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 180));
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode >= 400) {
      String detail = body;
      try {
        final d = jsonDecode(body);
        if (d is Map && d['detail'] != null) detail = d['detail'].toString();
      } catch (_) {}
      throw Exception('(${res.statusCode}) $detail');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  void _add(Msg m, {String? status}) {
    setState(() {
      _msgs.add(m);
      if (status != null) _status = status;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _speak(String text) async {
    if (!_s.speak) return;
    try {
      await _tts.setLanguage('ar');
      await _tts.speak(text.length > 1200 ? text.substring(0, 1200) : text);
    } catch (_) {}
  }

  String? _takeInput(String emptyMsg) {
    final t = _input.text.trim();
    if (t.isEmpty) {
      setState(() => _status = emptyMsg);
      return null;
    }
    _input.clear();
    return t;
  }

  // ---------- الأوامر ----------
  Future<void> _submit() async {
    if (_busy) return;
    final message = _takeInput('اكتب طلبًا أولًا');
    if (message == null) return;
    _add(Msg(true, message), status: 'أبحث وأعالج طلبك...');
    setState(() => _busy = true);
    try {
      final r = await _post('/ask', {
        'message': message,
        'use_search': _liveSearch,
        'use_tor': _tor,
        'mode': _mode,
        'model': _s.model.isEmpty ? null : _s.model,
      });
      var answer = (r['answer'] ?? 'لا توجد إجابة.').toString();
      final sources = (r['sources'] as List?) ?? [];
      if (sources.isNotEmpty) {
        answer += '\n\nالمصادر التي استُرجعت:\n' +
            sources
                .take(7)
                .map((x) => '- ${x['title'] ?? ''} — ${x['url'] ?? ''}')
                .join('\n');
      }
      _add(Msg(false, answer), status: 'اكتمل');
      _speak(answer);
    } catch (e) {
      _add(
          Msg(false,
              'تعذّر الاتصال بالخادم:\n$e\n\nتحقق من عنوان الخادم، الشبكة، API Key، وتشغيل Ollama والخادم.'),
          status: 'فشل الاتصال');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _search() async {
    if (_busy) return;
    final query = _takeInput('اكتب عبارة البحث في مربع الرسالة');
    if (query == null) return;
    _add(Msg(true, 'بحث: $query'), status: 'جارٍ البحث...');
    setState(() => _busy = true);
    try {
      final r = await _post(
          '/search', {'query': query, 'use_tor': _tor, 'limit': 10});
      final items = (r['results'] as List?) ?? [];
      final text = items.isEmpty
          ? 'لم تُعثر على نتائج.'
          : items
              .asMap()
              .entries
              .map((e) =>
                  '${e.key + 1}. ${e.value['title']}\n${e.value['url']}\n${e.value['snippet'] ?? ''}')
              .join('\n\n');
      _add(Msg(false, text), status: 'اكتمل البحث — ${items.length} نتيجة');
    } catch (e) {
      _add(Msg(false, 'فشل البحث: $e'), status: 'فشل البحث');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generateImage() async {
    if (_busy) return;
    final prompt = _takeInput('اكتب وصف الصورة أولًا');
    if (prompt == null) return;
    _add(Msg(true, 'طلب توليد صورة: $prompt'),
        status: 'توليد الصورة عبر الخادم...');
    setState(() => _busy = true);
    try {
      final r = await _post(
          '/images/generate', {'prompt': prompt, 'aspect_ratio': '1:1'});
      final bytes = base64Decode(r['image_base64'].toString());
      _add(Msg(false, 'تم توليد الصورة.', image: bytes),
          status: 'اكتمل توليد الصورة');
    } catch (e) {
      _add(
          Msg(false,
              'تعذّر توليد الصورة: $e\nتأكد من ضبط STABILITY_API_KEY على الخادم.'),
          status: 'تعذّر توليد الصورة');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clear() {
    setState(() {
      _msgs
        ..clear()
        ..add(Msg(false, 'تم مسح الشاشة.'));
      _status = 'جاهز';
    });
  }

  Future<void> _openSettings() async {
    final server = TextEditingController(text: _s.serverUrl);
    final key = TextEditingController(text: _s.apiKey);
    final model = TextEditingController(text: _s.model);
    bool speak = _s.speak;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: kPanel,
          title: const Text('إعدادات Molay AI'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('قراءة الردود بصوت الهاتف'),
                  value: speak,
                  onChanged: (v) => setD(() => speak = v),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: server,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'عنوان الخادم',
                    hintText: 'http://192.168.1.20:8000',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: key,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: model,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'اسم النموذج (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                _s = Settings(
                  serverUrl: server.text.trim(),
                  apiKey: key.text.trim(),
                  model: model.text.trim(),
                  speak: speak,
                );
                await _saveSettings();
                if (mounted) setState(() => _status = 'تم حفظ الإعدادات');
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- الواجهة ----------
  Widget _modeButton(String label, String mode, String status) {
    final selected = _mode == mode;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: selected
            ? FilledButton(
                onPressed: () => setState(() {
                  _mode = mode;
                  _status = status;
                }),
                child: Text(label),
              )
            : OutlinedButton(
                onPressed: () => setState(() {
                  _mode = mode;
                  _status = status;
                }),
                child: Text(label),
              ),
      ),
    );
  }

  Widget _bubble(Msg m) {
    final bg = m.fromUser ? const Color(0xFF2A1745) : kPanel;
    return Align(
      alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.92),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.fromUser ? 'أنت' : 'Molay AI',
                style: TextStyle(
                    color: m.fromUser ? kGold : kPurple,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
            const SizedBox(height: 4),
            SelectableText(m.text,
                style: const TextStyle(fontSize: 15, height: 1.5)),
            if (m.image != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(m.image!, fit: BoxFit.contain),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBg,
        title: const Text('Molay AI',
            style: TextStyle(color: kPurple, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
              tooltip: 'مسح الشاشة',
              onPressed: _clear,
              icon: const Icon(Icons.delete_outline)),
          IconButton(
              tooltip: 'الإعدادات',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings)),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 4, 9, 0),
              child: Row(
                children: [
                  _modeButton('محادثة', 'chat', 'وضع المحادثة'),
                  _modeButton('برمجة', 'code', 'وضع البرمجة'),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: OutlinedButton(
                          onPressed: _busy ? null : _search,
                          child: const Text('بحث')),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: OutlinedButton(
                          onPressed: _busy ? null : _generateImage,
                          child: const Text('صورة')),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                const SizedBox(width: 8),
                Checkbox(
                    value: _liveSearch,
                    onChanged: (v) => setState(() => _liveSearch = v ?? true)),
                const Text('بحث ويب حي'),
                const SizedBox(width: 8),
                Checkbox(
                    value: _tor,
                    onChanged: (v) => setState(() => _tor = v ?? false)),
                const Flexible(
                    child: Text('Tor (يتطلب إعداد الخادم)',
                        overflow: TextOverflow.ellipsis)),
              ],
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _msgs.length,
                itemBuilder: (_, i) => _bubble(_msgs[i]),
              ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(_status,
                    style: const TextStyle(color: kBlue, fontSize: 12)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: 'اكتب سؤالك أو ما تريد برمجته...',
                        filled: true,
                        fillColor: kPanel,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16)),
                    child: const Text('إرسال'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}