import 'dart:convert' as convert;
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_page.dart';
import 'edit_profile.dart';
import 'main_page.dart';
import 'profile_page.dart';

class MenuPage extends StatefulWidget {
  final int initialIndex;

  const MenuPage({super.key, this.initialIndex = 0});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  late int _currentIndex;

  String? _userName;
  String? _userCode;

  final List<Widget> _pages = [
    const MainPage(),
    const ChatPage(),
    const ProfilePage(),
    const EditProfilePage(),
  ];

  Future<Map<String, dynamic>?> getUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user_info');
    if (userJson == null) return null;
    return jsonDecode(userJson) as Map<String, dynamic>;
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    loadUserName();
  }

  void loadUserName() async {
    final user = await getUserSession();
    if (user != null && mounted) {
      setState(() {
        _userName = user['name'] as String?;
        _userCode = user['code'] as String?;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = bottomInset > 0;

    return CupertinoPageScaffold(
      child: SafeArea(
        child: Column(
          children: [
            // เนื้อหาหลัก
            Expanded(
              child: _pages[_currentIndex],
            ),

            // เมนูล่าง ซ่อนเมื่อคีย์บอร์ดขึ้น
            if (_currentIndex != 0)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: isKeyboardVisible ? 0 : 190,
                child: isKeyboardVisible
                    ? const SizedBox.shrink()
                    : Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: const BoxDecoration(
                          color: Color(0xFF1B386A),
                          border: Border(
                            top: BorderSide(
                              color: CupertinoColors.systemGrey,
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Stack(
                          children: [
                            // ✅ เนื้อหาเดิมทั้งหมด
                            SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_userName != null || _userCode != null)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: 4, bottom: 8),
                                      child: Column(
                                        children: [
                                          if (_userName != null)
                                            Text(
                                              _userName!,
                                              style: const TextStyle(
                                                color: CupertinoColors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                decoration: TextDecoration.none,
                                              ),
                                            ),
                                          if (_userCode != null)
                                            Text(
                                              'รหัสผู้ใช้งาน: $_userCode',
                                              style: const TextStyle(
                                                color: CupertinoColors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w400,
                                                decoration: TextDecoration.none,
                                              ),
                                            ),
                                          const SizedBox(height: 8),
                                          CupertinoButton.filled(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 24, vertical: 12),
                                            borderRadius:
                                                BorderRadius.circular(24),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: const [
                                                Icon(CupertinoIcons.power,
                                                    size: 20,
                                                    color:
                                                        CupertinoColors.white),
                                                SizedBox(width: 8),
                                                Text(
                                                  'ออกจากระบบ',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        CupertinoColors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            onPressed: () async {
                                              final confirm =
                                                  await showCupertinoDialog<
                                                      bool>(
                                                context: context,
                                                builder: (context) =>
                                                    CupertinoAlertDialog(
                                                  title: const Text(
                                                      'ยืนยันการออกจากระบบ'),
                                                  content: const Text(
                                                      'คุณต้องการออกจากระบบจริงหรือไม่?'),
                                                  actions: [
                                                    CupertinoDialogAction(
                                                      child:
                                                          const Text('ยกเลิก'),
                                                      onPressed: () =>
                                                          Navigator.of(context)
                                                              .pop(false),
                                                    ),
                                                    CupertinoDialogAction(
                                                      isDestructiveAction: true,
                                                      child: const Text(
                                                          'ออกจากระบบ'),
                                                      onPressed: () =>
                                                          Navigator.of(context)
                                                              .pop(true),
                                                    ),
                                                  ],
                                                ),
                                              );

                                              if (confirm == true) {
                                                final prefs =
                                                    await SharedPreferences
                                                        .getInstance();
                                                final userInfoString =
                                                    prefs.getString(
                                                        'user_info');
                                                if (userInfoString != null) {
                                                  final userInfo = convert
                                                      .jsonDecode(userInfoString);
                                                  final userId = userInfo['id'];
                                                  final authToken = prefs
                                                          .getString(
                                                              'token_api') ??
                                                      '';

                                                  final response =
                                                      await http.post(
                                                    Uri.parse(
                                                        'https://privatechat-api.team.orangeworkshop.info/api/logout'),
                                                    headers: {
                                                      'Content-Type':
                                                          'application/json',
                                                      'Authorization':
                                                          'Bearer $authToken',
                                                      'Accept':
                                                          'application/json',
                                                    },
                                                    body: convert.jsonEncode(
                                                        {'user_id': userId}),
                                                  );

                                                  print(
                                                      '📡 Logout API response: ${response.statusCode} ${response.body}');
                                                }

                                                await prefs.remove('user_info');

                                                if (mounted) {
                                                  setState(() {
                                                    _userName = null;
                                                    _userCode = null;
                                                    _currentIndex = 0;
                                                  });

                                                  Navigator.of(context)
                                                      .pushAndRemoveUntil(
                                                    CupertinoPageRoute(
                                                        builder: (_) =>
                                                            const MainPage()),
                                                    (route) => false,
                                                  );
                                                }
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    ),

                                  // ไอคอนเมนูล่าง
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: List.generate(4, (index) {
                                      final iconData = [
                                        CupertinoIcons.home,
                                        CupertinoIcons.chat_bubble_2,
                                        CupertinoIcons.person_add,
                                        CupertinoIcons.pencil,
                                      ][index];
                                      final label = [
                                        'หน้าหลัก',
                                        'แชท',
                                        'เพื่อน',
                                        'โปรไฟล์'
                                      ][index];
                                      final isSelected =
                                          _currentIndex == index;

                                      return GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _currentIndex = index;
                                          });
                                        },
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              iconData,
                                              size: isSelected ? 36 : 30,
                                              color: isSelected
                                                  ? CupertinoColors.white
                                                  : CupertinoColors.white
                                                      .withOpacity(0.7),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              label,
                                              style: TextStyle(
                                                color: isSelected
                                                    ? CupertinoColors.white
                                                    : CupertinoColors.white
                                                        .withOpacity(0.7),
                                                fontSize: 14,
                                                decoration:
                                                    TextDecoration.none,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ),
                                ],
                              ),
                            ),

                            // ⭐ เวอร์ชัน v1.1 มุมซ้ายบน
                            const Positioned(
                              left: 12,
                              top: 8,
                              child: Text(
                                'v1.5',
                                style: TextStyle(
                                  color: CupertinoColors.white,
                                  fontSize: 12,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),

                          ],
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
