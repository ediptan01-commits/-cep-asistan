
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CepAsistanApp());
}

class CepAsistanApp extends StatelessWidget {
  const CepAsistanApp({super.key});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF183153);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CepAsistan',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: navy,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF5F7FB),
          foregroundColor: navy,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const CepHome(),
    );
  }
}

class CepHome extends StatefulWidget {
  const CepHome({super.key});

  @override
  State<CepHome> createState() => _CepHomeState();
}

class _CepHomeState extends State<CepHome> {
  int page = 0;
  bool loading = true;

  List<Map<String, dynamic>> notes = [];
  List<Map<String, dynamic>> tasks = [];

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();

    try {
      final savedNotes = jsonDecode(prefs.getString('notes') ?? '[]');
      final savedTasks = jsonDecode(prefs.getString('tasks') ?? '[]');

      if (savedNotes is List && savedTasks is List) {
        notes = savedNotes
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        tasks = savedTasks
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {
      notes = [];
      tasks = [];
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notes', jsonEncode(notes));
    await prefs.setString('tasks', jsonEncode(tasks));
  }

  void message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> addNote() async {
    final title = TextEditingController();
    final body = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Yeni not'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Not başlığı',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: body,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: 'Notunu buraya yaz...',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty &&
                  body.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      setState(() {
        notes.insert(0, {
          'title': title.text.trim().isEmpty
              ? 'Başlıksız not'
              : title.text.trim(),
          'body': body.text.trim(),
          'date': DateTime.now().toIso8601String(),
        });
      });
      await saveData();
      message('Not kaydedildi.');
    }

    title.dispose();
    body.dispose();
  }

  Future<void> addTask() async {
    final controller = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Yeni görev'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Örn. Faturayı öde',
          ),
          onSubmitted: (_) {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(dialogContext, true);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      setState(() {
        tasks.insert(0, {
          'title': controller.text.trim(),
          'done': false,
        });
      });
      await saveData();
      message('Görev eklendi.');
    }

    controller.dispose();
  }

  Future<void> deleteItem(bool isNote, int index) async {
    setState(() {
      if (isNote) {
        notes.removeAt(index);
      } else {
        tasks.removeAt(index);
      }
    });
    await saveData();
    message('Silindi.');
  }


Widget card({
  required IconData icon,
  required String title,
  required String subtitle,
  required Color color,
  required VoidCallback onTap,
}) {
  return Card(
    elevation: 0,
    color: Colors.white,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
  

  Widget dashboard() {
    final pending = tasks.where((t) => t['done'] != true).length;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF183153), Color(0xFF3266A8)],
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
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$pending bekleyen görev · ${notes.length} kayıtlı not',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF183153),
                ),
                onPressed: addTask,
                icon: const Icon(Icons.add),
                label: const Text('Görev ekle'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Araçların',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.95,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [
            card(
              icon: Icons.note_alt_outlined,
              title: 'Notlarım',
              subtitle: '${notes.length} kayıt',
              color: const Color(0xFF2674C8),
              onTap: () => setState(() => page = 1),
            ),
            card(
              icon: Icons.check_circle_outline,
              title: 'Görevlerim',
              subtitle: '$pending bekleyen',
              color: const Color(0xFF27966A),
              onTap: () => setState(() => page = 2),
            ),
            card(
              icon: Icons.calculate_outlined,
              title: 'Hesap makinesi',
              subtitle: 'Hızlı hesapla',
              color: const Color(0xFFE49A2D),
              onTap: () => setState(() => page = 3),
            ),
            card(
              icon: Icons.swap_horiz,
              title: 'Birim dönüştür',
              subtitle: 'Uzunluk ve ağırlık',
              color: const Color(0xFF8C56C8),
              onTap: () => setState(() => page = 3),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.auto_awesome, color: Color(0xFF3266A8)),
            title: const Text('Yapay zekâ asistanı'),
            subtitle: const Text('Yakında kullanıma açılacak'),
            trailing: const Icon(Icons.lock_outline),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'CepAsistan · Ücretsiz sürüm',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  Widget notesPage() {
    if (notes.isEmpty) {
      return const Center(
        child: Text('Henüz notun yok.\n+ düğmesiyle ilk notunu ekle.',
            textAlign: TextAlign.center),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        return Card(
          elevation: 0,
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: Text(note['title']?.toString() ?? 'Not'),
            subtitle: Text(
              note['body']?.toString() ?? '',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: 'Notu sil',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => deleteItem(true, index),
            ),
          ),
        );
      },
    );
  }

