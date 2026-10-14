import 'dart:convert';
import 'dart:io';
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

const navy = Color(0xFF183153);
const aiEndpoint = String.fromEnvironment('AI_ENDPOINT', defaultValue: 'https://YOUR-SERVER.example.com/chat');
const monthlyProductId = 'cepasistan_pro_monthly';
const yearlyProductId = 'cepasistan_pro_yearly';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  // Turkey local time. Change this if distributing primarily in another timezone.
  tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
  runApp(const CepAsistanApp());
}

class CepAsistanApp extends StatelessWidget {
  const CepAsistanApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CepAsistan', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: navy), scaffoldBackgroundColor: const Color(0xFFF5F7FB)),
    home: const HomePage(),
  );
}

class Store {
  static final Store instance = Store._();
  Store._();
  SharedPreferences? _prefs;
  Future<void> init() async { _prefs = await SharedPreferences.getInstance(); }
  List<Map<String, dynamic>> list(String key) {
    try { final raw = jsonDecode(_prefs?.getString(key) ?? '[]'); return (raw as List).whereType<Map>().map((e) => Map<String,dynamic>.from(e)).toList(); } catch (_) { return []; }
  }
  Future<void> put(String key, List<Map<String,dynamic>> value) async => _prefs?.setString(key, jsonEncode(value));
  int get aiUses => _prefs?.getInt('ai_uses') ?? 0;
  Future<void> setAiUses(int n) async => _prefs?.setInt('ai_uses', n);
  bool get isPro => _prefs?.getBool('is_pro_demo') ?? false;
  Future<void> setProDemo(bool v) async => _prefs?.setBool('is_pro_demo', v);
}

class NotifyService {
  static final plugin = FlutterLocalNotificationsPlugin();
  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(requestAlertPermission: true, requestBadgePermission: true, requestSoundPermission: true);
    await plugin.initialize(settings: InitializationSettings(android: android, iOS: ios));
    await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  }
  static Future<void> schedule(Map<String,dynamic> item) async {
    final date = DateTime.tryParse(item['when']?.toString() ?? '');
    if (date == null || !date.isAfter(DateTime.now())) return;
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
  static Future<void> cancel(int id) => plugin.cancel(id: id);
}

