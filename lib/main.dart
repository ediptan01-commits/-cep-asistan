import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
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
  defaultValue: 'https://YOUR-SERVER.example.com/chat',
);

const String monthlyProductId = 'cepasistan_pro_monthly';
const String yearlyProductId = 'cepasistan_pro_yearly';

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
        colorScheme: ColorScheme.fromSeed(seedColor: navy),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF5F7FB),
          foregroundColor: navy,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE0E5ED)),
          ),
        ),
      ),
      home: const HomePage(),
    );
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

  Future<void> setAiUses(int value) async {
    await _prefs?.setInt('ai_uses', value);
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

  Future<void> _addTask() async {
    final title = await _textDialog(
      'Yeni görev',
      'Örn. Faturayı öde',
    );

    if (!mounted || title == null || title.isEmpty) return;

    tasks.insert(0, {
      'id': DateTime.now().millisecondsSinceEpoch,
      'title': title,
      'done': false,
    });

    await _saveAll();

    if (mounted) _msg('Görev eklendi.');
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
    }

    await _saveAll();

    if (mounted) _msg('Kayıt silindi.');
  }

  // --------------------------------------------------
  // ANA SAYFA KARTI
  // --------------------------------------------------

  Widget _tile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap, {
    Color color = navy,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 6,
        ),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _dashboard() {
    final pendingTasks =
        tasks.where((item) => item['done'] != true).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                navy,
                Color(0xFF3266A8),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Günlük hayatın, tek yerde.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '$pendingTasks bekleyen görev · '
                '${notes.length} not · '
                '${reminders.length} hatırlatıcı',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _addTask,
                    icon: const Icon(Icons.add),
                    label: const Text('Görev ekle'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    onPressed: _addReminder,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Hatırlatıcı'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Araçların',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        _tile(
          Icons.note_alt_outlined,
          'Notlarım',
          '${notes.length} kayıt',
          () => setState(() => tab = 1),
          color: Colors.blue,
        ),
        _tile(
          Icons.task_alt,
          'Görevlerim',
          '$pendingTasks bekleyen',
          () => setState(() => tab = 2),
          color: Colors.green,
        ),
        _tile(
          Icons.notifications_active_outlined,
          'Hatırlatıcılar',
          '${reminders.length} kayıt',
          () => setState(() => tab = 3),
          color: Colors.deepPurple,
        ),
        _tile(
          Icons.account_balance_wallet_outlined,
          'Gelir-gider',
          'Bütçeni takip et',
          () => setState(() => tab = 4),
          color: Colors.orange,
        ),
        _tile(
          Icons.picture_as_pdf_outlined,
          'Fotoğraftan PDF',
          'Fotoğraf seç, PDF oluştur ve paylaş',
          _makePdf,
          color: Colors.red,
        ),
        _tile(
          Icons.calculate_outlined,
          'Hesap makinesi ve birim dönüştürme',
          'Günlük hesaplama araçları',
          () => setState(() => tab = 5),
        ),
        _tile(
          Icons.auto_awesome,
          'Yapay zekâ asistanı',
          'Sunucu ayarlandıktan sonra kullanılır',
          () => setState(() => tab = 6),
          color: Colors.indigo,
        ),
        _tile(
          Icons.workspace_premium_outlined,
          'Pro üyelik',
          'Abonelik seçenekleri',
          () => setState(() => tab = 7),
          color: Colors.amber,
        ),
      ],
    );
  }

  // --------------------------------------------------
  // NOT / GÖREV / HATIRLATICI LİSTELERİ
  // --------------------------------------------------

