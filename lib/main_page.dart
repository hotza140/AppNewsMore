import 'dart:async'; // อย่าลืม import
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'login.dart';
import 'menu.dart'; // นี่คือหน้า "Home"
import 'news_detail.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  bool showNewsBadge = false;

  Timer? _longPressTimer;
  String? currentUserId; // <-- เพิ่มบรรทัดนี้

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkUnreadMessages();
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
    
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print('🔁 กลับเข้าหน้า MainPage');
      _checkUnreadMessages();
    }
  }

Future<void> _checkUnreadMessages() async {
  print('🟢 เริ่มเช็คข้อความยังไม่ได้อ่าน');

  final prefs = await SharedPreferences.getInstance();
  final userJson = prefs.getString('user_info');
  if (userJson == null) return;
  final user = jsonDecode(userJson) as Map<String, dynamic>;
  final userId = user['id'].toString();
  currentUserId = userId;

  FirebaseFirestore.instance
      .collection('chat_groups')
      .snapshots()
      .listen((groupSnapshot) {
    if (currentUserId == null) return;

    bool foundUnread = false;

    for (var groupDoc in groupSnapshot.docs) {
      final groupId = groupDoc.id;

      FirebaseFirestore.instance
          .collection('chat_groups')
          .doc(groupId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots()
          .listen((messageSnapshot) {
        if (messageSnapshot.docs.isEmpty) return;

        final message = messageSnapshot.docs.first.data();
        final senderId = message['senderId']?.toString() ?? '';
        final readBy = (message['readBy'] as List<dynamic>?) ?? [];

        if (senderId != currentUserId && !readBy.contains(currentUserId)) {
          foundUnread = true;
        }

        setState(() {
          showNewsBadge = foundUnread;
          print('✅ showNewsBadge = $showNewsBadge');
        });
      });
    }
  });
}


  Future<Map<String, dynamic>?> getUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userStr = prefs.getString('user_info');
    if (userStr == null) return null;
    return jsonDecode(userStr);
  }

 Future<List<Map<String, String?>>> fetchNews() async {
  final url = Uri.parse('https://privatechat-api.team.orangeworkshop.info/api/news_nologin/selectall_news');
  final response = await http.get(url);

  print('📡 NEWS API STATUS: ${response.statusCode}');
  print('📡 NEWS API BODY: ${response.body}');

  if (response.statusCode == 200) {
    final List<dynamic> data = json.decode(response.body);
    return data.map<Map<String, String?>>((item) {
      final imageUrl = (item['image']?.toString().isNotEmpty ?? false)
          ? item['image'].toString()
          : null;

      return {
        'title': item['title']?.toString() ?? 'No Title',
        'link': item['link']?.toString() ?? '',
        'description': item['description']?.toString() ?? '',
        'date': item['date']?.toString() ?? '',
        'image': imageUrl,
      };
    }).toList();
  } else {
    throw Exception('Failed to load news');
  }
}


  // void onLongPress(BuildContext context) {
  //   Navigator.push(
  //     context,
  //     CupertinoPageRoute(
  //       builder: (_) => const LoginPage(),
  //     ),
  //   );
  // }

  void onLongPress(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final userStr = prefs.getString('user_info');

  if (userStr != null) {
    // มีข้อมูล user แล้ว ไปหน้า MenuPage
    Navigator.pushReplacement(
      context,
      CupertinoPageRoute(builder: (_) => const MenuPage(initialIndex: 1)),
    );
  } else {
    // ยังไม่มีข้อมูล user ไปหน้า LoginPage
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => const LoginPage(),
      ),
    );
  }
  }

  @override
  Widget build(BuildContext context) {
    print('🔄 build() MainPage: showNewsBadge = $showNewsBadge');

    return CupertinoPageScaffold(
      child: SafeArea(
        child: Stack(
          children: [

         Positioned(
  top: 0,
  bottom: 0,
  left: 0,
  right: 0,
  child: RefreshIndicator(
    onRefresh: () async {
      print('🔄 รีเฟรชโดยการดึงหน้าจอ');
      await _checkUnreadMessages();
    },
    child: FutureBuilder<List<Map<String, String?>>>( // <-- ตัวเดิม
      future: fetchNews(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CupertinoActivityIndicator());
        }

        final hasError = snapshot.hasError;
        final hasData = snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty;
        final newsList = snapshot.data ?? [];

        if (hasError) {
          print('❌ error loading news: ${snapshot.error}');
        }

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(), // 👈 ทำให้ดึงได้แม้ไม่มีเนื้อหา
          padding: const EdgeInsets.only(bottom: 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.network(
                'https://images.unsplash.com/photo-1504384308090-c894fdcc538d?auto=format&fit=crop&w=800&q=80',
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
              ),
              const SizedBox(height: 12),

              if (!hasData)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(
                    'ไม่พบข่าวสาร',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),

              if (hasData)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: newsList.map((news) {
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => NewsDetailPage(
                                title: news['title'] ?? '',
                                imageUrl: news['image'] ?? '',
                                description: news['description'] ?? '',
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 150,
                                  height: 80,
                                  child: news['image'] != null &&
                                          news['image']!.isNotEmpty
                                      ? Image.network(
                                          news['image']!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              color: Colors.grey[300],
                                              child: const Icon(
                                                CupertinoIcons.photo,
                                                size: 40,
                                                color: Colors.grey,
                                              ),
                                            );
                                          },
                                        )
                                      : Container(
                                          color: Colors.grey[300],
                                          child: const Icon(
                                            CupertinoIcons.photo,
                                            size: 40,
                                            color: Colors.grey,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  news['title'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    decoration: TextDecoration.none,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

              const SizedBox(height: 30),
            ],
          ),
        );
      },
    ),
  ),
),


            Positioned(
  bottom: 20,
  right: 20,
  child: GestureDetector(
    onLongPressStart: (_) {
      // เริ่มจับเวลาเมื่อกดค้างลง
      _longPressTimer = Timer(const Duration(seconds: 3), () {
        onLongPress(context);
      });
    },
    onLongPressEnd: (_) {
      // ถ้ายังไม่ครบ 3 วินาทีแล้วปล่อยนิ้ว ให้ยกเลิกการทำงาน
      _longPressTimer?.cancel();
    },
    child: Container(
      width: 60,
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFF1B386A),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(2, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Icon(
        CupertinoIcons.refresh,
        color: Colors.white,
        size: 24,
      ),
    ),
  ),
),

            if (showNewsBadge)
              const Positioned(
                bottom: 30,
                left: 20,
                child: NewsBadge(),
              ),
          ],
        ),
      ),
    );
  }
}

class NewsBadge extends StatefulWidget {
  const NewsBadge({super.key});

  @override
  State<NewsBadge> createState() => _NewsBadgeState();
}

class _NewsBadgeState extends State<NewsBadge> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnim;
  late Animation<double> _shadowBlurAnim;

  @override
  void initState() {
    super.initState();
    print('🔔 NewsBadge ถูกโหลดแล้ว');
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _opacityAnim = Tween(begin: 1.0, end: 0.4).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _shadowBlurAnim = Tween(begin: 6.0, end: 16.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnim.value,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.redAccent.withOpacity(0.7),
                  blurRadius: _shadowBlurAnim.value,
                  spreadRadius: 1,
                  offset: const Offset(0, 0),
                ),
              ],
            ),
            child: const Text(
              '● มีข่าวสารใหม่',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        );
      },
    );
  }
}
