import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'new_group_2.dart'; // นี่คือหน้า "Home"

class NewGroup extends StatefulWidget {
  const NewGroup({super.key});

  @override
  State<NewGroup> createState() => _NewGroup();
}

class _NewGroup extends State<NewGroup> {
  List<Map<String, dynamic>> chatGroups = [];
  String searchText = '';
  final Set<int> selectedGroupIds = {};
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    fetchFriends();
  }

  Future<Map<String, dynamic>?> getUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user_info');
    if (userJson == null) return null;
    return jsonDecode(userJson) as Map<String, dynamic>;
  }

  Future<void> fetchFriends() async {
  setState(() {
    isLoading = true;
  });

  final prefs = await SharedPreferences.getInstance();
  final authToken = prefs.getString('token_api') ?? '';

  final user = await getUserSession();
  if (user == null) {
    setState(() {
      isLoading = false;
    });
    return;
  }

  final userId = user['id'];

  final url = Uri.parse(
      'https://privatechat-api.team.orangeworkshop.info/api/manage-friend/get-by-id/$userId');

  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $authToken',
  };

  final response = await http.get(url, headers: headers);

  if (response.statusCode == 200) {
    final List<dynamic> friendUserData = json.decode(response.body)['data'];

    final filteredUsers = friendUserData.map<Map<String, dynamic>>((u) {
      return {
        'id': u['id'],          // id เพื่อน
        'name': u['name'],      // ชื่อ
        'image': u['image'],    // รูป
        'code': u['code'],      // รหัสเพื่อน
        // ไม่มี pivot → ไม่ต้องใช้ในหน้านี้
      };
    }).toList();

    setState(() {
      chatGroups = filteredUsers;
      isLoading = false;
    });
  } else {
    setState(() {
      isLoading = false;
    });
    print('API Error: ${response.statusCode} ${response.body}');
  }
}


  @override
  Widget build(BuildContext context) {
    final filteredGroups = chatGroups.where((group) {
      return group['name']
          .toString()
          .toLowerCase()
          .contains(searchText.toLowerCase());
    }).toList();

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        backgroundColor: const Color(0xFF1B386A),
        middle: const Text(
          'เพิ่มกลุ่มใหม่',
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
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: CupertinoSearchTextField(
                placeholder: 'ค้นหาเพื่อน',
                onChanged: (value) {
                  setState(() {
                    searchText = value;
                  });
                },
              ),
            ),
            Expanded(
              child: isLoading
                  ? const Center(child: CupertinoActivityIndicator())
                  : filteredGroups.isEmpty
                      ? const Center(
                          child: Text('ไม่พบข้อมูล',
                              style: TextStyle(
                                  color: Colors.grey,
                                  decoration: TextDecoration.none)),
                        )
                      : ListView.builder(
                          itemCount: filteredGroups.length,
                          itemBuilder: (context, index) {
                            final group = filteredGroups[index];
                            final isSelected = selectedGroupIds.contains(group['id']);

                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    selectedGroupIds.remove(group['id']);
                                  } else {
                                    selectedGroupIds.add(group['id']);
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                color: isSelected
                                    ? CupertinoColors.systemGrey5
                                    : CupertinoColors.white,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade300,
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        (group['name'] ?? '?')[0].toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 20,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        group['name'],
                                        style: const TextStyle(
                                          fontSize: 18,
                                          color: Colors.black,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      isSelected
                                          ? CupertinoIcons.check_mark_circled_solid
                                          : CupertinoIcons.circle,
                                      color: isSelected
                                          ? CupertinoColors.activeBlue
                                          : CupertinoColors.inactiveGray,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            // if (selectedGroupIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: CupertinoButton(
                  color: const Color(0xFF1B386A),
                  child: const Text(
                    'ยืนยัน',
                    style: TextStyle(color: Colors.white),
                  ),
                 onPressed: () {
                  Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => NewGroup_end(
                        code: 'T__T',
                        selectedUserIds: selectedGroupIds.toList(),
                      ),
                    ),
                  );
                },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