class HomePage extends StatefulWidget { const HomePage({super.key}); @override State<HomePage> createState() => _HomePageState(); }
class _HomePageState extends State<HomePage> {
  int tab = 0; bool loading = true;
  List<Map<String,dynamic>> notes = [], tasks = [], reminders = [], transactions = [];
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    await Store.instance.init(); await NotifyService.init();
    notes = Store.instance.list('notes'); tasks = Store.instance.list('tasks'); reminders = Store.instance.list('reminders'); transactions = Store.instance.list('transactions');
    if (mounted) setState(() => loading = false);
  }
  Future<void> _saveAll() async { await Store.instance.put('notes', notes); await Store.instance.put('tasks', tasks); await Store.instance.put('reminders', reminders); await Store.instance.put('transactions', transactions); if (mounted) setState(() {}); }
  void _msg(String s) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }
  Future<String?> _textDialog(String title, String hint, {String initial = ''}) async { final c = TextEditingController(text: initial); final v = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: Text(title), content: TextField(controller: c, autofocus: true, maxLines: 4, decoration: InputDecoration(hintText: hint)), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Kaydet'))])); c.dispose(); return v; }
  Future<void> _addNote() async { final title = await _textDialog('Yeni not', 'Not başlığı'); if (title == null || title.isEmpty) return; final body = await _textDialog('Not içeriği', 'Notunu yaz'); notes.insert(0, {'id': DateTime.now().millisecondsSinceEpoch, 'title': title, 'body': body ?? '', 'date': DateTime.now().toIso8601String()}); await _saveAll(); }
  Future<void> _addTask() async { final title = await _textDialog('Yeni görev', 'Örn. Faturayı öde'); if (title == null || title.isEmpty) return; tasks.insert(0, {'id': DateTime.now().millisecondsSinceEpoch, 'title': title, 'done': false}); await _saveAll(); }
  Future<void> _addReminder() async {
    final title = await _textDialog('Hatırlatıcı', 'Ne hatırlatılsın?'); if (title == null || title.isEmpty || !mounted) return;
    final date = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(hours: 1)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650))); if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1)))); if (time == null || !mounted) return;
    final when = DateTime(date.year,date.month,date.day,time.hour,time.minute); if (!when.isAfter(DateTime.now())) { _msg('Geçmiş bir zaman seçemezsin.'); return; }
    final item = {'id': DateTime.now().millisecondsSinceEpoch.remainder(2147483647), 'title': title, 'body': 'CepAsistan hatırlatıcın', 'when': when.toIso8601String()}; reminders.add(item); await _saveAll(); await NotifyService.schedule(item); _msg('Hatırlatıcı kaydedildi. Bildirim izinlerini açık tut.');
  }
  Future<void> _addTransaction() async {
    final kind = await showModalBottomSheet<String>(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [ListTile(leading: const Icon(Icons.add_circle, color: Colors.green), title: const Text('Gelir ekle'), onTap: () => Navigator.pop(ctx, 'Gelir')), ListTile(leading: const Icon(Icons.remove_circle, color: Colors.red), title: const Text('Gider ekle'), onTap: () => Navigator.pop(ctx, 'Gider'))]))); if (kind == null) return;
    final title = await _textDialog('$kind açıklaması', 'Örn. Maaş / Market'); if (title == null || title.isEmpty) return;
    final raw = await _textDialog('Tutar (TL)', 'Örn. 250,50'); if (raw == null) return; final amount = double.tryParse(raw.replaceAll('.', '').replaceAll(',', '.')); if (amount == null || amount <= 0) { _msg('Geçerli bir tutar gir.'); return; }
    transactions.insert(0, {'id': DateTime.now().millisecondsSinceEpoch, 'title': title, 'kind': kind, 'amount': amount, 'date': DateTime.now().toIso8601String()}); await _saveAll();
  }
  Future<void> _delete(List<Map<String,dynamic>> list, int index, {bool reminder = false}) async { final item = list.removeAt(index); if (reminder) await NotifyService.cancel((item['id'] as num).toInt()); await _saveAll(); }
  Widget _tile(IconData icon, String title, String sub, VoidCallback tap, {Color color = navy}) => Card(elevation: 0, color: Colors.white, child: ListTile(leading: CircleAvatar(backgroundColor: color.withValues(alpha: .12), child: Icon(icon, color: color)), title: Text(title), subtitle: Text(sub), trailing: const Icon(Icons.chevron_right), onTap: tap));
  Widget _dashboard() => ListView(padding: const EdgeInsets.all(16), children: [Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(gradient: const LinearGradient(colors: [navy, Color(0xFF3266A8)]), borderRadius: BorderRadius.circular(24)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Günlük hayatın, tek yerde.', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)), const SizedBox(height: 10), Text('${tasks.where((e)=>e['done'] != true).length} bekleyen görev · ${notes.length} not · ${reminders.length} hatırlatıcı', style: const TextStyle(color: Colors.white70)), const SizedBox(height: 16), Wrap(spacing: 8, runSpacing: 8, children: [FilledButton.icon(onPressed: _addTask, icon: const Icon(Icons.add), label: const Text('Görev ekle')), OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)), onPressed: _addReminder, icon: const Icon(Icons.notifications_active_outlined), label: const Text('Hatırlatıcı'))])])), const SizedBox(height: 16), const Text('Araçların', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)), const SizedBox(height: 8), _tile(Icons.note_alt_outlined, 'Notlarım', '${notes.length} kayıt', () => setState(() => tab = 1), color: Colors.blue), _tile(Icons.task_alt, 'Görevlerim', '${tasks.where((e)=>e['done'] != true).length} bekleyen', () => setState(() => tab = 2), color: Colors.green), _tile(Icons.notifications_active_outlined, 'Hatırlatıcılar', '${reminders.length} kayıt', () => setState(() => tab = 3), color: Colors.deepPurple), _tile(Icons.account_balance_wallet_outlined, 'Gelir-gider', 'Bütçeni takip et', () => setState(() => tab = 4), color: Colors.orange), _tile(Icons.picture_as_pdf_outlined, 'Fotoğraftan PDF', 'Fotoğraf seç, PDF oluştur ve paylaş', _makePdf, color: Colors.red), _tile(Icons.calculate_outlined, 'Hesap makinesi ve birim dönüştürme', 'Günlük hesaplama araçları', () => setState(() => tab = 5)), _tile(Icons.auto_awesome, 'Yapay zekâ asistanı', 'Ücretsiz kota + Pro', () => setState(() => tab = 6), color: Colors.indigo), _tile(Icons.workspace_premium_outlined, 'Pro üyelik', Store.instance.isPro ? 'Pro etkin (yerel test durumu)' : 'Daha yüksek kullanım kotası', () => setState(() => tab = 7), color: Colors.amber)]);
  Widget _listPage(String title, List<Map<String,dynamic>> data, Future<void> Function() add, {bool isTasks=false, bool isReminders=false}) => Scaffold(backgroundColor: Colors.transparent, appBar: AppBar(title: Text(title), actions: [IconButton(onPressed: add, icon: const Icon(Icons.add))]), body: data.isEmpty ? Center(child: Text('Henüz kayıt yok. + düğmesiyle ekle.')) : ListView.builder(padding: const EdgeInsets.all(12), itemCount: data.length, itemBuilder: (ctx,i) { final x=data[i]; return Card(elevation:0, color:Colors.white, child: ListTile(leading: isTasks ? Checkbox(value:x['done']==true, onChanged:(v) async { x['done']=v==true; await _saveAll(); }) : Icon(isReminders ? Icons.notifications_active_outlined : Icons.description_outlined), title: Text(x['title']?.toString() ?? ''), subtitle: Text(isReminders ? (DateTime.tryParse(x['when']?.toString() ?? '')?.toLocal().toString() ?? '') : (x['body']?.toString() ?? '')), trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed:()=>_delete(data,i, reminder:isReminders)))); }));
  Widget _budgetPage() { final income = transactions.where((x)=>x['kind']=='Gelir').fold<double>(0,(s,x)=>s+(x['amount'] as num).toDouble()); final expense = transactions.where((x)=>x['kind']=='Gider').fold<double>(0,(s,x)=>s+(x['amount'] as num).toDouble()); return ListView(padding: const EdgeInsets.all(16), children: [Card(elevation:0, child:Padding(padding:const EdgeInsets.all(18), child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[const Text('Toplam bakiye',style:TextStyle(fontSize:16)), Text('${(income-expense).toStringAsFixed(2)} TL',style:const TextStyle(fontSize:28,fontWeight:FontWeight.bold)), Text('Gelir: ${income.toStringAsFixed(2)} TL  ·  Gider: ${expense.toStringAsFixed(2)} TL')]))), const SizedBox(height:8), FilledButton.icon(onPressed:_addTransaction, icon:const Icon(Icons.add), label:const Text('Gelir veya gider ekle')), const SizedBox(height:8), ...transactions.map((x)=>Card(elevation:0,child:ListTile(leading:Icon(x['kind']=='Gelir'?Icons.arrow_downward:Icons.arrow_upward,color:x['kind']=='Gelir'?Colors.green:Colors.red),title:Text(x['title'].toString()),subtitle:Text(x['kind'].toString()),trailing:Text('${x['kind']=='Gelir'?'+':'-'}${(x['amount'] as num).toStringAsFixed(2)} TL'))))]); }
  Future<void> _makePdf() async { try { final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90); if (image == null) return; final bytes = await image.readAsBytes(); final doc = pw.Document(); doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain)))); final out = await doc.save(); final dir = await getTemporaryDirectory(); final file = File('${dir.path}/cep_asistan_${DateTime.now().millisecondsSinceEpoch}.pdf'); await file.writeAsBytes(out); await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')], text: 'CepAsistan PDF')); } catch(e) { _msg('PDF oluşturulamadı: $e'); } }
  @override Widget build(BuildContext context) { final pages = ['CepAsistan','Notlarım','Görevlerim','Hatırlatıcılar','Gelir-gider','Araçlar','Yapay zekâ','Pro üyelik']; return Scaffold(appBar: AppBar(title: Text(pages[tab],style:const TextStyle(fontWeight:FontWeight.bold))), body: loading ? const Center(child:CircularProgressIndicator()) : IndexedStack(index:tab, children:[_dashboard(), _listPage('Notlarım',notes,_addNote), _listPage('Görevlerim',tasks,_addTask,isTasks:true), _listPage('Hatırlatıcılar',reminders,_addReminder,isReminders:true), _budgetPage(), const ToolsPage(), AiPage(onMessage:_msg), ProPage(onMessage:_msg)]), bottomNavigationBar: NavigationBar(selectedIndex: tab>3?3:tab, onDestinationSelected:(i)=>setState(()=>tab=i), destinations:const [NavigationDestination(icon:Icon(Icons.home_outlined),selectedIcon:Icon(Icons.home),label:'Ana sayfa'),NavigationDestination(icon:Icon(Icons.note_alt_outlined),label:'Notlar'),NavigationDestination(icon:Icon(Icons.task_alt_outlined),label:'Görevler'),NavigationDestination(icon:Icon(Icons.grid_view_outlined),label:'Diğer')]), floatingActionButton: tab==1 ? FloatingActionButton(onPressed:_addNote,child:const Icon(Icons.add)) : null); }
}

