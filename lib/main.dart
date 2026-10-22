import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';

const Color navy = Color(0xFF183153);

const String aiEndpoint = String.fromEnvironment(
  'AI_ENDPOINT',
  defaultValue: 'https://cepasistan-ai.cepasistan-app-7416.workers.dev/chat',
);

const String monthlyProductId = 'cepasistan_pro_monthly';
const String yearlyProductId = 'cepasistan_pro_yearly';

// Ücretsiz günlük yapay zekâ hakkı. Sunucudaki FREE_LIMIT ile aynı olmalı.
const int freeDailyLimit = 5;

String get aiNoteEndpoint =>
    aiEndpoint.replaceFirst(RegExp(r'/chat$'), '/note');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));

  runApp(const CepAsistanApp());
}

class CepAsistanApp extends StatelessWidget {
  const CepAsistanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CepAsistan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: navy).copyWith(
          surface: const Color(0xFFF4F6FA),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF5F7FB),
          foregroundColor: navy,
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(21),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE5EAF1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: navy, width: 1.4),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const HomePage(),
    );
  }
}

// --------------------------------------------------
// YAPAY ZEKÂ İSTEMCİSİ
// --------------------------------------------------

class AiResult {
  final Map<String, dynamic>? data;
  final String? error;
  final String? code;

  const AiResult({this.data, this.error, this.code});

  bool get ok => data != null;
  bool get quotaExceeded => code == 'DAILY_QUOTA_EXCEEDED';
}

class AiClient {
  static Future<AiResult> post(
    String url,
    Map<String, dynamic> body,
  ) async {
    try {
      final used = await Store.instance.prepareAiUsageToday();
      if (used >= freeDailyLimit) {
        return const AiResult(
          error: 'Bugünkü ücretsiz hakkın doldu.',
          code: 'DAILY_QUOTA_EXCEEDED',
        );
      }

      if (url.contains('YOUR-SERVER')) {
        return const AiResult(
          error: 'Yapay zekâ sunucusu henüz yapılandırılmadı.',
          code: 'NOT_CONFIGURED',
        );
      }

      final clientId = await Store.instance.aiClientId();

      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'X-CepAsistan-Client': clientId,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 45));

      Map<String, dynamic>? data;
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map) data = Map<String, dynamic>.from(decoded);
      } catch (_) {}

      if (response.statusCode == 200 && data != null) {
        final remaining = data['remainingToday'];
        final updated =
            remaining is num ? freeDailyLimit - remaining.toInt() : used + 1;
        await Store.instance
            .setAiUsesToday(updated.clamp(0, freeDailyLimit).toInt());
        return AiResult(data: data);
      }

      final code = data?['code']?.toString();
      if (code == 'DAILY_QUOTA_EXCEEDED') {
        await Store.instance.setAiUsesToday(freeDailyLimit);
      }

      final message = data?['error'] is String
          ? data!['error'] as String
          : 'Sunucu hatası (${response.statusCode}).';
      return AiResult(error: message, code: code);
    } on TimeoutException {
      return const AiResult(
        error: 'Yanıt zaman aşımına uğradı. Tekrar dene.',
        code: 'TIMEOUT',
      );
    } catch (e) {
      debugPrint('AI bağlantı hatası: $e');
      return const AiResult(
        error: 'Bağlantı kurulamadı. İnternetini kontrol et.',
        code: 'NETWORK',
      );
    }
  }
}

Future<void> showQuotaDialog(BuildContext context, VoidCallback onUpgrade) {
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Günlük hakkın doldu'),
      content: const Text(
        'Ücretsiz sürümde günde $freeDailyLimit yapay zekâ hakkın var. '
        'Yarın yenilenir. Daha fazlası için Pro’ya geçebilirsin.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Tamam'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            onUpgrade();
          },
          child: const Text('Pro’ya geç'),
        ),
      ],
    ),
  );
}

// --------------------------------------------------
// TÜRKÇE TARİH/SAAT AYRIŞTIRICI (cihazda çalışır, API maliyeti yok)
// --------------------------------------------------

String formatDue(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  final time =
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (diff == 0) return 'bugün $time';
  if (diff == 1) return 'yarın $time';
  return '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year} $time';
}

class ParsedTask {
  final String title;
  final DateTime? due;

  const ParsedTask(this.title, this.due);
}

class TrDateParser {
  static const String _l = r'(?<![\p{L}\d])';
  static const String _r = r'(?![\p{L}\d])';
  static const String _suf = r"['’]?(?:te|ta|de|da)";

  static const Map<String, int> _weekdays = {
    'pazartesi': 1,
    'salı': 2,
    'sali': 2,
    'çarşamba': 3,
    'carsamba': 3,
    'perşembe': 4,
    'persembe': 4,
    'cuma': 5,
    'cumartesi': 6,
    'pazar': 7,
  };

