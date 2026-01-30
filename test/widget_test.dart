import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// DİKKAT: Aşağıdaki 'deneme2_1' kısmı senin proje isminle aynı olmalı.
// Eğer import hatası verirse, mevcut dosyanın en üstündeki import satırını kopyala.
import 'package:deneme2_1/main.dart';

void main() {
  testWidgets('App start smoke test', (WidgetTester tester) async {
    // 1. Uygulamayı başlat. 
    // (Eski kodda MyApp() vardı, biz KantarMobileApp() yaptık, onu çağırıyoruz)
    await tester.pumpWidget(const KantarMobileApp());

    // 2. Uygulama açıldığında ekranda "Kantar Giriş" başlığının olduğunu doğrula.
    expect(find.text('Kantar Giriş'), findsOneWidget);

    // 3. Ekranda "GİRİŞ YAP" butonunun olduğunu doğrula.
    expect(find.text('GİRİŞ YAP'), findsOneWidget);

    // 4. Ekranda eski sayaçtan kalan '0' rakamının OLMADIĞINI doğrula.
    expect(find.text('0'), findsNothing);
  });
}