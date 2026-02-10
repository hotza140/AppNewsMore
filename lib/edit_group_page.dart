import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EditGroupPage extends StatefulWidget {
  final String groupId;
  const EditGroupPage({super.key, required this.groupId});

  @override
  State<EditGroupPage> createState() => _EditGroupPageState();
}

class _EditGroupPageState extends State<EditGroupPage> {
  String groupName = '';
  String? groupImageUrl;
  File? newImageFile;
  bool isLoading = false;

  final TextEditingController _nameController = TextEditingController(); // ✅ เพิ่ม controller ถาวร

  @override
  void initState() {
    super.initState();
    fetchGroupDetail();
  }

  Future<void> fetchGroupDetail() async {
    setState(() => isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token_api') ?? '';

    final url = Uri.parse(
        'https://privatechat-api.team.orangeworkshop.info/api/group-chat/get_group_chat/${widget.groupId}');

    final res =
        await http.get(url, headers: {'Authorization': 'Bearer $token'});
    if (res.statusCode == 200) {
      final jsonRes = jsonDecode(res.body);
      final data = jsonRes['data'];
      setState(() {
        groupName = data['name'] ?? '';
        groupImageUrl = data['image'];
        _nameController.text = groupName; // ✅ อัปเดตค่าชื่อกลุ่มในช่องกรอก
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
      print('Error fetching group detail: ${res.body}');
    }
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        newImageFile = File(pickedFile.path);
      });
    }
  }

  Future<void> updateGroup() async {
    if (_nameController.text.trim().isEmpty) {
      showDialogMessage("กรุณากรอกชื่อกลุ่ม");
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token_api') ?? '';

    final url = Uri.parse(
        'https://privatechat-api.team.orangeworkshop.info/api/group-chat/update/${widget.groupId}');

    Map<String, dynamic> body = {
      'name': _nameController.text.trim(),
    };

    if (newImageFile != null) {
      final bytes = await newImageFile!.readAsBytes();
      body['image'] = 'data:image/png;base64,${base64Encode(bytes)}';
    }

    setState(() => isLoading = true);

    final res = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );

    setState(() => isLoading = false);

    if (res.statusCode == 200) {
      showDialogMessage("แก้ไขข้อมูลกลุ่มสำเร็จ", success: true);
    } else {
      print('Update failed: ${res.body}');
      showDialogMessage("เกิดข้อผิดพลาดในการบันทึกข้อมูล");
    }
  }

  void showDialogMessage(String message, {bool success = false}) {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text("ตกลง"),
            onPressed: () {
              Navigator.pop(context); // ✅ ปิด dialog เฉย ๆ
              // ❌ ไม่ย้อนกลับหน้าอีกต่อไป
            },
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
        middle: const Text(
          'แก้ไขกลุ่ม',
          style: TextStyle(color: CupertinoColors.white),
        ),
        // ✅ ใช้ปุ่ม back ปกติ (สามารถ pop ได้)
        leading: Navigator.canPop(context)
            ? const CupertinoNavigationBarBackButton(color: CupertinoColors.white)
            : null,
      ),
      child: SafeArea(
        child: isLoading
            ? const Center(child: CupertinoActivityIndicator())
            : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: pickImage,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: const Color(0xFF1B386A), width: 3),
                            image: newImageFile != null
                                ? DecorationImage(
                                    image: FileImage(newImageFile!),
                                    fit: BoxFit.cover,
                                  )
                                : (groupImageUrl != null &&
                                        groupImageUrl!.isNotEmpty)
                                    ? DecorationImage(
                                        image: NetworkImage(groupImageUrl!),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                          ),
                          child: (newImageFile == null &&
                                  (groupImageUrl == null ||
                                      groupImageUrl!.isEmpty))
                              ? const Center(
                                  child: Icon(CupertinoIcons.camera,
                                      color: Color(0xFF1B386A), size: 30),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "ชื่อกลุ่ม",
                          style: TextStyle(
                              fontSize: 14,
                              color: CupertinoColors.systemGrey,
                              decoration: TextDecoration.none),
                        ),
                      ),
                      const SizedBox(height: 4),
                      CupertinoTextField(
                        placeholder: "กรอกชื่อกลุ่ม",
                        controller: _nameController, // ✅ ใช้ controller เดิม
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemGrey6,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFF1B386A), width: 1.3),
                        ),
                      ),
                      const SizedBox(height: 30),
                      isLoading
                          ? const CupertinoActivityIndicator()
                          : CupertinoButton.filled(
                              onPressed: updateGroup,
                              child: const Text(
                                "บันทึกการแก้ไข",
                                style: TextStyle(fontSize: 18),
                              ),
                            ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