  static ParsedTask parse(String input, DateTime now) {
    var s = input.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
    final spans = <List<int>>[];

    void consume(RegExpMatch m) {
      spans.add([m.start, m.end]);
      s = s.substring(0, m.start) +
          ' ' * (m.end - m.start) +
          s.substring(m.end);
    }

    RegExpMatch? find(String pattern) =>
        RegExp(pattern, unicode: true).firstMatch(s);

    int? dayOffset;
    int? hour;
    var minute = 0;
    String? part;
    DateTime? rel;

    // 1) "N dakika / saat / gün sonra"
    var m = find(_l + r'(\d{1,3})\s*(dakika|dk|saat|gün|gun)\s+sonra' + _r);
    if (m != null) {
      final n = int.parse(m.group(1)!);
      final unit = m.group(2)!;
      consume(m);
      if (unit == 'gün' || unit == 'gun') {
        dayOffset = n;
      } else {
        rel = now.add(
          unit == 'saat' ? Duration(hours: n) : Duration(minutes: n),
        );
      }
    }

    // 2) gün
    if (rel == null && dayOffset == null) {
      if ((m = find(_l + r'(öbür gün|obur gun|ertesi gün|ertesi gun)' + _r)) !=
          null) {
        consume(m!);
        dayOffset = 2;
      } else if ((m = find(_l + r'(yarın|yarin)' + _r)) != null) {
        consume(m!);
        dayOffset = 1;
      } else if ((m = find(_l + r'(bugün|bugun)' + _r)) != null) {
        consume(m!);
        dayOffset = 0;
      } else if ((m = find(_l +
              r'(pazartesi|salı|sali|çarşamba|carsamba|perşembe|persembe|cumartesi|cuma|pazar)(?:\s+(?:günü|gunu|gün|gun))?' +
              _r)) !=
          null) {
        consume(m!);
        final target = _weekdays[m.group(1)!]!;
        var diff = (target - now.weekday + 7) % 7;
        if (diff == 0) diff = 7;
        dayOffset = diff;
      }
    }

    // 3) günün bölümü ("öğle yemeği" gibi isimler saat sayılmaz)
    m = find(_l +
        r'(öğleden sonra|ogleden sonra|sabah|öğlen|öğle|oglen|ogle|akşam|aksam|gece)' +
        _r +
        r'(?!\s+yeme[ğg]i)');
    if (m != null) {
      consume(m);
      final w = m.group(1)!;
      if (w.startsWith('öğleden') || w.startsWith('ogleden')) {
        part = 'ogleden';
      } else if (w == 'sabah') {
        part = 'sabah';
      } else if (w == 'gece') {
        part = 'gece';
      } else if (w.startsWith('ö') || w.startsWith('o')) {
        part = 'ogle';
      } else {
        part = 'aksam';
      }
    }

    // 4) saat
    if (rel == null) {
      final patterns = <String>[
        _l + r'(?:saat\s+)?(\d{1,2})[:.](\d{2})' + '(?:$_suf)?' + _r,
        _l + r'saat\s+(\d{1,2})(\s*bu[çc]uk)?' + '(?:$_suf)?' + _r,
        _l + r'(\d{1,2})(\s*bu[çc]uk)?' + _suf + _r,
      ];

      int? h;
      var mi = 0;
      for (var i = 0; i < patterns.length && h == null; i++) {
        final t = find(patterns[i]);
        if (t == null) continue;
        final hh = int.parse(t.group(1)!);
        final mm = i == 0
            ? int.parse(t.group(2)!)
            : (t.group(2) != null ? 30 : 0);
        if (hh > 23 || mm > 59) continue;
        h = hh;
        mi = mm;
        consume(t);
      }

      if (h != null) {
        var hr = h;
        minute = mi;
        if (part == 'aksam' || part == 'ogleden') {
          if (hr < 12) hr += 12;
        } else if (part == 'ogle') {
          if (hr <= 6) hr += 12;
        } else if (part == 'gece') {
          if (hr == 12) {
            hr = 0;
          } else if (hr >= 6 && hr < 12) {
            hr += 12;
          }
        } else if (part == 'sabah') {
          // olduğu gibi
        } else if (hr >= 1 && hr <= 6) {
          hr += 12; // "3'te" -> 15:00
        }
        hour = hr;
      }
    }

    DateTime? due;
    if (rel != null) {
      due = rel;
    } else if (dayOffset != null || hour != null || part != null) {
      var hr = hour;
      if (hr == null) {
        hr = switch (part) {
          'sabah' => 8,
          'ogle' => 12,
          'ogleden' => 14,
          'aksam' => 19,
          'gece' => 22,
          _ => 9,
        };
        minute = 0;
      }
      var base = DateTime(now.year, now.month, now.day, hr, minute);
      if (dayOffset != null) {
        base = DateTime(base.year, base.month, base.day + dayOffset, hr, minute);
      } else if (!base.isAfter(now)) {
        base = DateTime(base.year, base.month, base.day + 1, hr, minute);
      }
      due = base;
    }

    var title = input;
    spans.sort((a, b) => b[0].compareTo(a[0]));
    for (final sp in spans) {
      title = '${title.substring(0, sp[0])} ${title.substring(sp[1])}';
    }
    title = title
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s,.;:\-–]+|[\s,.;:\-–]+$'), '');
    if (title.isEmpty) title = input.trim();

    return ParsedTask(title, due);
  }
}

// --------------------------------------------------
// YEREL VERİ DEPOSU
// --------------------------------------------------

class Store {
  Store._();