class ToolsPage extends StatefulWidget { const ToolsPage({super.key}); @override State<ToolsPage> createState()=>_ToolsPageState(); }
class _ToolsPageState extends State<ToolsPage> { final a=TextEditingController(), b=TextEditingController(); String op='+', result=''; final amount=TextEditingController(text:'1'); String unit='Metre'; String converted='100 Santimetre'; void calc(){final x=double.tryParse(a.text.replaceAll(',','.')), y=double.tryParse(b.text.replaceAll(',','.')); if(x==null||y==null){setState(()=>result='İki sayı gir.');return;} if(op=='÷'&&y==0){setState(()=>result='Sıfıra bölünemez.');return;} final r=op=='+'?x+y:op=='-'?x-y:op=='×'?x*y:x/y; setState(()=>result='Sonuç: $r');} void convert(){final x=double.tryParse(amount.text.replaceAll(',','.')); if(x==null){setState(()=>converted='Geçerli sayı gir.');return;} setState(()=>converted=unit=='Metre'?'${x*100} Santimetre':'${x/100} Metre');} @override Widget build(BuildContext c)=>ListView(padding:const EdgeInsets.all(16),children:[Card(elevation:0,child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[const Text('Hesap makinesi',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),TextField(controller:a,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Birinci sayı')),DropdownButton<String>(value:op,items:['+','-','×','÷'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(x)=>setState(()=>op=x!)),TextField(controller:b,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'İkinci sayı')),FilledButton(onPressed:calc,child:const Text('Hesapla')),Text(result)]))),Card(elevation:0,child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[const Text('Uzunluk dönüştürücü',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),TextField(controller:amount,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Miktar')),DropdownButton<String>(value:unit,items:const [DropdownMenuItem(value:'Metre',child:Text('Metre → Santimetre')),DropdownMenuItem(value:'Santimetre',child:Text('Santimetre → Metre'))],onChanged:(x){setState(()=>unit=x!);convert();}),FilledButton(onPressed:convert,child:const Text('Dönüştür')),Text(converted)])))]); }

