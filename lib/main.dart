import 'dart:io';

// ignore: unused_import
import 'package:firebase_core/firebase_core.dart';
// ignore: unused_import
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ignore: unused_import
import 'login.dart';
// ignore: unused_import
import 'main_page.dart'; // นี่คือหน้า "Home"
import 'menu.dart'; // นี่คือหน้า "Home"

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   await Firebase.initializeApp();
//   runApp(const MyApp());
// }

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    print('Flutter Error: ${details.exception}');
  };

  try {
    await Firebase.initializeApp();

     // 🔔 ขอ permission แจ้งเตือน
  NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
  alert: true,
  badge: true,
  sound: true,
);

  print('User granted permission: ${settings.authorizationStatus}');

     const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

        const DarwinInitializationSettings initializationSettingsIOS =
    DarwinInitializationSettings();

const InitializationSettings initializationSettings =
    InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    // const InitializationSettings initializationSettings =
    //     InitializationSettings(android: initializationSettingsAndroid);


    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

// ✅ handle กรณีเปิดแอปจากการกด Notification ตอนแอปปิด
FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
  if (message != null) {
    navigatorKey.currentState?.pushReplacement(
      MaterialPageRoute(builder: (_) => const MenuPage(initialIndex: 0)),
    );
  }
});

// ✅ handle กรณีแอปเปิดอยู่แล้วกด Notification → ไม่ทำอะไร
FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
  // ไม่ต้องเรียก push หรือ pushReplacement
});


   FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;
      if (notification != null && android != null) {
        flutterLocalNotificationsPlugin.show(
  notification.hashCode,
  notification.title,
  notification.body,
  const NotificationDetails(
    android: AndroidNotificationDetails(
      'chat_channel',
      'Chat Notifications',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    ),
    iOS: DarwinNotificationDetails(),
  ),
);
      }
    });

  } catch (e, stack) {
    print('Firebase Init Error: $e\n$stack');
  }

HttpOverrides.global = MyHttpOverrides(); // 👈 เพิ่มตรงนี้
  runApp(const MyApp());
}

// void main() {
//   runApp(const MyApp());
// }

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'สื่อสารรายวัน',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey, // ✅ เพิ่มตรงนี้
      home: const SplashScreen(),
    );
  }
}


// class MyApp extends StatelessWidget {
//   const MyApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'สื่อสารรายวัน',
//       debugShowCheckedModeBanner: false,
//       home: const SplashScreen(),
//     );
//   }
// }

// ฟังก์ชันปรับความสว่างของสี (lighten)
Color lightenColor(Color color, [double amount = 0.1]) {
  assert(amount >= 0 && amount <= 1);
  final hsl = HSLColor.fromColor(color);
  final hslLight = hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0));
  return hslLight.toColor();
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  final Color baseColor = const Color(0xFF1B386A); // สีธีมหลัก

  @override
  @override
void initState() {
  super.initState();

  _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  // 🔔 ขอ permission หลังจาก widget พร้อม
  Future.delayed(const Duration(milliseconds: 500), () async {
    NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('ต้องเปิดแจ้งเตือน'),
          content: const Text('กรุณาเปิด Notification เพื่อใช้งานแอป'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ตกลง'),
            ),
          ],
        ),
      );
    }
  });

  Future.delayed(const Duration(seconds: 2), () {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MenuPage(initialIndex: 0)),
    );
  });
}

  // void initState() {
  //   super.initState();

  //   _controller = AnimationController(
  //     vsync: this,
  //     duration: const Duration(seconds: 1),
  //   )..repeat();

  //   Future.delayed(const Duration(seconds: 2), () {
  //     Navigator.of(context).pushReplacement(
  //       MaterialPageRoute(builder: (_) => const MenuPage(initialIndex: 0)),
  //     );
  //   });
  // }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              baseColor,                  // สีหลักเข้มสุด
              lightenColor(baseColor, 0.2),  // สว่างขึ้น 20%
              lightenColor(baseColor, 0.4),  // สว่างขึ้น 40%
              lightenColor(baseColor, 0.6),  // สว่างขึ้น 60%
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(30),
                child: const Icon(
                  Icons.chat_bubble_outline,
                  color: Colors.white,
                  size: 80,
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                'สื่อสารรายวัน',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 50),
              SizedBox(
                width: 50,
                height: 50,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _controller.value * 6.3,
                      child: child,
                    );
                  },
                  child: const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
