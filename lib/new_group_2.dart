import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'menu.dart';

class NewGroup_end extends StatefulWidget {
  final String code;
  final List<int> selectedUserIds;

  const NewGroup_end({
    super.key,
    required this.code,
    required this.selectedUserIds,
  });

  @override
  State<NewGroup_end> createState() => _NewGroup_endState();
}

class _NewGroup_endState extends State<NewGroup_end> {
  String groupName = '';
  String hour = '';
  bool isLoading = false;
  File? groupImageFile;

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        groupImageFile = File(pickedFile.path);
      });
    }
  }

  Future<Map<String, dynamic>?> getUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user_info');
    if (userJson == null) return null;
    return jsonDecode(userJson) as Map<String, dynamic>;
  }

  Future<void> createGroup() async {
  if (groupName.trim().isEmpty) {
    _showDialog('Please enter a group name.');
    return;
  }

  if (hour.trim().isEmpty) {
    _showDialog('Please enter number of Day.');
    return;
  }

  final user = await getUserSession();
  if (user == null) {
    _showDialog('User session not found.');
    return;
  }
  final userId = user['id'];

  setState(() {
    isLoading = true;
  });

  final prefs = await SharedPreferences.getInstance();
  final authToken = prefs.getString('token_api') ?? '';

  final url = Uri.parse('https://privatechat-api.team.orangeworkshop.info/api/group-chat/add');
  final allUserIds = [userId, ...widget.selectedUserIds];

  // สร้าง JSON body
  Map<String, dynamic> body = {
    'name': groupName,
    'hour': hour,
    'users': allUserIds,
  };

  // ถ้ามีรูป: แปลงเป็น base64 (API ต้องรองรับ)
  if (groupImageFile != null) {
    final bytes = await groupImageFile!.readAsBytes();
    body['image'] = 'data:image/png;base64,${base64Encode(bytes)}';
  }

  try {
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode(body),
    );

    setState(() {
      isLoading = false;
    });

    if (response.statusCode == 200 || response.statusCode == 201) {
      _showDialog('Group "$groupName" created successfully.', success: true);
    } else {
      String errorMessage = 'Failed to create group. (${response.statusCode})';
      try {
        final data = jsonDecode(response.body);
        if (data['message'] != null) errorMessage = data['message'];
      } catch (_) {}
      _showDialog(errorMessage);
    }
  } catch (e) {
    setState(() {
      isLoading = false;
    });
    _showDialog('Error: $e');
  }
}


  void _showDialog(String message, {bool success = false}) {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () {
              Navigator.pop(context);
              if (success) {
                Navigator.pushAndRemoveUntil(
                  context,
                  CupertinoPageRoute(builder: (_) => MenuPage(initialIndex: 1)),
                  (route) => false,
                );
              }
            },
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        backgroundColor: const Color(0xFF1B386A),
        leading: GestureDetector(
  onTap: () => Navigator.pop(context),
  child: const Icon(
    CupertinoIcons.back,
    color: CupertinoColors.white, // ลูกศรสีขาว
    size: 28,
  ),
),
        middle: const Text(
          'สร้างกลุ่มใหม่',
          style: TextStyle(color: CupertinoColors.white),
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: pickImage,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF1B386A), width: 3),
                    image: groupImageFile != null
                        ? DecorationImage(
                            image: FileImage(groupImageFile!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: groupImageFile == null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(CupertinoIcons.camera, color: Color(0xFF1B386A), size: 30),
                            ],
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ชื่อกลุ่ม',
                      style: TextStyle(
                        fontSize: 14,
                        color: CupertinoColors.systemGrey,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 4),
                    CupertinoTextField(
                      placeholder: 'กรอกชื่อกลุ่ม',
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemGrey6,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF1B386A), width: 1.5),
                      ),
                      style: const TextStyle(
                        fontSize: 18,
                        color: CupertinoColors.black,
                      ),
                      onChanged: (value) {
                        setState(() {
                          groupName = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'เลือกใส่จำนวนวันที่ข้อความจะแสดงก่อนถูกลบ (หากไม่ต้องการลบให้ใส่ 0)',
                      style: TextStyle(
                        fontSize: 14,
                        color: CupertinoColors.systemGrey,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 4),
                    CupertinoTextField(
                      placeholder: 'ใส่จำนวนวัน',
                      keyboardType: TextInputType.number,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      prefix: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(CupertinoIcons.time, size: 20, color: CupertinoColors.systemGrey),
                      ),
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemGrey6,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF1B386A), width: 1.3),
                      ),
                      style: const TextStyle(
                        fontSize: 18,
                        color: CupertinoColors.black,
                      ),
                      onChanged: (value) {
                        setState(() {
                          hour = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              if (isLoading)
                const CupertinoActivityIndicator()
              else
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B386A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                    child: const Text(
                      'สร้างกลุ่ม',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: CupertinoColors.white,
                      ),
                    ),
                    onPressed: createGroup,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
