import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const KantarMobileApp());
}

class KantarMobileApp extends StatelessWidget {
  const KantarMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kantar Mobil',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('tr', 'TR'),
        Locale('en', 'US'),
      ],
      locale: const Locale('tr', 'TR'),
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[100],
        useMaterial3: false,
      ),
      home: const LoginPage(attemptAutoLogin: true),
    );
  }
}

class Satis {
  final String sirketAdi;
  final String tarihStr;
  final DateTime? tarihDt;
  final String plaka;
  final String adSoyad;
  final String netKg;
  final String netLitre;
  final double toplamTutar;
  final String aramaMetni;
  final double netKgNum;
  final double netLitreNum;
  final String urunAdi;
  final String telefon; // 1. YENİ EKLENDİ

  Satis({
    required this.sirketAdi,
    required this.tarihStr,
    required this.tarihDt,
    required this.plaka,
    required this.adSoyad,
    required this.netKg,
    required this.netLitre,
    required this.toplamTutar,
    required this.aramaMetni,
    required this.netKgNum,
    required this.netLitreNum,
    required this.urunAdi,
    required this.telefon, // 2. YENİ EKLENDİ
  });

  factory Satis.fromJson(String key, Map<String, dynamic> json) {
    String rawSirket = json['sirket_adi'] ?? 'Tanımsız Şirket';
    String rawTarih = json['tarih'] ?? '';
    if (rawTarih.isEmpty) {
      rawTarih = key.replaceAll('_', ' ');
    }

    String rawPlaka = json['plaka'] ?? '-';
    String rawAdSoyad = json['ad_soyad'] ?? 'Bilinmiyor';
    String rawUrunAdi = json['urun_adi']?.toString() ?? '-';

    // 3. Veritabanından telefon çekiliyor
    String rawTelefon = json['telefon']?.toString() ?? '-'; // YENİ EKLENDİ

    DateTime? dt;
    try {
      dt = DateTime.tryParse(rawTarih.replaceAll('.', '-'));
    } catch (_) {}

    // 4. Arama algoritmasına telefon da dahil edildi
    String searchBlob = "$rawSirket $rawPlaka $rawAdSoyad $rawUrunAdi $rawTelefon"
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .toLowerCase();

    String strKg = json['net_kg'] != null ? json['net_kg'].toString() : '-';
    String strLitre = json['net_litre'] != null ? json['net_litre'].toString() : '-';

    double valKg = 0.0;
    try {
      valKg = double.tryParse(strKg.replaceAll(',', '.')) ?? 0.0;
    } catch (_) {}

    double valLitre = 0.0;
    try {
      valLitre = double.tryParse(strLitre.replaceAll(',', '.')) ?? 0.0;
    } catch (_) {}

    return Satis(
      sirketAdi: rawSirket,
      tarihStr: rawTarih,
      tarihDt: dt,
      plaka: rawPlaka,
      adSoyad: rawAdSoyad,
      netKg: strKg,
      netLitre: strLitre,
      toplamTutar: (json['toplam_tutar'] is int)
          ? (json['toplam_tutar'] as int).toDouble()
          : (json['toplam_tutar'] is double)
          ? json['toplam_tutar']
          : double.tryParse(json['toplam_tutar'].toString()) ?? 0.0,
      aramaMetni: searchBlob,
      netKgNum: valKg,
      netLitreNum: valLitre,
      urunAdi: rawUrunAdi,
      telefon: rawTelefon, // 5. YENİ EKLENDİ
    );
  }
}

class LoginPage extends StatefulWidget {
  final bool attemptAutoLogin;

  const LoginPage({super.key, this.attemptAutoLogin = true});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String? _jsonContent;
  String _dbUrl = "";
  String? _goruntulenenProjeId;
  String? _goruntulenenEmail;
  bool _isLoading = false;
  bool _isCheckingAutoLogin = true;
  String _statusMessage = "İndirdiğiniz dosyayı seçiniz.";

  @override
  void initState() {
    super.initState();
    _otomatikGirisKontrol();
  }

