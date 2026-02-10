import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_box.dart'; // ✅ มี ChatPage_Code อยู่ในนี้ตามเดิม

class CodePage extends StatefulWidget {
  const CodePage({super.key});

  @override
  State<CodePage> createState() => _CodePageState();
}

class _CodePageState extends State<CodePage> {
  final int codeLength = 6;
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(codeLength, (_) => TextEditingController());
    _focusNodes = List.generate(codeLength, (_) => FocusNode());
    for (var f in _focusNodes) {
      f.addListener(() {
        setState(() {});
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
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  void _onCodeChanged(int index, String value) {
    if (value.length == 1 && index < codeLength - 1) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
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
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('token_api') ?? '';
    final userJson = prefs.getString('user_info');

    if (userJson == null) {
      _showCupertinoAlert('ไม่พบข้อมูลผู้ใช้ใน session');
      return;
    }

    final userData = jsonDecode(userJson);
    final String userId = userData['id'].toString();

    final url = Uri.parse('https://privatechat-api.team.orangeworkshop.info/api/group-chat/join');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode({
        'user_id': int.parse(userId),
        'group_code': code,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final group = data['data'];

      if (group != null) {
        if (!mounted) return;
        Navigator.push(
          context,
          CupertinoPageRoute(
            builder: (_) => ChatPage_Code(
              groupId: group['id'].toString(),
              groupName: group['name'],
            ),
          ),
        );
      } else {
        _showCupertinoAlert('ไม่พบโค้ดนี้ในระบบ');
      }
    } else {
      _showCupertinoAlert('เกิดข้อผิดพลาดจากเซิร์ฟเวอร์ (${response.statusCode})');
    }
  } catch (e) {
    _showCupertinoAlert('เกิดข้อผิดพลาดในการเชื่อมต่อ');
  } finally {
    setState(() {
      isLoading = false;
    });
  }
}


  Widget _buildCodeBox(int index) {
    return Container(
      width: 40,
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      child: CupertinoTextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: _focusNodes[index].hasFocus ? const Color(0xFF1B386A) : Colors.grey,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        onChanged: (value) {
          if (value.length > 1) {
            _controllers[index].text = value[0];
            _controllers[index].selection = const TextSelection.collapsed(offset: 1);
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
        middle: const Text('เพิ่มกลุ่มโดยรหัส', style: TextStyle(color: CupertinoColors.white)),
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(CupertinoIcons.back, color: Colors.white),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const Text(
                'ใส่เลขรหัสกลุ่ม',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 25,
                  color: Colors.black,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(codeLength, _buildCodeBox),
              ),
              const SizedBox(height: 20),
              if (isLoading) const CupertinoActivityIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