class AiPage extends StatefulWidget { final void Function(String) onMessage; const AiPage({super.key,required this.onMessage}); @override State<AiPage> createState()=>_AiPageState(); }
class _AiPageState extends State<AiPage> { final input=TextEditingController(); final history=<String>[]; bool busy=false; Future<void> send() async { final text=input.text.trim(); if(text.isEmpty||busy)return; final pro=Store.instance.isPro; final used=Store.instance.aiUses; if(!pro&&used>=5){widget.onMessage('Ücretsiz günlük demo kotası doldu. Pro üyelik bölümünü incele.');return;} if(aiEndpoint.contains('YOUR-SERVER')){widget.onMessage('Yapay zekâ sunucusu henüz kurulmadı. README dosyasındaki sunucu adımlarını uygula.');return;} setState(()=>busy=true); history.add('Sen: $text'); input.clear(); try { final response=await http.post(Uri.parse(aiEndpoint),headers:{'Content-Type':'application/json'},body:jsonEncode({'message':text,'pro':pro})).timeout(const Duration(seconds:45)); if(response.statusCode==200){final data=jsonDecode(response.body); history.add('Asistan: ${data['reply'] ?? 'Yanıt alınamadı.'}'); await Store.instance.setAiUses(used+1);} else {history.add('Asistan: Sunucu hatası (${response.statusCode}).');} } catch(e){history.add('Asistan: Bağlantı kurulamadı.');} if(mounted)setState(()=>busy=false); } @override Widget build(BuildContext c)=>Column(children:[Expanded(child:history.isEmpty?const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('Sorunu yaz; sunucu ayarlandıktan sonra yapay zekâ yanıtlayacak.',textAlign:TextAlign.center))):ListView(padding:const EdgeInsets.all(12),children:history.map((s)=>Card(elevation:0,child:Padding(padding:const EdgeInsets.all(12),child:Text(s)))).toList())),Padding(padding:const EdgeInsets.all(12),child:Row(children:[Expanded(child:TextField(controller:input,decoration:const InputDecoration(hintText:'Bir şey sor...'))),IconButton(onPressed:busy?null:send,icon:busy?const CircularProgressIndicator():const Icon(Icons.send))]))]); }

