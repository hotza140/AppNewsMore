import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';  // ต้อง import material
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'add_friend.dart'; // นี่คือหน้า "Home"

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(     // ห่อด้วย MaterialApp
      debugShowCheckedModeBanner: false,
      home: const CodePage_Friend(),
      theme: ThemeData(
        useMaterial3: true,
      ),
    );
  }
}

class CodePage_Friend extends StatefulWidget {
  const CodePage_Friend({super.key});

  @override
  State<CodePage_Friend> createState() => _CodePage_FriendState();
}

class _CodePage_FriendState extends State<CodePage_Friend> {
  final int codeLength = 6;
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(codeLength, (_) => TextEditingController());
    _focusNodes = List.generate(codeLength, (_) => FocusNode());
    // เพิ่ม listener ให้แต่ละ focusNode เพื่อ update UI ตอน focus change
    for (var f in _focusNodes) {
      f.addListener(() {
        setState(() {}); // เพื่อรีเฟรช UI ขอบเวลามีการโฟกัสเปลี่ยน
      });
    }
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _showCupertinoAlert(String message) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('แจ้งเตือน'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('ตกลง'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  void _onCodeChanged(int index, String value) {
    if (value.length == 1 && index < codeLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    String code = _controllers.map((c) => c.text).join();
    if (code.length == codeLength && !isLoading) {
      _submitCode();
    }
  }

 Future<void> _submitCode() async {
  String code = _controllers.map((c) => c.text).join();

  if (code.length < codeLength) {
    _showCupertinoAlert('กรุณากรอกโค้ดให้ครบ 6 หลัก');
    return;
  }

  setState(() {
    isLoading = true;
  });

  try {
    final be = await SharedPreferences.getInstance();
    await be.remove('friend_info');

    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('token_api') ?? '';

    final url = Uri.parse('https://privatechat-api.team.orangeworkshop.info/api/user/by-code/${code}');
    final response = await http.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken', // ✅ เพิ่ม Token ที่นี่
      },
    );

    if (response.statusCode == 200) {
      // final List<dynamic> data = jsonDecode(response.body);

      final Map<String, dynamic> resBody = jsonDecode(response.body);
      final List<dynamic> data = resBody['data'];

      // หา user ที่โค้ดตรงกับที่กรอก
      final matchedUser = data.firstWhere(
        (user) => user['code'] == code,
        orElse: () => null,
      );

      if (matchedUser != null) {
        // เก็บข้อมูลลง session (SharedPreferences)
        await prefs.setString('auth_token', 'dummy_token'); // ถ้าจะเปลี่ยนเป็น token จริง ให้แก้ที่นี่
        await prefs.setString('friend_info', jsonEncode({
          'id': matchedUser['id'],
          'name': matchedUser['name'],
          'email': matchedUser['email'],
          'code': matchedUser['code'],
        }));

        if (!mounted) return;
        Navigator.push(
          context,
          CupertinoPageRoute(builder: (_) => DisplayCodePage()),
        );
      } else {
        _showCupertinoAlert('โค้ดไม่ถูกต้องหรือไม่มีข้อมูล');
      }
    } else {
      _showCupertinoAlert('โค้ดไม่ถูกต้องหรือไม่มีข้อมูล (${response.statusCode})');
    }
  } catch (e) {
    _showCupertinoAlert('เกิดข้อผิดพลาดในการเชื่อมต่อ\n$e');
  } finally {
    setState(() {
      isLoading = false;
    });
  }
}



  Widget _buildCodeBox(int index) {
    return Container(
      width: 40,  // สี่เหลี่ยมจัตุรัสขนาด 40x50
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      child: CupertinoTextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: _focusNodes[index].hasFocus
                ? const Color(0xFF1B386A)  // สีน้ำเงินเข้มเมื่อโฟกัส
                : Colors.grey,             // สีเทาเมื่อไม่ได้โฟกัส
            width: 2,
          ),
          borderRadius: BorderRadius.circular(6),  // มุมโค้งเล็กน้อย
        ),
        onChanged: (value) {
          if (value.length > 1) {
            _controllers[index].text = value[0];
            _controllers[index].selection = TextSelection.fromPosition(
              const TextPosition(offset: 1),
            );
            _onCodeChanged(index, value[0]);
          } else {
            _onCodeChanged(index, value);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        backgroundColor: const Color(0xFF1B386A),
        middle: const Text(
          'เพิ่มเพื่อนด้วยรหัส',
          style: TextStyle(color: CupertinoColors.white),
        ),
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(
            CupertinoIcons.back,
            color: Colors.white,
          ),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),  // ขยับลงมามากขึ้น
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ข้อความ ENTER CODE ด้านบนช่องกรอก
              const Text(
                'กรอกเลขรหัสผู้ใช้งานของเพื่อน',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 25,
                  color: Colors.black,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 24),  // ขยับช่องกรอกลงมาจากข้อความมากขึ้น
              // Row ช่องกรอกตัวเลข
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(codeLength, _buildCodeBox),
              ),
              const SizedBox(height: 20),
              if (isLoading) ...[
                const CupertinoActivityIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class NextPage extends StatelessWidget {
  const NextPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        backgroundColor: const Color(0xFF1B386A),
        middle: const Text(
          'หน้าถัดไป',
          style: TextStyle(color: CupertinoColors.white),
        ),
      ),
      child: const Center(
        child: Text(
          'คุณผ่านการตรวจสอบโค้ดแล้ว!',
          style: TextStyle(fontSize: 20),
        ),
      ),
    );
  }
}