Widget _listPage(
    String title,
    List<Map<String, dynamic>> data,
    Future<void> Function() add, {
    bool isTasks = false,
    bool isReminders = false,
  }) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Ekle',
            onPressed: () => add(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: data.isEmpty
          ? const Center(
              child: Text('Henüz kayıt yok. + düğmesiyle ekle.'),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: data.length,
              itemBuilder: (itemContext, index) {
                final item = data[index];

                return Card(
                  elevation: 0,
                  color: Colors.white,
                  child: ListTile(
                    leading: isTasks
                        ? Checkbox(
                            value: item['done'] == true,
                            onChanged: (value) async {
                              item['done'] = value == true;
                              await _saveAll();
                            },
                          )
                        : Icon(
                            isReminders
                                ? Icons.notifications_active_outlined
                                : Icons.description_outlined,
                          ),
                    title: Text(
                      item['title']?.toString() ?? '',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: isTasks && item['done'] == true
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      ),
                    ),
                    subtitle: Text(
                      isReminders
                          ? (DateTime.tryParse(
                                    item['when']?.toString() ?? '',
                                  )
                                  ?.toLocal()
                                  .toString() ??
                              '')
                          : (item['body']?.toString() ?? ''),
                    ),
                    trailing: IconButton(
                      tooltip: 'Sil',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        _delete(
                          data,
                          index,
                          reminder: isReminders,
                        );
                      },
                    ),
                  ),
                );
              },
            ),
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
      'Araçlar',
      'Yapay zekâ',
      'Pro üyelik',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          pageTitles[tab],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: tab,
              children: [
                _dashboard(),
                _listPage('Notlarım', notes, _addNote),
                _listPage(
                  'Görevlerim',
                  tasks,
                  _addTask,
                  isTasks: true,
                ),
                _listPage(
                  'Hatırlatıcılar',
                  reminders,
                  _addReminder,
                  isReminders: true,
                ),
                _budgetPage(),
                const ToolsPage(),
                AiPage(onMessage: _msg),
                ProPage(onMessage: _msg),
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
            if (index == 0) {
              tab = 0;
            } else if (index == 1) {
              tab = 1;
            } else if (index == 2) {
              tab = 2;
            } else {
              tab = 5;
            }
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
            label: 'Notlar',
          ),
          NavigationDestination(
            icon: Icon(Icons.task_alt_outlined),
            label: 'Görevler',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            label: 'Araçlar',
          ),
        ],
      ),
      floatingActionButton: tab == 1
          ? FloatingActionButton(
              onPressed: _addNote,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

// --------------------------------------------------
// HESAP MAKİNESİ VE BİRİM DÖNÜŞTÜRÜCÜ
// --------------------------------------------------

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  final TextEditingController a = TextEditingController();
  final TextEditingController b = TextEditingController();
  final TextEditingController amount = TextEditingController(text: '1');

  String op = '+';
  String result = '';
  String unit = 'Metre';
  String converted = '100 Santimetre';

  void calc() {
    final x = double.tryParse(a.text.replaceAll(',', '.'));
    final y = double.tryParse(b.text.replaceAll(',', '.'));

    if (x == null || y == null) {
      setState(() => result = 'İki sayı gir.');
      return;
    }

    if (op == '÷' && y == 0) {
      setState(() => result = 'Sıfıra bölünemez.');
      return;
    }

    final answer = op == '+'
        ? x + y
        : op == '-'
            ? x - y
            : op == '×'
                ? x * y
                : x / y;

    setState(() => result = 'Sonuç: $answer');
  }

  void convert() {
    final value = double.tryParse(
      amount.text.replaceAll(',', '.'),
    );

    if (value == null) {
      setState(() => converted = 'Geçerli sayı gir.');
      return;
    }

    setState(() {
      converted = unit == 'Metre'
          ? '${value * 100} Santimetre'
          : '${value / 100} Metre';
    });
  }

  @override
  void dispose() {
    a.dispose();
    b.dispose();
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'Hesap makinesi',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextField(
                  controller: a,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Birinci sayı',
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initualvalue: op,
                  decoration: const InputDecoration(labelText: 'İşlem'),
                  items: ['+', '-', '×', '÷']
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => op = value);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: b,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'İkinci sayı',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: calc,
                  child: const Text('Hesapla'),
                ),
                const SizedBox(height: 8),
                Text(result),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'Uzunluk dönüştürücü',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Miktar',
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: unit,
                  decoration: const InputDecoration(labelText: 'Birim'),
                  items: const [
                    DropdownMenuItem(
                      value: 'Metre',
                      child: Text('Metre → Santimetre'),
                    ),
                    DropdownMenuItem(
                      value: 'Santimetre',
                      child: Text('Santimetre → Metre'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => unit = value);
                      convert();
                    }
                  },
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: convert,
                  child: const Text('Dönüştür'),
                ),
                const SizedBox(height: 8),
                Text(converted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------
// YAPAY ZEKÂ ASİSTANI
// --------------------------------------------------

class AiPage extends StatefulWidget {
  final void Function(String) onMessage;

  const AiPage({
    super.key,
    required this.onMessage,
  });

  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  final TextEditingController input = TextEditingController();
  final List<String> history = [];

  bool busy = false;

  Future<void> send() async {
    final message = input.text.trim();

    if (message.isEmpty || busy) return;

    final isPro = Store.instance.isPro;
    final used = Store.instance.aiUses;

    if (!isPro && used >= 5) {
      widget.onMessage(
        'Ücretsiz demo kotası doldu. Pro üyelik bölümünü incele.',
      );
      return;
    }

    if (aiEndpoint.contains('YOUR-SERVER')) {
      widget.onMessage(
        'Yapay zekâ sunucusu henüz yapılandırılmadı.',
      );
      return;
    }

    setState(() {
      busy = true;
      history.add('Sen: $message');
      input.clear();
    });

    try {
      final response = await http
          .post(
            Uri.parse(aiEndpoint),
            headers: const {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'message': message,
              'pro': isPro,
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data is Map && data['reply'] != null) {
          history.add('Asistan: ${data['reply']}');
        } else {
          history.add('Asistan: Yanıt alınamadı.');
        }

        await Store.instance.setAiUses(used + 1);
      } else {
        history.add(
          'Asistan: Sunucu hatası (${response.statusCode}).',
        );
      }
    } catch (e) {
      history.add('Asistan: Bağlantı kurulamadı.');
      debugPrint('AI bağlantı hatası: $e');
    }

    if (mounted) setState(() => busy = false);
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
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Sorunu yaz. Yapay zekâ sunucusu ayarlandıktan '
                      'sonra burada yanıt alabilirsin.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    return Card(
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(history[index]),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => send(),
                    decoration: const InputDecoration(
                      hintText: 'Bir şey sor...',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: busy ? null : send,
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
  late final StreamSubscription<List<PurchaseDetails>> purchaseSubscription;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      available = await iap.isAvailable();

      if (available) {
        final response = await iap.queryProductDetails({
          monthlyProductId,
          yearlyProductId,
        });

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
      purchaseSubscription.cancel();
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
       