  static final Store instance = Store._();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  List<Map<String, dynamic>> list(String key) {
    try {
      final raw = jsonDecode(_prefs?.getString(key) ?? '[]');

      if (raw is! List) return [];

      return raw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> put(
    String key,
    List<Map<String, dynamic>> value,
  ) async {
    await _prefs?.setString(key, jsonEncode(value));
  }

  int get aiUses => _prefs?.getInt('ai_uses') ?? 0;

  String get _istanbulDateKey {
    final now = tz.TZDateTime.now(tz.getLocation('Europe/Istanbul'));
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  Future<int> prepareAiUsageToday() async {
    final today = _istanbulDateKey;
    if (_prefs?.getString('ai_uses_date') != today) {
      await _prefs?.setString('ai_uses_date', today);
      await _prefs?.setInt('ai_uses', 0);
      return 0;
    }
    return aiUses;
  }

  Future<void> setAiUsesToday(int value) async {
    await _prefs?.setString('ai_uses_date', _istanbulDateKey);
    await _prefs?.setInt('ai_uses', value);
  }

  Future<String> aiClientId() async {
    final saved = _prefs?.getString('ai_client_id');
    if (saved != null && RegExp(r'^[a-f0-9]{32}$').hasMatch(saved)) {
      return saved;
    }

    final random = Random.secure();
    final generated = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await _prefs?.setString('ai_client_id', generated);
    return generated;
  }

  bool get isPro => _prefs?.getBool('is_pro_demo') ?? false;

  Future<void> setProDemo(bool value) async {
    await _prefs?.setBool('is_pro_demo', value);
  }
}

// --------------------------------------------------
// BİLDİRİM SİSTEMİ
// --------------------------------------------------

class NotifyService {
  static final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');

    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await plugin.initialize(
      settings: const InitializationSettings(
        android: android,
        iOS: ios,
      ),
    );

    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> schedule(
    Map<String, dynamic> item,
  ) async {
    final date = DateTime.tryParse(
      item['when']?.toString() ?? '',
    );

    if (date == null || !date.isAfter(DateTime.now())) {
      return;
    }

    await plugin.zonedSchedule(
      id: (item['id'] as num).toInt(),
      title: item['title']?.toString() ?? 'CepAsistan hatırlatıcı',
      body: item['body']?.toString() ?? 'Hatırlatma zamanı geldi.',
      scheduledDate: tz.TZDateTime.from(date, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'cepasistan_reminders',
          'Hatırlatıcılar',
          channelDescription: 'Planladığınız işler için bildirimler',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static Future<void> cancel(int id) async {
    await plugin.cancel(id: id);
  }
}

// --------------------------------------------------
// UYGULAMA ANA SAYFASI
// --------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  bool loading = true;
  bool _exitDialogOpen = false;

  List<Map<String, dynamic>> notes = [];
  List<Map<String, dynamic>> tasks = [];
  List<Map<String, dynamic>> reminders = [];
  List<Map<String, dynamic>> transactions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await Store.instance.init();
      await NotifyService.init();

      notes = Store.instance.list('notes');
      tasks = Store.instance.list('tasks');
      reminders = Store.instance.list('reminders');
      transactions = Store.instance.list('transactions');
    } catch (e) {
      debugPrint('Başlatma hatası: $e');
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> _saveAll() async {
    await Store.instance.put('notes', notes);
    await Store.instance.put('tasks', tasks);
    await Store.instance.put('reminders', reminders);
    await Store.instance.put('transactions', transactions);

    if (mounted) setState(() {});
  }

  void _msg(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
      );
  }

  // DÜZELTİLEN GİRİŞ PENCERESİ:
  // TextEditingController oluşturup pencere kapanırken dispose etmek yerine
  // TextFormField'ın başlangıç değerini kullanır.
  Future<String?> _textDialog(
    String title,
    String hint, {
    String initial = '',
  }) async {
    String value = initial;

    final result = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextFormField(
            initialValue: initial,
            autofocus: true,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: hint,
            ),
            onChanged: (text) {
              value = text;
            },
            onFieldSubmitted: (text) {
              Navigator.of(dialogContext).pop(text.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(null);
              },
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(value.trim());
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );

    return result;
  }

  // --------------------------------------------------
  // NOT EKLEME
  // --------------------------------------------------

  Future<void> _addNote() async {
    final title = await _textDialog(
      'Yeni not',
      'Not başlığı',
    );

    if (!mounted || title == null || title.isEmpty) return;

    final body = await _textDialog(
      'Not içeriği',
      'Notunu yaz',
    );

    if (!mounted) return;

    notes.insert(0, {
      'id': DateTime.now().millisecondsSinceEpoch,
      'title': title,
      'body': body ?? '',
      'date': DateTime.now().toIso8601String(),
    });

    await _saveAll();

    if (mounted) _msg('Not kaydedildi.');
  }

  // --------------------------------------------------
  // GÖREV EKLEME
  // --------------------------------------------------

  Future<void> _insertTask(String title, DateTime? due, {int salt = 0}) async {
    final now = DateTime.now();
    final id = now.millisecondsSinceEpoch + salt;
    final task = <String, dynamic>{
      'id': id,
      'title': title,
      'done': false,
    };

    if (due != null && due.isAfter(now)) {
      final reminderId = id.remainder(2147483647);
      final reminder = <String, dynamic>{
        'id': reminderId,
        'title': title,
        'body': 'Görev zamanı geldi',
        'when': due.toIso8601String(),
      };
      task['due'] = due.toIso8601String();
      task['reminderId'] = reminderId;
      reminders.add(reminder);

      try {
        await NotifyService.schedule(reminder);
      } catch (e) {
        debugPrint('Bildirim hatası: $e');
      }
    }

    tasks.insert(0, task);
  }

  Future<void> _addTask() async {
    final raw = await _textDialog(
      'Yeni görev',
      'Örn. yarın 3’te Ahmet’i ara',
    );

    if (!mounted || raw == null || raw.isEmpty) return;

    final parsed = TrDateParser.parse(raw, DateTime.now());
    final due = parsed.due;
    final futureDue = due != null && due.isAfter(DateTime.now());

    await _insertTask(parsed.title, due);
    await _saveAll();

    if (!mounted) return;
    if (futureDue) {
      _msg('Görev eklendi. Hatırlatıcı: ${formatDue(due)}');
    } else if (due != null) {
      _msg('Görev eklendi. Zaman geçmiş olduğu için hatırlatıcı kurulmadı.');
    } else {
      _msg('Görev eklendi.');
    }
  }

  // --------------------------------------------------
  // NOTU YAPAY ZEKÂ İLE ÖZETLE VE GÖREV ÇIKAR
  // --------------------------------------------------

  Future<void> _aiNote(Map<String, dynamic> item) async {
    final text =
        '${item['title'] ?? ''}\n${item['body'] ?? ''}'.trim();

    if (text.length < 10) {
      _msg('Özetlemek için not çok kısa.');
      return;
    }

    final used = await Store.instance.prepareAiUsageToday();
    if (!mounted) return;

    if (used >= freeDailyLimit) {
      await showQuotaDialog(context, () => setState(() => tab = 7));
      return;
    }

    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final result = await AiClient.post(aiNoteEndpoint, {
      'note': text,
      'now': DateTime.now().toIso8601String(),
    });

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (result.quotaExceeded) {
      await showQuotaDialog(context, () => setState(() => tab = 7));
      return;
    }

    if (!result.ok) {
      _msg(result.error ?? 'Not işlenemedi.');
      return;
    }

    final data = result.data!;
    final summary =
        data['summary'] is String ? (data['summary'] as String).trim() : '';
    final suggestions = <Map<String, dynamic>>[];

    if (data['tasks'] is List) {
      for (final t in data['tasks'] as List) {
        if (t is Map &&
            t['title'] is String &&
            (t['title'] as String).trim().isNotEmpty) {
          suggestions.add({
            'title': (t['title'] as String).trim(),
            'due': t['due'] is String ? t['due'] : null,
          });
        }
      }
    }

    final choice = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NoteAiSheet(summary: summary, tasks: suggestions),
    );

    if (!mounted || choice == null) return;

    if (choice['summary'] == true && summary.isNotEmpty) {
      final old = (item['body']?.toString() ?? '').trimRight();
      item['body'] =
          old.isEmpty ? 'AI özeti: $summary' : '$old\n\nAI özeti: $summary';
    }

    var added = 0;
    final picked = (choice['tasks'] as List? ?? const []).whereType<int>();
    for (final index in picked) {
      if (index < 0 || index >= suggestions.length) continue;
      final due = DateTime.tryParse(suggestions[index]['due']?.toString() ?? '');
      await _insertTask(
        suggestions[index]['title'] as String,
        due,
        salt: added,
      );
      added++;
    }

    await _saveAll();
    if (mounted) {
      _msg(added > 0 ? '$added görev eklendi.' : 'Özet nota eklendi.');
    }
  }

  // --------------------------------------------------
  // HATIRLATICI EKLEME
  // --------------------------------------------------

  Future<void> _addReminder() async {
    final title = await _textDialog(
      'Hatırlatıcı',
      'Ne hatırlatılsın?',
    );

    if (!mounted || title == null || title.isEmpty) return;

    final now = DateTime.now();
    final suggested = now.add(const Duration(hours: 1));

    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(
        suggested.year,
        suggested.month,
        suggested.day,
      ),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10),
    );

    if (!mounted || date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(suggested),
    );

    if (!mounted || time == null) return;

    final when = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    if (!when.isAfter(DateTime.now())) {
      _msg('Geçmiş bir zaman seçemezsin.');
      return;
    }

    final item = <String, dynamic>{
      'id': DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
      'title': title,
      'body': 'CepAsistan hatırlatıcın',
      'when': when.toIso8601String(),
    };

    reminders.add(item);

    await _saveAll();

    try {
      await NotifyService.schedule(item);
      if (mounted) _msg('Hatırlatıcı kaydedildi.');
    } catch (e) {
      if (mounted) {
        _msg('Hatırlatıcı kaydedildi ancak bildirim kurulamadı.');
      }
      debugPrint('Bildirim hatası: $e');
    }
  }

  // --------------------------------------------------
  // GELİR / GİDER EKLEME
  // --------------------------------------------------

  Future<void> _addTransaction() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.add_circle,
                  color: Colors.green,
                ),
                title: const Text('Gelir ekle'),
                onTap: () {
                  Navigator.of(sheetContext).pop('Gelir');
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.remove_circle,
                  color: Colors.red,
                ),
                title: const Text('Gider ekle'),
                onTap: () {
                  Navigator.of(sheetContext).pop('Gider');
                },
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || kind == null) return;

    final title = await _textDialog(
      '$kind açıklaması',
      'Örn. Maaş / Market',
    );

    if (!mounted || title == null || title.isEmpty) return;

    final raw = await _textDialog(
      'Tutar (TL)',
      'Örn. 250,50',
    );

    if (!mounted || raw == null) return;

    final amount = double.tryParse(
      raw.trim().replaceAll(' ', '').replaceAll(',', '.'),
    );

    if (amount == null || amount <= 0) {
      _msg('Geçerli bir tutar gir.');
      return;
    }

    transactions.insert(0, {
      'id': DateTime.now().millisecondsSinceEpoch,
      'title': title,
      'kind': kind,
      'amount': amount,
      'date': DateTime.now().toIso8601String(),
    });

    await _saveAll();

    if (mounted) _msg('$kind kaydedildi.');
  }

  // --------------------------------------------------
  // KAYIT SİLME
  // --------------------------------------------------

  Future<void> _delete(
    List<Map<String, dynamic>> list,
    int index, {
    bool reminder = false,
  }) async {
    if (index < 0 || index >= list.length) return;

    final item = list.removeAt(index);

    if (reminder) {
      try {
        await NotifyService.cancel(
          (item['id'] as num).toInt(),
        );
      } catch (e) {
        debugPrint('Bildirim silme hatası: $e');
      }
    } else if (identical(list, tasks) && item['reminderId'] is num) {
      // Görev silinirse ona bağlı hatırlatıcı ve bildirim de silinir
      final reminderId = (item['reminderId'] as num).toInt();
      reminders.removeWhere(
        (r) => r['id'] is num && (r['id'] as num).toInt() == reminderId,
      );
      try {
        await NotifyService.cancel(reminderId);
      } catch (e) {
        debugPrint('Bildirim silme hatası: $e');
      }
    }

    await _saveAll();

    if (mounted) _msg('Kayıt silindi.');
  }

  // --------------------------------------------------
  // ANA SAYFA KARTI
  // --------------------------------------------------

  Widget _toolCard(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap, {
    Color color = navy,
  }) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(21),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: .12),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 7),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: navy,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF8290A3), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _taskSubtitle(Map<String, dynamic> item) {
    final due = DateTime.tryParse(item['due']?.toString() ?? '');
    return due == null ? '' : 'Hatırlatıcı: ${formatDue(due)}';
  }

  Widget _sectionTitle(String title, {String? action, VoidCallback? onAction}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: navy,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Text(action),
          ),
      ],
    );
  }

  Widget _dashboard() {
    final pendingTasks = tasks.where((item) => item['done'] != true).length;
    final now = DateTime.now();
    const weekdays = [
      'PAZAR',
      'PAZARTESİ',
      'SALI',
      'ÇARŞAMBA',
      'PERŞEMBE',
      'CUMA',
      'CUMARTESİ',
    ];
    const months = [
      'OCAK',
      'ŞUBAT',
      'MART',
      'NİSAN',
      'MAYIS',
      'HAZİRAN',
      'TEMMUZ',
      'AĞUSTOS',
      'EYLÜL',
      'EKİM',
      'KASIM',
      'ARALIK',
    ];
    final greeting = now.hour < 12
        ? 'Günaydın'
        : now.hour < 18
            ? 'İyi günler'
            : 'İyi akşamlar';
    final income = transactions
        .where((item) => item['kind'] == 'Gelir')
        .fold<double>(
          0,
          (sum, item) =>
              sum + (item['amount'] is num ? (item['amount'] as num).toDouble() : 0),
        );
    final expense = transactions
        .where((item) => item['kind'] == 'Gider')
        .fold<double>(
          0,
          (sum, item) =>
              sum + (item['amount'] is num ? (item['amount'] as num).toDouble() : 0),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      children: [
        Text(
          '${weekdays[now.weekday % 7]}, ${now.day} ${months[now.month - 1]}',
          style: const TextStyle(
            color: Color(0xFF718096),
            fontWeight: FontWeight.w700,
            letterSpacing: .7,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          '$greeting 👋',
          style: const TextStyle(
            color: navy,
            fontWeight: FontWeight.w800,
            fontSize: 25,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          'Bugün işlerini kolayca hallet.',
          style: TextStyle(color: Color(0xFF718096), fontSize: 14),
        ),
        const SizedBox(height: 20),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(25),
            onTap: () => setState(() => tab = 6),
            child: Ink(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [navy, Color(0xFF315F98)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: 3,
                    top: 0,
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white.withValues(alpha: .12),
                      child: const Icon(
                        Icons.auto_awesome,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CEP ASİSTAN AI',
                        style: TextStyle(
                          color: Color(0xFFC9D8EB),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Aklındaki soruyu sor',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Sorularına hızlıca yanıt al.',
                        style: TextStyle(color: Color(0xFFE1EAF5), fontSize: 12),
                      ),
                      const SizedBox(height: 15),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Sohbete başla',
                              style: TextStyle(
                                color: navy,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(Icons.arrow_forward, color: navy, size: 16),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        _sectionTitle(
          'Hızlı araçlar',
          action: 'Tüm araçlar',
          onAction: () => setState(() => tab = 9),
        ),
        const SizedBox(height: 4),
        GridView(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 124,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _toolCard(
              Icons.calculate_outlined,
              'Hesap makinesi',
              'Hızlı hesapla',
              () => setState(() => tab = 8),
              color: navy,
            ),
            _toolCard(
              Icons.straighten_outlined,
              'Ölçü birimleri',
              'Birim dönüştür',
              () => setState(() => tab = 5),
              color: const Color(0xFF318376),
            ),
            _toolCard(
              Icons.note_alt_outlined,
              'Notlarım',
              '${notes.length} kayıt',
              () => setState(() => tab = 1),
              color: const Color(0xFF8057A5),
            ),
            _toolCard(
              Icons.task_alt_outlined,
              'Görevlerim',
              '$pendingTasks bekleyen',
              () => setState(() => tab = 2),
              color: const Color(0xFF58814D),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _sectionTitle('Bugünün özeti'),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
            child: Row(
              children: [
                _summaryMetric(
                  Icons.check_circle_outline,
                  '$pendingTasks',
                  'bekleyen görev',
                  const Color(0xFF58814D),
                  () => setState(() => tab = 2),
                ),
                _summaryMetric(
                  Icons.notifications_none,
                  '${reminders.length}',
                  'hatırlatıcı',
                  const Color(0xFF8057A5),
                  () => setState(() => tab = 3),
                ),
                _summaryMetric(
                  Icons.account_balance_wallet_outlined,
                  '${(income - expense).toStringAsFixed(0)} ₺',
                  'bakiye',
                  const Color(0xFFC87832),
                  () => setState(() => tab = 4),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 15),
        OutlinedButton.icon(
          onPressed: _addReminder,
          icon: const Icon(Icons.add_alarm_outlined),
          label: const Text('Hatırlatıcı ekle'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: navy,
            side: const BorderSide(color: Color(0xFFD9E2EE)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _summaryMetric(
    IconData icon,
    String value,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: Column(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: color.withValues(alpha: .12),
                child: Icon(icon, color: color, size: 17),
              ),
              const SizedBox(height: 7),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: navy,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF8290A3),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------
  // NOT / GÖREV / HATIRLATICI LİSTELERİ
  // --------------------------------------------------

Widget _listPage(
  List<Map<String, dynamic>> data, {
  bool isTasks = false,
  bool isReminders = false,
}) {
  if (data.isEmpty) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isTasks
                  ? Icons.task_alt_outlined
                  : isReminders
                      ? Icons.notifications_none
                      : Icons.note_alt_outlined,
              size: 48,
              color: const Color(0xFF9AA8B9),
            ),
            const SizedBox(height: 12),
            Text(
              isTasks
                  ? 'Henüz görev eklemedin.'
                  : isReminders
                      ? 'Henüz hatırlatıcı yok.'
                      : 'Henüz not eklemedin.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: navy,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Yeni kayıt eklemek için sağ üstteki + düğmesine dokun.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8290A3)),
            ),
          ],
        ),
      ),
    );
  }

  return ListView.separated(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
    itemCount: data.length,
    separatorBuilder: (context, index) => const SizedBox(height: 10),
    itemBuilder: (itemContext, index) {
      final item = data[index];
      final done = isTasks && item['done'] == true;
      final iconColor = isTasks
          ? const Color(0xFF58814D)
          : isReminders
              ? const Color(0xFF8057A5)
              : navy;

      return Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 6,
          ),
          leading: isTasks
              ? Checkbox.adaptive(
                  value: done,
                  onChanged: (value) async {
                    item['done'] = value == true;
                    await _saveAll();
                  },
                )
              : CircleAvatar(
                  backgroundColor: iconColor.withValues(alpha: .12),
                  child: Icon(
                    isReminders
                        ? Icons.notifications_active_outlined
                        : Icons.description_outlined,
                    color: iconColor,
                  ),
                ),
          title: Text(
            item['title']?.toString() ?? '',
            style: TextStyle(
              color: navy,
              fontWeight: FontWeight.w700,
              decoration: done ? TextDecoration.lineThrough : null,
            ),
          ),
          subtitle: Text(
            isReminders
                ? (DateTime.tryParse(item['when']?.toString() ?? '')
                          ?.toLocal()
                          .toString() ??
                      '')
                : isTasks
                    ? _taskSubtitle(item)
                    : (item['body']?.toString() ?? ''),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: (!isTasks && !isReminders)
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'AI ile özetle ve görev çıkar',
                      icon: const Icon(Icons.auto_awesome, color: navy),
                      onPressed: () => _aiNote(item),
                    ),
                    IconButton(
                      tooltip: 'Sil',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(data, index),
                    ),
                  ],
                )
              : IconButton(
                  tooltip: 'Sil',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(
                    data,
                    index,
                    reminder: isReminders,
                  ),
                ),
        ),
      );
    },
  );
}

  // --------------------------------------------------
  // GELİR GİDER SAYFASI
  // --------------------------------------------------

  Widget _budgetPage() {
    final income = transactions
        .where((item) => item['kind'] == 'Gelir')
        .fold<double>(
          0,
          (sum, item) => sum + (item['amount'] as num).toDouble(),
        );

    final expense = transactions
        .where((item) => item['kind'] == 'Gider')
        .fold<double>(
          0,
          (sum, item) => sum + (item['amount'] as num).toDouble(),
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Toplam bakiye'),
                const SizedBox(height: 6),
                Text(
                  '${(income - expense).toStringAsFixed(2)} TL',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: navy,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Gelir: ${income.toStringAsFixed(2)} TL'),
                Text('Gider: ${expense.toStringAsFixed(2)} TL'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _addTransaction,
          icon: const Icon(Icons.add),
          label: const Text('Gelir veya gider ekle'),
        ),
        const SizedBox(height: 8),
        if (transactions.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Henüz gelir veya gider yok.')),
          ),
        ...transactions.map((item) {
          final isIncome = item['kind'] == 'Gelir';
          final amount = (item['amount'] as num).toDouble();

          return Card(
            elevation: 0,
            child: ListTile(
              leading: Icon(
                isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                color: isIncome ? Colors.green : Colors.red,
              ),
              title: Text(item['title']?.toString() ?? ''),
              subtitle: Text(item['kind']?.toString() ?? ''),
              trailing: Text(
                '${isIncome ? '+' : '-'}${amount.toStringAsFixed(2)} TL',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isIncome ? Colors.green : Colors.red,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  // --------------------------------------------------
  // FOTOĞRAFTAN PDF OLUŞTURMA
  // --------------------------------------------------

  Future<void> _makePdf() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );

      if (image == null || !mounted) return;

      final bytes = await image.readAsBytes();

      final document = pw.Document();

      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Center(
            child: pw.Image(
              pw.MemoryImage(bytes),
              fit: pw.BoxFit.contain,
            ),
          ),
        ),
      );

      final output = await document.save();
      final directory = await getTemporaryDirectory();

      final file = File(
        '${directory.path}/cep_asistan_'
        '${DateTime.now().millisecondsSinceEpoch}.pdf',
      );

      await file.writeAsBytes(output);

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              mimeType: 'application/pdf',
            ),
          ],
          text: 'CepAsistan PDF',
        ),
      );
    } catch (e) {
      if (mounted) _msg('PDF oluşturulamadı.');
      debugPrint('PDF hatası: $e');
    }
  }

  Widget _toolsPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const Text(
          'İhtiyacın olan araçlar tek yerde.',
          style: TextStyle(color: Color(0xFF718096), fontSize: 14),
        ),
        const SizedBox(height: 16),
        GridView(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 124,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _toolCard(Icons.calculate_outlined, 'Hesap makinesi',
                'Dört işlem ve yüzde', () => setState(() => tab = 8)),
            _toolCard(Icons.straighten_outlined, 'Ölçü birimleri',
                'Birim dönüştürücü', () => setState(() => tab = 5),
                color: const Color(0xFF318376)),
            _toolCard(Icons.notifications_active_outlined, 'Hatırlatıcılar',
                '${reminders.length} kayıt', () => setState(() => tab = 3),
                color: const Color(0xFF8057A5)),
            _toolCard(Icons.account_balance_wallet_outlined, 'Gelir-gider',
                'Bütçeni takip et', () => setState(() => tab = 4),
                color: const Color(0xFFC87832)),
            _toolCard(Icons.picture_as_pdf_outlined, 'Fotoğraftan PDF',
                'Oluştur ve paylaş', _makePdf,
                color: const Color(0xFFC75C58)),
            _toolCard(Icons.auto_awesome, 'Yapay zekâ', 'CepAsistan’a sor',
                () => setState(() => tab = 6),
                color: const Color(0xFF426CA0)),
            _toolCard(Icons.workspace_premium_outlined, 'CepAsistan Pro',
                'Üyelik seçenekleri', () => setState(() => tab = 7),
                color: const Color(0xFFB18435)),
          ],
        ),
      ],
    );
  }

  // --------------------------------------------------
  // ANA EKRAN VE ALT MENÜ
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    const pageTitles = [
      'CepAsistan',
      'Notlarım',
      'Görevlerim',
      'Hatırlatıcılar',
      'Gelir-gider',
      'Ölçü birimleri',
      'Yapay zekâ',
      'Pro üyelik',
      'Hesap makinesi',
      'Araçlar',
    ];

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (tab != 0) {
          setState(() => tab = 0);
        } else {
          _confirmExit();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: tab == 0
              ? Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE1EAF5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.grid_view_rounded, color: navy),
                    ),
                    const SizedBox(width: 11),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'CEP ASİSTAN',
                          style: TextStyle(
                            color: Color(0xFF718096),
                            fontSize: 10,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Günlük yardımcın',
                          style: TextStyle(
                            color: navy,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Text(
                  pageTitles[tab],
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
          actions: tab == 1 || tab == 2 || tab == 3
              ? [
                  IconButton.filledTonal(
                    tooltip: 'Ekle',
                    onPressed: () {
                      if (tab == 1) _addNote();
                      if (tab == 2) _addTask();
                      if (tab == 3) _addReminder();
                    },
                    icon: const Icon(Icons.add),
                  ),
                  const SizedBox(width: 8),
                ]
              : null,
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : IndexedStack(
                index: tab,
                children: [
                  _dashboard(),
                  _listPage(notes),
                  _listPage(tasks, isTasks: true),
                  _listPage(reminders, isReminders: true),
                  _budgetPage(),
                  const UnitConverterPage(),
                  AiPage(
                    onMessage: _msg,
                    onUpgrade: () => setState(() => tab = 7),
                  ),
                  ProPage(onMessage: _msg),
                  const CalculatorPage(),
                  _toolsPage(),
                ],
              ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab == 0
              ? 0
              : tab == 1
                  ? 1
                  : tab == 2
                      ? 2
                      : 3,
          onDestinationSelected: (index) {
            setState(() {
              tab = switch (index) {
                0 => 0,
                1 => 1,
                2 => 2,
                _ => 9,
              };
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Ana sayfa',
            ),
            NavigationDestination(
              icon: Icon(Icons.note_alt_outlined),
              selectedIcon: Icon(Icons.note_alt),
              label: 'Notlar',
            ),
            NavigationDestination(
              icon: Icon(Icons.task_alt_outlined),
              selectedIcon: Icon(Icons.task_alt),
              label: 'Görevler',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded),
              label: 'Araçlar',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmExit() async {
    if (_exitDialogOpen || !mounted) return;
    _exitDialogOpen = true;
    try {
      final shouldExit = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Uygulamadan çıkılsın mı?'),
          content: const Text('CepAsistan’dan çıkmak istediğine emin misin?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Çıkış'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (shouldExit == true) {
        await SystemNavigator.pop();
      }
    } finally {
      _exitDialogOpen = false;
    }
  }
}

// --------------------------------------------------
// HESAP MAKİNESİ VE BİRİM DÖNÜŞTÜRÜCÜ
// --------------------------------------------------

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  String display = '0';
  String expression = '';
  double? storedValue;
  String? operation;
  bool startNewNumber = false;

  void press(String key) {
    setState(() {
      if (key == 'AC') {
        display = '0';
        expression = '';
        storedValue = null;
        operation = null;
        startNewNumber = false;
      } else if (key == 'DEL') {
        if (display.length > 1) {
          display = display.substring(0, display.length - 1);
        } else {
          display = '0';
        }
        _syncExpression();
      } else if (key == '+/-') {
        if (display != '0') {
          display = display.startsWith('-')
              ? display.substring(1)
              : '-$display';
        }
        _syncExpression();
      } else if (key == '%') {
        final value = _number(display);
        if (value != null) display = _format(value / 100);
        _syncExpression();
      } else if (['+', '−', '×', '÷'].contains(key)) {
        storedValue = _number(display);
        operation = key;
        expression = '$display $key';
        startNewNumber = true;
      } else if (key == '=') {
        final left = storedValue;
        final right = _number(display);
        if (left != null && right != null && operation != null) {
          final answer = switch (operation) {
            '+' => left + right,
            '−' => left - right,
            '×' => left * right,
            '÷' => right == 0 ? null : left / right,
            _ => null,
          };
          expression =
              '${_format(left).replaceAll('.', ',')} $operation '
              '${_format(right).replaceAll('.', ',')} =';
          display = answer == null ? 'Hata' : _format(answer);
          storedValue = null;
          operation = null;
          startNewNumber = true;
        }
      } else if (key == '.') {
        if (startNewNumber || display == 'Hata') {
          if (operation == null) expression = '';
          display = '0.';
          startNewNumber = false;
        } else if (!display.contains('.')) {
          display += '.';
        }
        _syncExpression();
      } else {
        if (startNewNumber || display == '0' || display == 'Hata') {
          if (operation == null) expression = '';
          display = key;
          startNewNumber = false;
        } else if (display.replaceAll('-', '').replaceAll('.', '').length < 14) {
          display += key;
        }
        _syncExpression();
      }
    });
  }

  void _syncExpression() {
    if (operation == null || storedValue == null || startNewNumber) return;
    expression =
        '${_format(storedValue!).replaceAll('.', ',')} $operation '
        '${display.replaceAll('.', ',')}';
  }

  double? _number(String value) => double.tryParse(value);

  String _format(double value) {
    if (!value.isFinite) return 'Hata';
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toStringAsFixed(0);
    }
    final text = value.toStringAsPrecision(10);
    return text.contains('.') && !text.contains('e')
        ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : text;
  }

  @override
  Widget build(BuildContext context) {
    const keys = [
      'AC', '+/-', '%', '÷',
      '7', '8', '9', '×',
      '4', '5', '6', '−',
      '1', '2', '3', '+',
      'DEL', '0', ',', '=',
    ];
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              children: [
                SizedBox(
                  height: constraints.maxHeight * .22,
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (expression.isNotEmpty)
                          SizedBox(
                            width: double.infinity,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                expression,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 22,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            display.replaceAll('.', ','),
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 56,
                              fontWeight: FontWeight.w500,
                              color: navy,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: keys.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 1.15,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemBuilder: (context, index) {
                      final label = keys[index];
                      final key = label == ',' ? '.' : label;
                      final isOperator = ['÷', '×', '−', '+', '='].contains(key);
                      final isUtility = ['AC', 'DEL', '+/-', '%'].contains(key);
                      return FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: isOperator
                              ? navy
                              : isUtility
                                  ? const Color(0xFFDCE5EF)
                                  : Colors.white,
                          foregroundColor: navy,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        onPressed: () => press(key),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: label == 'DEL'
                              ? const Icon(Icons.backspace_outlined, size: 26)
                              : Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: label.length > 2 ? 18 : 26,
                                    fontWeight: FontWeight.w600,
                                    color: isOperator ? Colors.white : navy,
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class UnitConverterPage extends StatefulWidget {
  const UnitConverterPage({super.key});

  @override
  State<UnitConverterPage> createState() => _UnitConverterPageState();
}

class _UnitConverterPageState extends State<UnitConverterPage> {
  final TextEditingController amount = TextEditingController(text: '1');
  String category = 'Uzunluk';
  String from = 'Metre';
  String to = 'Kilometre';
  String result = '';

  static const Map<String, Map<String, double>> units = {
    'Uzunluk': {'Milimetre': .001, 'Santimetre': .01, 'Desimetre': .1, 'Metre': 1, 'Kilometre': 1000, 'İnç': .0254, 'Fit': .3048, 'Yarda': .9144, 'Mil': 1609.344, 'Deniz mili': 1852},
    'Ağırlık / Kütle': {'Miligram': .000001, 'Gram': .001, 'Kilogram': 1, 'Ton': 1000, 'Ons': .028349523125, 'Pound': .45359237, 'Stone': 6.35029318},
    'Hacim': {'Mililitre': .001, 'Litre': 1, 'Metreküp': 1000, 'Çay kaşığı': .00492892, 'Yemek kaşığı': .0147868, 'Su bardağı': .2, 'ABD galonu': 3.785411784, 'İngiliz galonu': 4.54609, 'ABD sıvı onsu': .0295735},
    'Alan': {'Milimetrekare': .000001, 'Santimetrekare': .0001, 'Metrekare': 1, 'Hektar': 10000, 'Kilometrekare': 1000000, 'Fit kare': .09290304, 'Akre': 4046.8564224},
    'Zaman': {'Milisaniye': .001, 'Saniye': 1, 'Dakika': 60, 'Saat': 3600, 'Gün': 86400, 'Hafta': 604800, 'Yıl (365 gün)': 31536000},
    'Hız': {'Metre/saniye': 1, 'Kilometre/saat': .2777777778, 'Mil/saat': .44704, 'Fit/saniye': .3048, 'Deniz mili/saat': .514444},
    'Sıcaklık': {'Santigrat': 1, 'Fahrenhayt': 2, 'Kelvin': 3},
    'Veri': {'Bit': .125, 'Bayt': 1, 'Kilobayt (1000 B)': 1000, 'Megabayt (1000 B)': 1000000, 'Gigabayt (1000 B)': 1000000000, 'Kibibayt (1024 B)': 1024, 'Mebibayt (1024 B)': 1048576, 'Gibibayt (1024 B)': 1073741824},
    'Basınç': {'Pascal': 1, 'Kilopascal': 1000, 'Bar': 100000, 'Atmosfer': 101325, 'PSI': 6894.757, 'mmHg': 133.322},
    'Enerji': {'Joule': 1, 'Kilojoule': 1000, 'Kalori': 4.184, 'Kilokalori': 4184, 'Watt-saat': 3600, 'Kilowatt-saat': 3600000, 'Elektronvolt': 1.602176634e-19},
    'Güç': {'Watt': 1, 'Kilowatt': 1000, 'Beygir gücü': 745.699872, 'Kilokalori/saat': 1.163},
    'Kuvvet': {'Newton': 1, 'Kilonewton': 1000, 'Kilogram-kuvvet': 9.80665, 'Pound-kuvvet': 4.448222},
    'Açı': {'Derece': 1, 'Radyan': 57.2957795, 'Grad': .9, 'Tur': 360},
    'Yakıt tüketimi': {'Litre/100 km': 1, 'Kilometre/litre': 2, 'Mil/galon (ABD)': 3},
  };

  @override
  void initState() {
    super.initState();
    _convert();
  }

  void _convert() {
    final value = double.tryParse(amount.text.trim().replaceAll(',', '.'));
    if (value == null) {
      setState(() => result = 'Geçerli bir sayı gir.');
      return;
    }
    final factor = units[category]!;
    double converted;
    if (category == 'Sıcaklık') {
      final celsius = switch (from) {
        'Fahrenhayt' => (value - 32) * 5 / 9,
        'Kelvin' => value - 273.15,
        _ => value,
      };
      converted = switch (to) {
        'Fahrenhayt' => celsius * 9 / 5 + 32,
        'Kelvin' => celsius + 273.15,
        _ => celsius,
      };
    } else if (category == 'Yakıt tüketimi') {
      final lPer100 = switch (from) {
        'Kilometre/litre' => value == 0 ? double.infinity : 100 / value,
        'Mil/galon (ABD)' => value == 0 ? double.infinity : 235.214583 / value,
        _ => value,
      };
      converted = switch (to) {
        'Kilometre/litre' => lPer100 == 0 ? double.infinity : 100 / lPer100,
        'Mil/galon (ABD)' => lPer100 == 0 ? double.infinity : 235.214583 / lPer100,
        _ => lPer100,
      };
    } else {
      converted = value * factor[from]! / factor[to]!;
    }
    setState(() => result = '$value $from = ${_format(converted)} $to');
  }

  String _format(double value) {
    if (!value.isFinite) return 'Tanımsız';
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toStringAsFixed(0);
    }
    final text = value.toStringAsPrecision(10);
    return text.contains('.') && !text.contains('e')
        ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : text;
  }

  void _changeCategory(String value) {
    setState(() {
      category = value;
      final names = units[category]!.keys.toList();
      from = names.first;
      to = names.length > 1 ? names[1] : names.first;
      result = '';
    });
    _convert();
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final names = units[category]!.keys.toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Dönüştürülecek ölçü türünü ve birimleri seç.', style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: category,
          decoration: const InputDecoration(labelText: 'Ölçü türü'),
          items: units.keys.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
          onChanged: (value) { if (value != null) _changeCategory(value); },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: const InputDecoration(labelText: 'Miktar'),
          onChanged: (_) => _convert(),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('$category-from'),
          initialValue: from,
          decoration: const InputDecoration(labelText: 'Nereden'),
          items: names.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
          onChanged: (value) { if (value != null) { setState(() => from = value); _convert(); } },
        ),
        const SizedBox(height: 12),
        Center(child: IconButton.filledTonal(onPressed: () { setState(() { final old = from; from = to; to = old; }); _convert(); }, icon: const Icon(Icons.swap_vert), tooltip: 'Birimleri değiştir')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('$category-to'),
          initialValue: to,
          decoration: const InputDecoration(labelText: 'Nereye'),
          items: names.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
          onChanged: (value) { if (value != null) { setState(() => to = value); _convert(); } },
        ),
        const SizedBox(height: 20),
        Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(18), child: Text(result, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)))),
        const SizedBox(height: 8),
        const Text('Uzunluk, kütle, hacim, alan, zaman, hız, sıcaklık, veri, basınç, enerji, güç, kuvvet, açı ve yakıt tüketimi.', style: TextStyle(fontSize: 12, color: Colors.black54), textAlign: TextAlign.center),
      ],
    );
  }
}

// --------------------------------------------------
// YAPAY ZEKÂ ASİSTANI
// --------------------------------------------------

class AiPage extends StatefulWidget {
  final void Function(String) onMessage;
  final VoidCallback onUpgrade;

  const AiPage({
    super.key,
    required this.onMessage,
    required this.onUpgrade,
  });

  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  final TextEditingController input = TextEditingController();
  final List<Map<String, String>> history = [];

  bool busy = false;

  int remaining = freeDailyLimit;

  @override
  void initState() {
    super.initState();
    _refreshRemaining();
  }

  Future<void> _refreshRemaining() async {
    final used = await Store.instance.prepareAiUsageToday();
    if (!mounted) return;
    setState(() {
      remaining = (freeDailyLimit - used).clamp(0, freeDailyLimit).toInt();
    });
  }

  Future<void> send() async {
    final message = input.text.trim();

    if (message.isEmpty || busy) return;

    setState(() => busy = true);
    try {
      final used = await Store.instance.prepareAiUsageToday();
      if (!mounted) return;

      if (used >= freeDailyLimit) {
        await showQuotaDialog(context, widget.onUpgrade);
        return;
      }

      setState(() {
        history.add({'role': 'user', 'content': message});
        input.clear();
      });

      final result = await AiClient.post(aiEndpoint, {
        'messages': history
            .map((item) => {
                  'role': item['role'],
                  'content': item['content'],
                })
            .toList(),
      });

      if (!mounted) return;

      final reply = result.data?['reply'];

      if (result.ok && reply is String && reply.trim().isNotEmpty) {
        history.add({'role': 'assistant', 'content': reply});
      } else if (result.quotaExceeded) {
        // Cevaplanmayan mesajı geri al
        history.removeLast();
        input.text = message;
        await showQuotaDialog(context, widget.onUpgrade);
      } else {
        history.add({
          'role': 'assistant',
          'content': result.error ?? 'Sunucudan okunabilir bir yanıt alınamadı.',
        });
      }

      await _refreshRemaining();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: history.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: const Color(0xFFE1EAF5),
                          child: const Icon(
                            Icons.auto_awesome,
                            size: 30,
                            color: navy,
                          ),
                        ),
                        const SizedBox(height: 17),
                        const Text(
                          'Nasıl yardımcı olayım?',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: navy,
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                          ),
                        ),
                        const SizedBox(height: 7),
                        const Text(
                          'Sorunu yaz. CepAsistan senin için yanıtlasın.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF718096)),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final item = history[index];
                    final isUser = item['role'] == 'user';
                    final bubbleColor = isUser ? navy : Colors.white;
                    final foreground = isUser ? Colors.white : navy;

                    return Align(
                      alignment: isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * .82,
                        ),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: bubbleColor,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(19),
                            topRight: const Radius.circular(19),
                            bottomLeft: Radius.circular(isUser ? 19 : 5),
                            bottomRight: Radius.circular(isUser ? 5 : 19),
                          ),
                          boxShadow: isUser
                              ? null
                              : const [
                                  BoxShadow(
                                    color: Color(0x0B183153),
                                    blurRadius: 12,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isUser ? 'Sen' : 'CepAsistan',
                              style: TextStyle(
                                color: isUser
                                    ? const Color(0xFFD9E6F5)
                                    : const Color(0xFF718096),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            SelectableText(
                              item['content'] ?? '',
                              style: TextStyle(color: foreground, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF4F6FA),
              border: Border(top: BorderSide(color: Color(0xFFE5EAF1))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => send(),
                    decoration: InputDecoration(
                      hintText: 'Bir şey sor · $remaining hak kaldı',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 17,
                        vertical: 13,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(
                          color: Color(0xFFE5EAF1),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(
                          color: Color(0xFFE5EAF1),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                IconButton.filled(
                  onPressed: busy ? null : send,
                  style: IconButton.styleFrom(
                    backgroundColor: navy,
                    foregroundColor: Colors.white,
                    fixedSize: const Size(49, 49),
                  ),
                  icon: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------
// PRO ÜYELİK
// --------------------------------------------------

class ProPage extends StatefulWidget {
  final void Function(String) onMessage;

  const ProPage({
    super.key,
    required this.onMessage,
  });

  @override
  State<ProPage> createState() => _ProPageState();
}

class _ProPageState extends State<ProPage> {
  final InAppPurchase iap = InAppPurchase.instance;

  bool available = false;
  bool busy = true;

  List<ProductDetails> products = [];
  Stream<List<PurchaseDetails>>? purchaseStream;
  StreamSubscription<List<PurchaseDetails>>? purchaseSubscription;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      available = await iap.isAvailable();
      if (!mounted) return;

      if (available) {
        final response = await iap.queryProductDetails({
          monthlyProductId,
          yearlyProductId,
        });

        if (!mounted) return;
        products = response.productDetails;

        if (response.error != null) {
          widget.onMessage('Mağaza ürünleri alınırken hata oluştu.');
        }

        purchaseStream = iap.purchaseStream;

        purchaseSubscription = iap.purchaseStream.listen(
          _onPurchaseUpdate,
          onError: (error) {
            debugPrint('Satın alma akışı hatası: $error');
          },
        );
      }
    } catch (e) {
      debugPrint('Pro yükleme hatası: $e');
    }

    if (mounted) setState(() => busy = false);
  }

  Future<void> _onPurchaseUpdate(
    List<PurchaseDetails> purchases,
  ) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.error) {
        widget.onMessage('Satın alma tamamlanamadı.');
      } else if (purchase.status == PurchaseStatus.pending) {
        widget.onMessage('Satın alma işlemi bekleniyor.');
      } else if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        widget.onMessage(
          'Mağazadan satın alma bildirimi geldi. '
          'Pro erişimi açılmadan önce satın alma sunucuda doğrulanmalıdır.',
        );
      }

      if (purchase.pendingCompletePurchase) {
        await iap.completePurchase(purchase);
      }
    }
  }

  Future<void> _buy(ProductDetails product) async {
    if (busy) return;

    setState(() => busy = true);

    try {
      await iap.buyNonConsumable(
        purchaseParam: PurchaseParam(
          productDetails: product,
        ),
      );
    } catch (e) {
      widget.onMessage('Satın alma başlatılamadı.');
      debugPrint('Satın alma hatası: $e');
    }

    if (mounted) setState(() => busy = false);
  }

  Future<void> _restore() async {
    try {
      await iap.restorePurchases();
      widget.onMessage('Satın alımları geri yükleme isteği gönderildi.');
    } catch (e) {
      widget.onMessage('Satın alımlar geri yüklenemedi.');
    }
  }

  @override
  void dispose() {
    if (available) {
      purchaseSubscription?.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Icon(
          Icons.workspace_premium,
          color: Colors.amber,
          size: 60,
        ),
        const SizedBox(height: 8),
        const Text(
          'CepAsistan Pro',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Daha yüksek yapay zekâ kullanım kotası ve gelişmiş araçlar.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),
        const Card(
          elevation: 0,
          child: ListTile(
            leading: Icon(Icons.check_circle, color: Colors.green),
            title: Text('Ücretsiz temel araçlar'),
          ),
        ),
        const Card(
          elevation: 0,
          child: ListTile(
            leading: Icon(Icons.check_circle, color: Colors.green),
            title: Text('Pro ile daha yüksek AI kullanım kotası'),
          ),
        ),
        const SizedBox(height: 12),
        if (busy)
          const Center(
            child: CircularProgressIndicator(),
          )
        else if (!available)
          const Text(
            'Mağaza satın alımları şu anda kullanılamıyor.',
            textAlign: TextAlign.center,
          )
        else if (products.isEmpty)
          const Text(
            'Mağaza ürünleri bulunamadı. Play Console veya '
            'App Store Connect ürün kimliklerini kontrol et.',
            textAlign: TextAlign.center,
          )
        else
          ...products.map(
            (product) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilledButton(
                onPressed: busy ? null : () => _buy(product),
                child: Text(
                  '${product.title} · ${product.price}',
                ),
              ),
            ),
          ),
        OutlinedButton(
          onPressed: _restore,
          child: const Text('Satın alımları geri yükle'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Not: Bu ekran tek başına güvenli Pro doğrulaması sağlamaz. '
          'Gerçek Pro erişimi için mağaza satın alma kaydını sunucuda '
          'doğrulamak gerekir.',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------
// NOT İÇİN YAPAY ZEKÂ ÖNERİ PENCERESİ
// --------------------------------------------------

class _NoteAiSheet extends StatefulWidget {
  final String summary;
  final List<Map<String, dynamic>> tasks;

  const _NoteAiSheet({
    required this.summary,
    required this.tasks,
  });

  @override
  State<_NoteAiSheet> createState() => _NoteAiSheetState();
}

class _NoteAiSheetState extends State<_NoteAiSheet> {
  late final List<bool> selected =
      List<bool>.filled(widget.tasks.length, true);
  bool saveSummary = true;

  @override
  Widget build(BuildContext context) {
    final hasSummary = widget.summary.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'AI özeti',
                style: TextStyle(
                  color: navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasSummary ? widget.summary : 'Özet çıkarılamadı.',
                style: const TextStyle(height: 1.4),
              ),
              if (hasSummary)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: saveSummary,
                  title: const Text('Özeti nota ekle'),
                  onChanged: (v) => setState(() => saveSummary = v == true),
                ),
              const SizedBox(height: 8),
              const Text(
                'Bulunan görevler',
                style: TextStyle(
                  color: navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (widget.tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Notta görev bulunamadı.'),
                )
              else
                for (var i = 0; i < widget.tasks.length; i++)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: selected[i],
                    title: Text(widget.tasks[i]['title'] as String),
                    subtitle: _dueText(widget.tasks[i]['due']),
                    onChanged: (v) => setState(() => selected[i] = v == true),
                  ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop(<String, dynamic>{
                      'summary': hasSummary && saveSummary,
                      'tasks': [
                        for (var i = 0; i < selected.length; i++)
                          if (selected[i]) i,
                      ],
                    });
                  },
                  child: const Text('Uygula'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _dueText(Object? raw) {
    final due = DateTime.tryParse(raw?.toString() ?? '');
    if (due == null) return null;
    return Text('Hatırlatıcı: ${formatDue(due)}');
  }
}