  Widget tasksPage() {
    if (tasks.isEmpty) {
      return const Center(
        child: Text('Henüz görevin yok.\n+ düğmesiyle görev ekle.',
            textAlign: TextAlign.center),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        final done = task['done'] == true;

        return Card(
          elevation: 0,
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 8),
          child: CheckboxListTile(
            value: done,
            title: Text(
              task['title']?.toString() ?? '',
              style: TextStyle(
                decoration: done ? TextDecoration.lineThrough : null,
                color: done ? Colors.grey : null,
              ),
            ),
            onChanged: (value) async {
              setState(() => task['done'] = value ?? false);
              await saveData();
            },
            secondary: IconButton(
              tooltip: 'Görevi sil',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => deleteItem(false, index),
            ),
          ),
        );
      },
    );
  }

  Widget toolsPage() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: const [
        Text(
          'Günlük araçlar',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 14),
        CalculatorTool(),
        SizedBox(height: 18),
        ConverterTool(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['CepAsistan', 'Notlarım', 'Görevlerim', 'Araçlar'];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          titles[page],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (page == 1 || page == 2)
            IconButton(
              tooltip: 'Ekle',
              onPressed: page == 1 ? addNote : addTask,
              icon: const Icon(Icons.add_circle_outline),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: page,
              children: [
                dashboard(),
                notesPage(),
                tasksPage(),
                toolsPage(),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: page,
        onDestinationSelected: (index) => setState(() => page = index),
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
            selectedIcon: Icon(Icons.grid_view),
            label: 'Araçlar',
          ),
        ],
      ),
    );
  }
}

class CalculatorTool extends StatefulWidget {
  const CalculatorTool({super.key});

  @override
  State<CalculatorTool> createState() => _CalculatorToolState();
}

class _CalculatorToolState extends State<CalculatorTool> {
  final first = TextEditingController();
  final second = TextEditingController();
  String operation = '+';
  String result = '';

  void calculate() {
    final a = double.tryParse(first.text.replaceAll(',', '.'));
    final b = double.tryParse(second.text.replaceAll(',', '.'));

    if (a == null || b == null) {
      setState(() => result = 'Geçerli iki sayı gir.');
      return;
    }

    double answer;
    switch (operation) {
      case '-':
        answer = a - b;
      case '×':
        answer = a * b;
      case '÷':
        if (b == 0) {
          setState(() => result = 'Sıfıra bölünemez.');
          return;
        }
        answer = a / b;
      default:
        answer = a + b;
    }

    setState(() {
      result = 'Sonuç: ${answer.toStringAsPrecision(10)
          .replaceAll(RegExp(r'\.?0+$'), '')}';
    });
  }

  @override
  void dispose() {
    first.dispose();
    second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hesap makinesi',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: first,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'Birinci sayı'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('İşlem'),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: operation,
                  items: ['+', '-', '×', '÷']
                      .map((op) => DropdownMenuItem(
                            value: op,
                            child: Text(op),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => operation = value);
                  },
                ),
              ],
            ),
            TextField(
              controller: second,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'İkinci sayı'),
              onSubmitted: (_) => calculate(),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: calculate,
              child: const Text('Hesapla'),
            ),
            if (result.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectableText(
                result,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ConverterTool extends StatefulWidget {
  const ConverterTool({super.key});

  @override
  State<ConverterTool> createState() => _ConverterToolState();
}

class _ConverterToolState extends State<ConverterTool> {
  final amount = TextEditingController(text: '1');
  String category = 'Uzunluk';
  String from = 'Metre';
  String to = 'Santimetre';
  String result = '';

  final units = {
    'Uzunluk': {
      'Milimetre': 0.001,
      'Santimetre': 0.01,
      'Metre': 1.0,
      'Kilometre': 1000.0,
    },
    'Ağırlık': {
      'Gram': 0.001,
      'Kilogram': 1.0,
      'Ton': 1000.0,
    },
  };

  @override
  void initState() {
    super.initState();
    calculate();
  }

  void calculate() {
    final value = double.tryParse(amount.text.replaceAll(',', '.'));
    final options = units[category]!;

    if (value == null || !options.containsKey(from) ||
        !options.containsKey(to)) {
      setState(() => result = 'Geçerli bir sayı gir.');
      return;
       }

    final converted = value * options[from]! / options[to]!;
    setState(() {
      result = '${converted.toStringAsPrecision(10)
          .replaceAll(RegExp(r'\.?0+$'), '')} $to';
    });
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = units[category]!.keys.toList();

    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Birim dönüştürücü',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: category,
              decoration: const InputDecoration(labelText: 'Kategori'),
              items: units.keys
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  category = value;
                  from = units[value]!.keys.first;
                  to = units[value]!.keys.elementAt(1);
                });
                calculate();
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'Miktar'),
              onChanged: (_) => calculate(),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: from,
              decoration: const InputDecoration(labelText: 'Nereden'),
              items: options
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => from = value);
                  calculate();
                }
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: to,
              decoration: const InputDecoration(labelText: 'Nereye'),
              items: options
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => to = value);
                  calculate();
                }
              },
            ),
            const SizedBox(height: 14),
            SelectableText(
              result,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