class ProPage extends StatefulWidget { final void Function(String) onMessage; const ProPage({super.key,required this.onMessage}); @override State<ProPage> createState()=>_ProPageState(); }
class _ProPageState extends State<ProPage> { final iap=InAppPurchase.instance; bool available=false, busy=false; List<ProductDetails> products=[]; @override void initState(){super.initState();_load();} Future<void> _load() async { available=await iap.isAvailable(); if(available){final r=await iap.queryProductDetails({monthlyProductId,yearlyProductId}); products=r.productDetails; iap.purchaseStream.listen((events){for(final p in events){if(p.status==PurchaseStatus.purchased||p.status==PurchaseStatus.restored){widget.onMessage('Satın alma mağazadan bildirildi. Üretimde sunucu taraflı makbuz doğrulaması eklenmeden Pro erişimi açılmamalıdır.');} if(p.pendingCompletePurchase) iap.completePurchase(p);}});} if(mounted)setState(()=>busy=false); } @override Widget build(BuildContext c)=>ListView(padding:const EdgeInsets.all(16),children:[const Icon(Icons.workspace_premium,color:Colors.amber,size:60),const Text('CepAsistan Pro',textAlign:TextAlign.center,style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),const SizedBox(height:8),const Text('Daha yüksek yapay zekâ kotası ve gelişmiş araçlar.',textAlign:TextAlign.center),const SizedBox(height:18),const ListTile(leading:Icon(Icons.check_circle,color:Colors.green),title:Text('Ücretsiz temel araçlar her zaman kullanılabilir')),const ListTile(leading:Icon(Icons.check_circle,color:Colors.green),title:Text('Pro ile daha yüksek AI kullanım kotası')),if(!available)const Text('Mağaza satın alımları şu anda kullanılamıyor.'),if(available&&products.isEmpty)const Text('Mağaza ürünleri bulunamadı. Play Console / App Store Connect ürün kimliklerini yapılandır.'),...products.map((p)=>FilledButton(onPressed:busy?null:() async {setState(()=>busy=true); await iap.buyNonConsumable(purchaseParam:PurchaseParam(productDetails:p)); if(mounted)setState(()=>busy=false);},child:Text('${p.title} · ${p.price}'))),OutlinedButton(onPressed:() async {await iap.restorePurchases();widget.onMessage('Satın alma geri yükleme isteği gönderildi.');},child:const Text('Satın alımları geri yükle')),const SizedBox(height:12),const Text('Not: Gerçek Pro erişimi için mağaza makbuzunu sunucuda doğrulayın. Bu ekran tek başına güvenli abonelik doğrulaması sağlamaz.',style:TextStyle(fontSize:12,color:Colors.grey))]); }






