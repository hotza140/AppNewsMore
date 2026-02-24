import 'dart:convert';

// ignore: unused_import
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart'; // สำหรับ post request
import 'package:shared_preferences/shared_preferences.dart'; // ignore: unused_import

import 'menu.dart'; // นี่คือหน้า "Home"

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
   bool _obscureRegPassword = true;
  bool _obscureRegConfirmPassword = true;
  // Login controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Register controllers
  final TextEditingController _regEmailController = TextEditingController();
  final TextEditingController _regPasswordController = TextEditingController();
  final TextEditingController _regConfirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true; // ซ่อนรหัสผ่านตอนเริ่ม
  bool _isRegisterMode = false; // สลับโหมด Login / Register

  // ฟังก์ชัน login
  Future<Map<String, dynamic>> loginCheck(String email, String password) async {
  setState(() => _isLoading = true);

  try {
    final uri = Uri.parse('https://privatechat-api.team.orangeworkshop.info/api/login');
    // final deviceToken = await FirebaseMessaging.instance.getToken();
      String deviceToken = '';
    try {
      await FirebaseMessaging.instance.requestPermission(); // iOS สำคัญ
      deviceToken = (await FirebaseMessaging.instance.getToken()) ?? '';
    } catch (e) {
      debugPrint('⚠️ FCM token error (ignore): $e');
      deviceToken = '';
    }

    final response = await post(
      uri,
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        "username": email,
        "password": password,
        "device_token": deviceToken,
      }),
    );

    final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
    print('✅ Login Response JSON: $jsonResponse');

    // แก้ตรงนี้: return success + message ไม่ว่าจะ status code อะไร
    return {
      'success': jsonResponse['success'] == true,
      'token': jsonResponse['token'] ?? '',
      'user': jsonResponse['user'] ?? {},
      'message': jsonResponse['message'] ?? 'อีเมลหรือรหัสผ่านไม่ถูกต้อง',
    };
  } catch (e) {
    print('Network error: $e');
    return {
      'success': false,
      'error': 'network',
      'message': 'เกิดข้อผิดพลาดทางเครือข่าย',
    };
  } finally {
    setState(() => _isLoading = false);
  }
}


  void _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty) {
      _showMessage('กรุณากรอกอีเมล');
      return;
    }
    if (password.isEmpty) {
      _showMessage('กรุณากรอกรหัสผ่าน');
      return;
    }

    final result = await loginCheck(email, password);

    if (result['success'] == true) {
      final token = result['token'];
      final user = result['user'];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);

      if (user != null) {
        final userJson = jsonEncode(user);
        await prefs.setString('user_info', userJson);
      }

      final token_api = await SharedPreferences.getInstance();
      await token_api.setString('token_api', user['token']);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        CupertinoPageRoute(builder: (_) => const MenuPage(initialIndex: 1)),
      );
    } else {
      if (result['error'] == 'network') {
        _showMessage('เกิดข้อผิดพลาดทางเครือข่าย');
      } else {
      // ดึง message จาก JSON ตรง ๆ หรือ fallback ข้อความ default
final apiMessage = result['message']?.toString() ?? 'อีเมลหรือรหัสผ่านไม่ถูกต้อง กรุณาลองใหม่';
_showMessage(apiMessage);
      }
    }
  }

  // สมัครสมาชิก
  Future<void> registerUser() async {
    final email = _regEmailController.text.trim();
    final password = _regPasswordController.text.trim();
    final confirmPassword = _regConfirmPasswordController.text.trim();

    print('password: ${password}');
    print('confirmPassword: ${confirmPassword}');

    if (email.isEmpty) {
      _showMessage('กรุณากรอก Username');
      return;
    }
    if (password.isEmpty) {
      _showMessage('กรุณากรอกรหัสผ่าน');
      return;
    }
    if (password != confirmPassword) {
      _showMessage('รหัสผ่านและยืนยันรหัสผ่านไม่ตรงกัน');
      return; // ✅ เช็คตรงนี้เลย
    }

    setState(() => _isLoading = true);

    final uri = Uri.parse(
        'https://privatechat-api.team.orangeworkshop.info/api/user_register/register');

    try {
      final response = await post(
        uri,
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'name': email,      // เพิ่มบรรทัดนี้หลอกระบบ
          'username': email,
          'password': password,
          'password_confirmation': confirmPassword
        }),
      );

      setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        // ignore: unused_local_variable
        final data = jsonDecode(response.body);
        
          if (!mounted) return;
          // ✅ สมัครเสร็จแล้ว เด้ง dialog ก่อน
          showCupertinoDialog(
            context: context,
            builder: (context) => CupertinoAlertDialog(
              title: const Text('แจ้งเตือน'),
              content: const Text('สมัครสมาชิกสำเร็จ กรุณารอการอนุมัติจากแอดมิน'),
              actions: [
                CupertinoDialogAction(
                  child: const Text('ตกลง'),
                  onPressed: () {
                    Navigator.of(context).pop(); // ปิด dialog
                    setState(() {
                      _isRegisterMode = false; // กลับไป login
                    });
                  },
                ),
              ],
            ),
          );
      } else {
        try {
          final errorData = jsonDecode(response.body);
          final errorMessage =
              errorData['message'] ?? 'สมัครสมาชิกไม่สำเร็จ (สถานะ ${response.statusCode})';
          _showMessage(errorMessage);
        } catch (e) {
          _showMessage('สมัครสมาชิกไม่สำเร็จ (สถานะ ${response.statusCode})');
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showMessage('เกิดข้อผิดพลาดทางเครือข่าย');
    }
  }

  void _showMessage(String message) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('แจ้งเตือน'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('ตกลง'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        backgroundColor: const Color(0xFF1B386A),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          child: const Icon(
            CupertinoIcons.back,
            color: CupertinoColors.white,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        middle: Text(
          _isRegisterMode ? 'สมัครสมาชิก' : 'เข้าสู่ระบบ',
          style: const TextStyle(color: CupertinoColors.white),
        ),
        border: null,
      ),
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: _isRegisterMode ? _buildRegisterForm() : _buildLoginForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'News Global',
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.bold,
            decoration: TextDecoration.none,
            color: Color(0xFF1B386A),
            shadows: [
              Shadow(
                offset: Offset(2, 2),
                blurRadius: 4,
                color: Color.fromARGB(80, 0, 78, 159),
              ),
            ],
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 60),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1B386A),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.systemGrey.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              CupertinoTextField(
                controller: _emailController,
                placeholder: 'Username',
                keyboardType: TextInputType.text,
                autocorrect: false,
                clearButtonMode: OverlayVisibilityMode.editing,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey6,
                  borderRadius: BorderRadius.circular(12),
                ),
                prefix: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    CupertinoIcons.person,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              CupertinoTextField(
                controller: _passwordController,
                placeholder: 'รหัสผ่าน',
                obscureText: _obscurePassword,
                clearButtonMode: OverlayVisibilityMode.editing,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey6,
                  borderRadius: BorderRadius.circular(12),
                ),
                prefix: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    CupertinoIcons.lock,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
                suffix: CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: Icon(
                    _obscurePassword ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                    color: CupertinoColors.systemGrey,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              const SizedBox(height: 30),
              _isLoading
                  ? const CupertinoActivityIndicator(radius: 18)
                  : CupertinoButton.filled(
                      onPressed: _handleLogin,
                      borderRadius: BorderRadius.circular(16),
                      padding:
                          const EdgeInsets.symmetric(vertical: 16, horizontal: 80),
                      child: const Text(
                        'เข้าสู่ระบบ',
                        style:
                            TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
              const SizedBox(height: 20),
              CupertinoButton(
                onPressed: () {
                  setState(() {
                    _isRegisterMode = true;
                  });
                },
                child: const Text(
                  'ยังไม่มีบัญชี? สมัครสมาชิก',
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    decorationColor: CupertinoColors.white,
                    color: CupertinoColors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterForm() {

  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Username',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Color(0xFF1B386A),
          fontSize: 16,
          decoration: TextDecoration.none,
        ),
      ),
      const SizedBox(height: 6),
      CupertinoTextField(
        controller: _regEmailController,
        keyboardType: TextInputType.text,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFE6F0FF),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'รหัสผ่าน (อย่างน้อย 6 ตัว)',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Color(0xFF1B386A),
          fontSize: 16,
          decoration: TextDecoration.none,
        ),
      ),
      const SizedBox(height: 6),
      StatefulBuilder(
        builder: (context, setStatePassword) {
          return CupertinoTextField(
            controller: _regPasswordController,
            obscureText: _obscureRegPassword,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F0FF),
              borderRadius: BorderRadius.circular(12),
            ),
            suffix: CupertinoButton(
  padding: EdgeInsets.zero,
  child: Icon(
    _obscureRegPassword ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
    color: CupertinoColors.systemGrey,
  ),
onPressed: () {
  setStatePassword(() {  // ✅ ใช้ setState ของ StatefulBuilder
    _obscureRegPassword = !_obscureRegPassword;
  });
}
),
          );
        },
      ),
      const SizedBox(height: 20),
      const Text(
        'ยืนยันรหัสผ่าน',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Color(0xFF1B386A),
          fontSize: 16,
          decoration: TextDecoration.none,
        ),
      ),
      const SizedBox(height: 6),
      StatefulBuilder(
        builder: (context, setStateConfirm) {
          return CupertinoTextField(
            controller: _regConfirmPasswordController,
            obscureText: _obscureRegConfirmPassword,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F0FF),
              borderRadius: BorderRadius.circular(12),
            ),
            suffix: CupertinoButton(
              padding: EdgeInsets.zero,
              child: Icon(
                _obscureRegConfirmPassword ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                color: CupertinoColors.systemGrey,
              ),
              onPressed: () {
                setStateConfirm(() {
                  _obscureRegConfirmPassword = !_obscureRegConfirmPassword;
                });
              },
            ),
          );
        },
      ),
      const SizedBox(height: 30),
      Center(
        child: Column(
          children: [
            _isLoading
                ? const CupertinoActivityIndicator(radius: 18)
                : CupertinoButton.filled(
                    onPressed: registerUser,
                    borderRadius: BorderRadius.circular(16),
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 80),
                    child: const Text(
                      'สมัครสมาชิก',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
            const SizedBox(height: 12),
            CupertinoButton(
              onPressed: () {
                setState(() {
                  _isRegisterMode = false;
                });
              },
              child: const Text('กลับไปหน้าเข้าสู่ระบบ'),
            ),
          ],
        ),
      ),
    ],
  );
}

}