  Future<void> _otomatikGirisKontrol() async {
    setState(() => _isCheckingAutoLogin = true);
    final prefs = await SharedPreferences.getInstance();
    final savedJson = prefs.getString('service_account_json');
    final savedDbUrl = prefs.getString('db_url');

    if (savedJson != null && savedJson.isNotEmpty) {
      try {
        Map<String, dynamic> map = jsonDecode(savedJson);
        String projectId = map['project_id'] ?? '';
        String url = (savedDbUrl != null && savedDbUrl.isNotEmpty)
            ? savedDbUrl
            : "https://$projectId-default-rtdb.firebaseio.com";

        setState(() {
          _jsonContent = savedJson;
          _dbUrl = url;
          _goruntulenenProjeId = projectId;
          _goruntulenenEmail = map['client_email'];
          _statusMessage = "Kayıtlı dosya hazır.";
        });

        if (widget.attemptAutoLogin) {
          await _serviceAccountIleGirisYap(savedJson, url);
        } else {
          if (mounted) setState(() {
            _isCheckingAutoLogin = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isCheckingAutoLogin = false);
      }
    } else {
      if (mounted) setState(() => _isCheckingAutoLogin = false);
    }
  }

  Future<void> _dosyaSec() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        String content = await file.readAsString();
        Map<String, dynamic> jsonMap;
        try {
          jsonMap = jsonDecode(content);
        } catch (e) {
          _hataGoster("Dosya JSON formatında değil.");
          return;
        }

        if (!jsonMap.containsKey('private_key')) {
          _hataGoster("Hatalı dosya: Private Key yok.");
          return;
        }

        String projectId = jsonMap['project_id'] ?? 'Bilinmiyor';
        setState(() {
          _jsonContent = content;
          _dbUrl = "https://$projectId-default-rtdb.firebaseio.com";
          _goruntulenenProjeId = projectId;
          _goruntulenenEmail = jsonMap['client_email'];
          _statusMessage = "Dosya yüklendi. Giriş yapabilirsiniz.";
        });
      }
    } catch (e) {
      _hataGoster("Dosya okuma hatası: $e");
    }
  }

  Future<void> _girisYapButonuTiklandi() async {
    if (_jsonContent == null) {
      _hataGoster("Lütfen önce dosya seçiniz.");
      return;
    }
    await _serviceAccountIleGirisYap(_jsonContent!, _dbUrl);
  }

  Future<void> _serviceAccountIleGirisYap(String jsonString, String dbUrl) async {
    setState(() {
      _isLoading = true;
      _statusMessage = "İnternet kontrol ediliyor...";
    });

    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 8));
      if (result.isEmpty || result[0].rawAddress.isEmpty) {
        throw const SocketException("İnternet yok");
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isCheckingAutoLogin = false;
          _statusMessage = "İnternet bağlantısı yok.";
        });
        _hataGoster("Lütfen internet bağlantınızı kontrol edin.");
      }
      return;
    }

    setState(() {
      _statusMessage = "Yetkilendirme yapılıyor...";
    });

    try {
      final creds = ServiceAccountCredentials.fromJson(jsonString);
      final scopes = [
        'https://www.googleapis.com/auth/firebase.database',
        'https://www.googleapis.com/auth/userinfo.email'
      ];

      final client = await clientViaServiceAccount(creds, scopes)
          .timeout(const Duration(seconds: 8));

      final accessToken = client.credentials.accessToken.data;

      final testUrl = Uri.parse(
          "$dbUrl/satislar.json?access_token=$accessToken&orderBy=\"\$key\"&limitToLast=1");

      final response = await http.get(testUrl).timeout(const Duration(seconds: 8));

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw "YETKİ HATASI";
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('service_account_json', jsonString);
      await prefs.setString('db_url', dbUrl);

      client.close();

      if (!mounted) return;
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HomePage(
                accessToken: accessToken, dbUrl: dbUrl, jsonString: jsonString),
          ));
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isCheckingAutoLogin = false;

          if (e is SocketException || e is TimeoutException) {
            _statusMessage = "Bağlantı sağlanamadı.";
            _hataGoster("İnternet bağlantınızı kontrol edin.");
          } else {
            _statusMessage = "Giriş başarısız.";
            _hataGoster("Hata oluştu: $e");
          }
        });
      }
    }
  }

  void _hataGoster(String mesaj) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mesaj), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingAutoLogin && widget.attemptAutoLogin) {
      return const Scaffold(body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 20), Text("Bağlanılıyor...")] )));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Giriş Ekranı")),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.vpn_key, size: 80, color: Colors.blueGrey),
              const SizedBox(height: 20),
              const Text("Giriş İzin Dosyası", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 30),

              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: [
                    if (_goruntulenenProjeId == null)
                      const Text("Henüz dosya seçilmedi.", style: TextStyle(color: Colors.grey))
                    else
                      Row(
                        children: [
                          const Icon(Icons.folder_shared, size: 20, color: Colors.blue),
                          const SizedBox(width: 10),
                          Expanded(child: Text("Proje ID: $_goruntulenenProjeId", style: const TextStyle(fontWeight: FontWeight.bold))),
                        ],
                      )
                  ],
                ),
              ),

              const SizedBox(height: 20),
              Text(_statusMessage, textAlign: TextAlign.center, style: TextStyle(color: _isLoading ? Colors.blue : Colors.black)),
              const SizedBox(height: 20),

              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _dosyaSec,
                      icon: const Icon(Icons.file_upload),
                      label: const Text("JSON Dosyası Seç"),
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), backgroundColor: Colors.blueGrey),
                    ),
                    const SizedBox(height: 15),
                    if (_jsonContent != null)
                      ElevatedButton.icon(
                        onPressed: _girisYapButonuTiklandi,
                        icon: const Icon(Icons.login),
                        label: const Text("GİRİŞ YAP"),
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), backgroundColor: Colors.green),
                      ),
                  ],
                )
            ],
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final String accessToken;
  final String dbUrl;
  final String jsonString;

  const HomePage({super.key, required this.accessToken, required this.dbUrl, required this.jsonString});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? _debounce;
  List<Satis> _hamSatislar = [];
  List<Satis> _ekrandaGosterilenSatislar = [];
  bool _isLoading = true;
  String? _errorMessage;
  late String _currentAccessToken;
  final TextEditingController _searchController = TextEditingController();

  String _secilenFiltre = 'Son 1 Hafta';
  DateTimeRange? _ozelTarihAraligi;

  double _cachedToplamTutar = 0;
  double _cachedToplamKg = 0;
  double _cachedToplamLitre = 0;

  @override
  void initState() {
    super.initState();
    _currentAccessToken = widget.accessToken;
    WidgetsBinding.instance.addPostFrameCallback((_) => _veriCekveYenile());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<String> _tokenYenile() async {
    final creds = ServiceAccountCredentials.fromJson(widget.jsonString);
    final client = await clientViaServiceAccount(creds, ['https://www.googleapis.com/auth/firebase.database']);
    final token = client.credentials.accessToken.data;
    client.close();
    return token;
  }

  Future<void> _veriCekveYenile({bool tekrarDenendi = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 4));
      if (result.isEmpty || result[0].rawAddress.isEmpty) {
        throw const SocketException("İnternet yok");
      }
    } catch (_) {
      setState(() {
        _isLoading = false;
        _errorMessage = "İnternet bağlantınızı kontrol edin.";
      });
      return;
    }

    String baseUrl = widget.dbUrl;
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }

    final DateFormat formatter = DateFormat('yyyy-MM-dd');
    final DateTime now = DateTime.now();

    String queryParams = "";
    String orderBy = '&orderBy="\$key"';

    if (_secilenFiltre == 'Tümü') {
      queryParams = orderBy;
    } else if (_secilenFiltre == 'Tarih Aralığı' && _ozelTarihAraligi != null) {
      String start = formatter.format(_ozelTarihAraligi!.start);
      String end = formatter.format(_ozelTarihAraligi!.end);
      queryParams = '$orderBy&startAt="$start"&endAt="$end\uf8ff"';
    } else {
      DateTime startDt;
      if (_secilenFiltre == 'Bugün') {
        startDt = now;
      } else if (_secilenFiltre == 'Son 1 Hafta') {
        startDt = now.subtract(const Duration(days: 7));
      } else if (_secilenFiltre == 'Son 1 Ay') {
        startDt = now.subtract(const Duration(days: 30));
      } else if (_secilenFiltre == 'Son 1 Yıl') {
        startDt = now.subtract(const Duration(days: 365));
      } else {
        startDt = now;
      }
      String startStr = formatter.format(startDt);
      queryParams = '$orderBy&startAt="$startStr"';
    }

    String fullUrl = "$baseUrl/satislar.json?access_token=$_currentAccessToken$queryParams";

    try {
      final List<Satis> gelenVeri = await compute(
          indirVeParselle,
          IsolateRequest(fullUrl, "")
      );

      if (!mounted) return;

      setState(() {
        _hamSatislar = gelenVeri;
        _isLoading = false;
      });

      _aramaFiltresiniUygula();

      if (_secilenFiltre == 'Tümü') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("${gelenVeri.length} kayıt yüklendi."),
          duration: const Duration(seconds: 2),
        ));
      }

    } catch (e) {
      setState(() {
        _isLoading = false;
        if (e.toString().contains("401") || e.toString().contains("Auth")) {
          if (!tekrarDenendi) {
            _tokenYenileVeTekrarDene();
          }
          else {
            _errorMessage = "Oturum açılamadı. Lütfen tekrar giriş yapın.";
            // _cikisYap();
          }
        } else if (e is SocketException || e is TimeoutException) {
          _errorMessage = "İnternet bağlantınızı kontrol edin.";
        } else {
          _errorMessage = "Veri alınamadı: $e";
        }
      });
    }
  }

  Future<void> _tokenYenileVeTekrarDene() async {
    try {
      _currentAccessToken = await _tokenYenile();
      _veriCekveYenile(tekrarDenendi: true);
    } catch (e) {
      setState(() => _errorMessage = "Oturum süresi doldu, tekrar giriş yapın.");
    }
  }

  void _aramaFiltresiniUygula() {
    String aramaMetni = _searchController.text.trim()
        .replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

    setState(() {
      if (aramaMetni.isEmpty) {
        _ekrandaGosterilenSatislar = List.from(_hamSatislar);
      } else {
        _ekrandaGosterilenSatislar = _hamSatislar.where((s) {
          return s.aramaMetni.contains(aramaMetni);
        }).toList();
      }
      _hesaplaVeCachele();
    });
  }

  void _hesaplaVeCachele() {
    double tempTutar = 0;
    double tempKg = 0;
    double tempLitre = 0;

    for (var item in _ekrandaGosterilenSatislar) {
      tempTutar += item.toplamTutar;
      tempKg += item.netKgNum;
      tempLitre += item.netLitreNum;
    }

    _cachedToplamTutar = tempTutar;
    _cachedToplamKg = tempKg;
    _cachedToplamLitre = tempLitre;
  }

  void _cikisYap() {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage(attemptAutoLogin: false)));
  }

  Future<void> _tarihAraligiSec() async {
    final startController = TextEditingController();
    final endController = TextEditingController();

    if (_ozelTarihAraligi != null) {
      startController.text = DateFormat('dd/MM/yyyy').format(_ozelTarihAraligi!.start);
      endController.text = DateFormat('dd/MM/yyyy').format(_ozelTarihAraligi!.end);
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text("Tarih Aralığı Giriniz"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Gün/Ay/Yıl olarak giriniz.", style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 20),
              TextField(
                controller: startController,
                keyboardType: TextInputType.number,
                maxLength: 10,
                inputFormatters: [DateTextFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Başlangıç',
                  hintText: 'GG/AA/YYYY',
                  prefixIcon: Icon(Icons.date_range),
                  border: OutlineInputBorder(),
                  counterText: "",
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: endController,
                keyboardType: TextInputType.number,
                maxLength: 10,
                inputFormatters: [DateTextFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Bitiş',
                  hintText: 'GG/AA/YYYY',
                  prefixIcon: Icon(Icons.event_busy),
                  border: OutlineInputBorder(),
                  counterText: "",
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("İptal", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                DateTime? start = _parseManualDate(startController.text);
                DateTime? end = _parseManualDate(endController.text);

                if (start == null || end == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tarih formatı hatalı (GG/AA/YYYY).")));
                  return;
                }
                if (start.isAfter(end)) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Başlangıç tarihi bitişten büyük olamaz.")));
                  return;
                }
                setState(() {
                  _ozelTarihAraligi = DateTimeRange(start: start, end: end);
                  _secilenFiltre = 'Tarih Aralığı';
                });
                Navigator.pop(context);
                _veriCekveYenile();
              },
              child: const Text("Uygula"),
            ),
          ],
        );
      },
    );
  }

  DateTime? _parseManualDate(String dateStr) {
    if (dateStr.length != 10) return null;
    try {
      List<String> parts = dateStr.split('/');
      if (parts.length != 3) return null;
      int day = int.parse(parts[0]);
      int month = int.parse(parts[1]);
      int year = int.parse(parts[2]);
      return DateTime(year, month, day);
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final numberFormat = NumberFormat("#,##0", "tr_TR");
    final currencyFormat = NumberFormat.currency(locale: "tr_TR", symbol: "₺", decimalDigits: 0);

    String tarihAraligiText = 'Tarih Aralığı';
    if (_ozelTarihAraligi != null && _secilenFiltre == 'Tarih Aralığı') {
      final df = DateFormat('dd.MM.yy');
      tarihAraligiText = "${df.format(_ozelTarihAraligi!.start)} - ${df.format(_ozelTarihAraligi!.end)}";
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Satışlar"),
        actions: [
          IconButton(
            icon: const Icon(Icons.show_chart),
            tooltip: "Analiz",
            onPressed: () {
              if (_ekrandaGosterilenSatislar.isNotEmpty) {

                DateTime now = DateTime.now();
                DateTime bitis = DateTime(now.year, now.month, now.day);
                DateTime baslangic;

                if (_secilenFiltre == 'Bugün') {
                  baslangic = bitis;
                } else if (_secilenFiltre == 'Son 1 Hafta') {
                  baslangic = bitis.subtract(const Duration(days: 6));
                } else if (_secilenFiltre == 'Son 1 Ay') {
                  baslangic = bitis.subtract(const Duration(days: 29));
                } else if (_secilenFiltre == 'Son 1 Yıl') {
                  baslangic = bitis.subtract(const Duration(days: 364));
                } else if (_secilenFiltre == 'Tarih Aralığı' && _ozelTarihAraligi != null) {
                  baslangic = DateTime(_ozelTarihAraligi!.start.year, _ozelTarihAraligi!.start.month, _ozelTarihAraligi!.start.day);
                  bitis = DateTime(_ozelTarihAraligi!.end.year, _ozelTarihAraligi!.end.month, _ozelTarihAraligi!.end.day);
                } else {
                  if (_ekrandaGosterilenSatislar.isNotEmpty && _ekrandaGosterilenSatislar.last.tarihDt != null) {
                    DateTime enEski = _ekrandaGosterilenSatislar.last.tarihDt!;
                    baslangic = DateTime(enEski.year, enEski.month, enEski.day);
                  } else {
                    baslangic = bitis;
                  }
                }

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AnalizPage(
                      tumSatislar: _ekrandaGosterilenSatislar,
                      baslangicTarihi: baslangic,
                      bitisTarihi: bitis,
                      filtreAdi: _secilenFiltre,
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Analiz için önce veri yüklenmeli.")),
                );
              }
            },
          ),
          IconButton(onPressed: _veriCekveYenile, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _cikisYap, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Dükkan Adı, Plaka veya Müşteri Ara...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.grey[200],
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                  onChanged: (val) {
                    if (_debounce?.isActive ?? false) _debounce!.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), _aramaFiltresiniUygula);
                  },
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('Bugün'),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Row(children: [
                          const Icon(Icons.date_range, size: 14),
                          const SizedBox(width: 4),
                          Text(tarihAraligiText)
                        ]),
                        selected: _secilenFiltre == 'Tarih Aralığı',
                        onSelected: (bool selected) {
                          _tarihAraligiSec();
                        },
                        selectedColor: Colors.blue,
                        labelStyle: TextStyle(
                            color: _secilenFiltre == 'Tarih Aralığı' ? Colors.white : Colors.black
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip('Son 1 Hafta'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Son 1 Ay'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Son 1 Yıl'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Tümü'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
                : _ekrandaGosterilenSatislar.isEmpty
                ? const Center(child: Text("Kayıt bulunamadı."))
                : ListView.builder(
              cacheExtent: 250,
              itemCount: _ekrandaGosterilenSatislar.length,
              padding: const EdgeInsets.only(bottom: 20, top: 5),
              itemBuilder: (context, index) => _buildSatisCard(_ekrandaGosterilenSatislar[index]),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
            decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0,-5))]),
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildSummaryItem("Adet", "${_ekrandaGosterilenSatislar.length}", Colors.purple),
                  _vertDivider(),
                  _buildSummaryItem("KG", numberFormat.format(_cachedToplamKg), Colors.green),
                  _vertDivider(),
                  _buildSummaryItem("Litre", numberFormat.format(_cachedToplamLitre), Colors.orange),
                  _vertDivider(),
                  _buildSummaryItem("Toplam Tutar", currencyFormat.format(_cachedToplamTutar), Colors.blue),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _vertDivider() => Container(width: 1, height: 35, color: Colors.grey[300]);

  Widget _buildSummaryItem(String title, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildFilterChip(String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _secilenFiltre == label,
      onSelected: (bool selected) {
        if (selected) {
          setState(() => _secilenFiltre = label);
          _veriCekveYenile();
        }
      },
      selectedColor: Colors.blue,
      labelStyle: TextStyle(color: _secilenFiltre == label ? Colors.white : Colors.black),
    );
  }

  Widget _buildSatisCard(Satis satis) {
    bool isKg = satis.netKg != "-" && satis.netKg != "";
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Tooltip(
                        message: satis.sirketAdi,
                        triggerMode: TooltipTriggerMode.tap,
                        showDuration: const Duration(seconds: 3),
                        child: Text(
                          satis.sirketAdi,
                          style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        satis.plaka,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
                Text(
                  DateFormat("dd.MM.yyyy\nHH:mm").format(satis.tarihDt ?? DateTime.now()),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
              ],
            ),

            const Divider(height: 14),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. PARÇA: AD SOYAD VE TELEFON (SOLA DAYALI)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person, size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          // AD SOYAD - TOOLTIP EKLENDİ
                          Expanded(
                            child: Tooltip(
                              message: satis.adSoyad,
                              triggerMode: TooltipTriggerMode.tap,
                              showDuration: const Duration(seconds: 3),
                              child: Text(
                                satis.adSoyad,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      // TELEFON NUMARASI
                      if (satis.telefon != '-' && satis.telefon.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Row(
                            children: [
                              const Icon(Icons.phone, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  satis.telefon,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.blueGrey,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // 2. PARÇA: ÜRÜN ADI (TAM ORTALI)
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.inventory_2, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      // ÜRÜN ADI - TOOLTIP EKLENDİ
                      Flexible(
                        child: Tooltip(
                          message: satis.urunAdi,
                          triggerMode: TooltipTriggerMode.tap,
                          showDuration: const Duration(seconds: 3),
                          child: Text(
                            satis.urunAdi,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              color: Colors.blueGrey,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 3. PARÇA: TUTAR / KG (SAĞA DAYALI)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "${NumberFormat("#,##0.00", "tr_TR").format(satis.toplamTutar)} ₺",
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 18),
                      ),
                      Text(
                        isKg ? "${satis.netKg} KG" : "${satis.netLitre} LT",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isKg ? Colors.green : Colors.orange),
                      ),
                    ],
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class DateTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (newValue.text.length < oldValue.text.length) {
      return newValue;
    }
    String formatted = '';
    for (int i = 0; i < text.length; i++) {
      if (i == 2 || i == 4) {
        formatted += '/';
      }
      formatted += text[i];
    }
    if (formatted.length > 10) {
      formatted = formatted.substring(0, 10);
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class AnalizPage extends StatefulWidget {
  final List<Satis> tumSatislar;
  final DateTime baslangicTarihi;
  final DateTime bitisTarihi;
  final String filtreAdi;

  const AnalizPage({
    super.key,
    required this.tumSatislar,
    required this.baslangicTarihi,
    required this.bitisTarihi,
    required this.filtreAdi,
  });

  @override
  State<AnalizPage> createState() => _AnalizPageState();
}

enum GrafikVeriTipi { tutar, kg, litre }

class _AnalizPageState extends State<AnalizPage> {
  GrafikVeriTipi _secilenTip = GrafikVeriTipi.tutar;
  List<FlSpot> _grafikNoktalari = [];
  double _maxY = 0;
  double _minX = 0;
  double _maxX = 0;

  @override
  void initState() {
    super.initState();
    _verileriHazirla();
  }

  void _verileriHazirla() {
    Map<int, double> gunlukToplamlar = {};

    for (var satis in widget.tumSatislar) {
      if (satis.tarihDt == null) continue;

      DateTime gununTarihi = DateTime(satis.tarihDt!.year, satis.tarihDt!.month, satis.tarihDt!.day);

      int dayKey = gununTarihi.millisecondsSinceEpoch;

      double deger = 0;
      if (_secilenTip == GrafikVeriTipi.tutar) {
        deger = satis.toplamTutar;
      } else if (_secilenTip == GrafikVeriTipi.kg) {
        deger = satis.netKgNum;
      } else {
        deger = satis.netLitreNum;
      }

      gunlukToplamlar[dayKey] = (gunlukToplamlar[dayKey] ?? 0) + deger;
    }

    List<FlSpot> noktalar = [];
    double maxDeger = 0;

    DateTime tempTarih = widget.baslangicTarihi;
    DateTime loopEnd = widget.bitisTarihi.add(const Duration(seconds: 1));

    while (tempTarih.isBefore(loopEnd)) {
      int key = tempTarih.millisecondsSinceEpoch;

      double deger = gunlukToplamlar[key] ?? 0.0;

      if (deger > maxDeger) maxDeger = deger;

      noktalar.add(FlSpot(key.toDouble(), deger));

      tempTarih = tempTarih.add(const Duration(days: 1));
    }

    double minX = widget.baslangicTarihi.millisecondsSinceEpoch.toDouble();
    double maxX = widget.bitisTarihi.millisecondsSinceEpoch.toDouble();

    if (minX == maxX) {
      maxX = minX + 86400000;
    }

    setState(() {
      _grafikNoktalari = noktalar;
      _maxY = maxDeger == 0 ? 100 : maxDeger * 1.2;
      _minX = minX;
      _maxX = maxX;
    });
  }

  Color _getAnaRenk() {
    switch (_secilenTip) {
      case GrafikVeriTipi.tutar: return Colors.green;
      case GrafikVeriTipi.kg: return Colors.blue;
      case GrafikVeriTipi.litre: return Colors.orange;
    }
  }

  String _getBaslik() {
    switch (_secilenTip) {
      case GrafikVeriTipi.tutar: return "Toplam Tutar (TL)";
      case GrafikVeriTipi.kg: return "Toplam Ağırlık (KG)";
      case GrafikVeriTipi.litre: return "Toplam Hacim (LT)";
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateFormat displayFormat = DateFormat('dd.MM.yyyy');
    String tarihAraligiYazisi = "${displayFormat.format(widget.baslangicTarihi)} - ${displayFormat.format(widget.bitisTarihi)}";
    if (widget.baslangicTarihi.year == widget.bitisTarihi.year &&
        widget.baslangicTarihi.month == widget.bitisTarihi.month &&
        widget.baslangicTarihi.day == widget.bitisTarihi.day) {
      tarihAraligiYazisi = displayFormat.format(widget.baslangicTarihi);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Analiz"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildTipSecici("Tutar", GrafikVeriTipi.tutar, Colors.green),
                const SizedBox(width: 10),
                _buildTipSecici("KG", GrafikVeriTipi.kg, Colors.blue),
                const SizedBox(width: 10),
                _buildTipSecici("Litre", GrafikVeriTipi.litre, Colors.orange),
              ],
            ),
          ),
          const Divider(height: 1),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_getBaslik(), style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  const SizedBox(height: 5),
                  Text(
                    widget.filtreAdi,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                  Text(
                    tarihAraligiYazisi,
                    style: const TextStyle(color: Colors.blueGrey, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: _grafikNoktalari.isEmpty
                ? const Center(child: Text("Görüntülenecek veri yok."))
                : Padding(
              padding: const EdgeInsets.only(right: 24, left: 10, bottom: 20),
              child: LineChart(_mainData()),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildTipSecici(String text, GrafikVeriTipi tip, Color renk) {
    bool selected = _secilenTip == tip;
    return InkWell(
      onTap: () {
        setState(() => _secilenTip = tip);
        _verileriHazirla();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? renk.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? renk : Colors.grey.shade300),
        ),
        child: Text(text, style: TextStyle(color: selected ? renk : Colors.grey, fontWeight: FontWeight.bold)),
      ),
    );
  }

  LineChartData _mainData() {
    Color anaRenk = _getAnaRenk();
    double intervalY = _maxY > 0 ? _maxY / 4 : 1.0;

    double rangeX = _maxX - _minX;
    if (rangeX <= 0) rangeX = 1;

    double intervalX = rangeX / 6;

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: intervalY,
        getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            interval: intervalX,
            getTitlesWidget: (value, meta) {
              if (value < _minX || value > _maxX) return const SizedBox.shrink();

              final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());

              String text;
              Duration diff = widget.bitisTarihi.difference(widget.baslangicTarihi);
              if (diff.inDays < 360) {
                text = DateFormat('dd/MM').format(date);
              } else {
                text = DateFormat('MM/yy').format(date);
              }

              return SideTitleWidget(
                axisSide: meta.axisSide,
                space: 12.0, // Eksen çizgisi ile yazı arasındaki boşluk
                child: Transform.rotate(
                  angle: -0.8, // Yaklaşık -45 derece dönüş
                  child: Text(
                    text,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 45,
            interval: intervalY,
            getTitlesWidget: (value, meta) {
              if (value == 0 || value > _maxY) return const SizedBox.shrink();
              String text;
              if (value >= 1000000) text = "${(value / 1000000).toStringAsFixed(1)}m";
              else if (value >= 1000) text = "${(value / 1000).toStringAsFixed(0)}k";
              else text = value.toInt().toString();
              return Text(text, style: const TextStyle(color: Colors.grey, fontSize: 10), textAlign: TextAlign.left);
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      minX: _minX, maxX: _maxX, minY: 0, maxY: _maxY,
      lineBarsData: [
        LineChartBarData(
          spots: _grafikNoktalari,
          isCurved: false,
          color: anaRenk,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [anaRenk.withOpacity(0.3), anaRenk.withOpacity(0.0)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        ),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
            return touchedBarSpots.map((barSpot) {
              final date = DateTime.fromMillisecondsSinceEpoch(barSpot.x.toInt());
              return LineTooltipItem(
                "${DateFormat('dd MMM yyyy').format(date)}\n${NumberFormat("#,##0").format(barSpot.y)}",
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              );
            }).toList();
          },
        ),
      ),
    );
  }
}

class IsolateRequest {
  final String url;
  final String token;

  IsolateRequest(this.url, this.token);
}

Future<List<Satis>> indirVeParselle(IsolateRequest req) async {
  final response = await http.get(Uri.parse(req.url)).timeout(const Duration(seconds: 30));

  if (response.statusCode != 200) {
    throw Exception("HTTP ${response.statusCode}");
  }

  if (response.body == "null" || response.body == "{}") {
    return [];
  }

  final Map<String, dynamic> rawData = jsonDecode(response.body);
  final List<Satis> tempSatislar = [];

  rawData.forEach((dateKey, transValue) {
    if (transValue is Map<String, dynamic>) {
      tempSatislar.add(Satis.fromJson(dateKey, transValue));
    }
  });

  tempSatislar.sort((a, b) {
    if (b.tarihDt == null) return -1;
    if (a.tarihDt == null) return 1;
    return b.tarihDt!.compareTo(a.tarihDt!);
  });

  return tempSatislar;
}