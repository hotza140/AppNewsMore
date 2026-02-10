import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'menu.dart';

class DisplayCodePage extends StatefulWidget {
  const DisplayCodePage({super.key});

  @override
  State<DisplayCodePage> createState() => _DisplayCodePageState();
}

class _DisplayCodePageState extends State<DisplayCodePage> {
  Map<String, dynamic>? userInfo;   // user ของเรา
  Map<String, dynamic>? friendInfo; // เพื่อนที่จะแสดง
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSessionData();
  }

  Future<void> _loadSessionData() async {
    final prefs = await SharedPreferences.getInstance();

    final userJson = prefs.getString('user_info');
    final friendJson = prefs.getString('friend_info');

    if (userJson != null) {
      userInfo = jsonDecode(userJson);
    }

    if (friendJson != null) {
      friendInfo = jsonDecode(friendJson);
    } else {
      // friendInfo = userInfo; // fallback
      friendInfo = null; // fallback
    }

    setState(() {});
  }

  Future<void> _addFriend() async {
  if (userInfo == null || friendInfo == null) {
    _showAlert('ไม่พบข้อมูลผู้ใช้หรือเพื่อน');
    return;
  }

  setState(() {
    isLoading = true;
  });

  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token_api');

    final url = Uri.parse('https://privatechat-api.team.orangeworkshop.info/api/manage-friend/add');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', // ✅ เพิ่ม Token ที่นี่
      },
      body: jsonEncode({
        'user_id': userInfo!['id'],
        'friend_id': friendInfo!['id'],
      }),
    );

    if (response.statusCode == 200) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('friend_info');

      _showAlert('เพิ่มเพื่อนสำเร็จ!', onOk: () {
        Navigator.pushReplacement(
          context,
          CupertinoPageRoute(builder: (_) => MenuPage(initialIndex: 2)),
        );
      });
    } else {
      final body = json.decode(response.body);
      _showAlert('เพิ่มเพื่อนล้มเหลว (${body['message']})');
    }
  } catch (e) {
    _showAlert('เกิดข้อผิดพลาด: $e');
  } finally {
    setState(() {
      isLoading = false;
    });
  }
}


  void _showAlert(String message, {VoidCallback? onOk}) {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('แจ้งเตือน'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('ตกลง'),
            onPressed: () {
              Navigator.pop(context);
              if (onOk != null) onOk();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (userInfo == null || friendInfo == null) {
      return const CupertinoPageScaffold(
        child: Center(child: CupertinoActivityIndicator()),
      );
    }

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        backgroundColor: const Color(0xFF1B386A),
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(CupertinoIcons.back, color: Colors.white),
        ),
        middle: const Text(
          'เพิ่มเพื่อน',
          style: TextStyle(color: CupertinoColors.white),
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF1B386A), width: 3),
                  image: const DecorationImage(
                    image: AssetImage('assets/images/friend_avatar.png'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                friendInfo!['name'] ?? 'ไม่พบชื่อ',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: CupertinoColors.black,
                  decoration: TextDecoration.none,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1B386A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  child: isLoading
                      ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                      : const Text(
                          'เพิ่มเพื่อน',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: CupertinoColors.white,
                          ),
                        ),
                  onPressed: isLoading ? null : _addFriend,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
