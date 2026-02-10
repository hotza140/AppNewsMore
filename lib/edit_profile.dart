import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  File? _newImageFile;
  String? _oldImageUrl;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    loadUserInfo();
  }

  Future<void> loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user_info');
    if (userJson != null) {
      final user = jsonDecode(userJson);
      setState(() {
        _usernameController.text = user['username'] ?? '';
        // ใช้ค่า URL ที่เซฟมาใน user_info ตรงๆ
        _oldImageUrl = user['image'];
      });
    }
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _newImageFile = File(pickedFile.path);
      });
    }
  }

  Future<void> updateProfile() async {
    if (_usernameController.text.trim().isEmpty) {
      _showDialog('Username ห้ามว่าง');
      return;
    }

  if (_passwordController.text.trim().isNotEmpty &&
    _passwordController.text.trim() !=
        _passwordConfirmController.text.trim()) {
  _showDialog('รหัสผ่านไม่ตรงกับยืนยันรหัสผ่าน');
  return;
}


    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('ยืนยันการแก้ไขโปรไฟล์'),
        content: const Text('คุณต้องการบันทึกการเปลี่ยนแปลงหรือไม่?'),
        actions: [
          CupertinoDialogAction(
            child: const Text('ยกเลิก'),
            onPressed: () => Navigator.pop(context, false),
          ),
          CupertinoDialogAction(
            child: const Text('ตกลง'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString('token_api') ?? '';
      final userJson = prefs.getString('user_info');
      if (userJson == null) return;
      final user = jsonDecode(userJson);
      final userId = user['id'];

      String? imageBase64;
      if (_newImageFile != null) {
        final bytes = await _newImageFile!.readAsBytes();
        imageBase64 = 'data:image/png;base64,${base64Encode(bytes)}';
      }

      final body = {
        "username": _usernameController.text.trim(),
        "name": _usernameController.text.trim(),
        if (_passwordController.text.isNotEmpty) ...{
          "password": _passwordController.text.trim(),
"password_confirmation": _passwordConfirmController.text.trim(),
        },
        if (imageBase64 != null) "image": imageBase64,
      };

      final url = Uri.parse(
          "https://privatechat-api.team.orangeworkshop.info/api/user_register/update/$userId");

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);

        if (resData['data'] != null) {
          await prefs.setString('user_info', jsonEncode(resData['data']));
        }

        _showDialog('บันทึกสำเร็จ', success: true);
      } else {
        String errorMessage = 'อัพเดตไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
        try {
          final data = jsonDecode(response.body);
          if (data['message'] != null) {
            errorMessage = data['message'];
          }
        } catch (_) {}
        _showDialog(errorMessage);
      }
    } catch (e) {
      _showDialog('เกิดข้อผิดพลาด: $e');
    } finally {
      setState(() => _isLoading = false);
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
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text("แก้ไขโปรไฟล์"),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const SizedBox(height: 12),
              GestureDetector(
                onTap: pickImage,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF1B386A), width: 3),
                    image: _newImageFile != null
                        ? DecorationImage(
                            image: FileImage(_newImageFile!),
                            fit: BoxFit.cover,
                          )
                        : (_oldImageUrl != null
                            ? DecorationImage(
                                image: NetworkImage(_oldImageUrl!),
                                fit: BoxFit.cover,
                              )
                            : null),
                  ),
                  child: _newImageFile == null && _oldImageUrl == null
                      ? const Center(
                          child: Icon(
                            CupertinoIcons.camera,
                            color: Color(0xFF1B386A),
                            size: 40,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 20),
              CupertinoTextField(
                controller: _usernameController,
                placeholder: "Username",
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey6,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1B386A), width: 1.5),
                ),
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: _passwordController,
                placeholder: "Password (ถ้าไม่เปลี่ยน ปล่อยว่าง)",
                obscureText: true,
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey6,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1B386A), width: 1.5),
                ),
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: _passwordConfirmController,
                placeholder: "ยืนยัน Password",
                obscureText: true,
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey6,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1B386A), width: 1.5),
                ),
              ),
              const SizedBox(height: 20),
              if (_isLoading)
                const CupertinoActivityIndicator()
              else
                CupertinoButton.filled(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  child: const Text("บันทึกการแก้ไข"),
                  onPressed: updateProfile,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
