import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:private_chat/AddFriendPage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_box.dart';
import 'friend_code.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePage();
}

class _ProfilePage extends State<ProfilePage> {
  List<Map<String, dynamic>> chatGroups = [];
  String searchText = '';
  bool isLoading = true;

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
        'id': u['id'],
        'name': u['name'],
        'image': u['image'],
        'code': u['code'],
        'manageFriendId': u['pivot']?['id'], // ❗ พยายามดึงจาก pivot
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
  void initState() {
    super.initState();
    fetchFriends();
  }

  void _confirmDeleteFriend(Map<String, dynamic> friend) {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('ลบเพื่อน'),
        content: Text('คุณต้องการลบ ${friend['name']} ใช่หรือไม่?'),
        actions: [
          CupertinoDialogAction(
            child: const Text('ยกเลิก'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('ลบ'),
            onPressed: () {
              Navigator.of(context).pop();
              _deleteFriend(friend);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFriend(Map<String, dynamic> friend) async {
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

    final manageFriendId = friend['id'];
    if (manageFriendId == null) {
      print('ไม่พบ manageFriendId สำหรับเพื่อน ${friend['name']}  id ${friend['id']}');
      return;
    }

     print('ส่ง ${friend['name']}  id ${friend['id']} idเรา id ${userId}');

    final url = Uri.parse('https://privatechat-api.team.orangeworkshop.info/api/manage-friend/delete/$manageFriendId/$userId');

    final response = await http.delete(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
    );

    if (response.statusCode == 200) {
      await fetchFriends();
    } else {
       print('ลบไม่สำเร็จ เกิดข้อผิดพลาด ${response.statusCode}');
      showCupertinoDialog(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('ลบไม่สำเร็จ'),
          content: Text('เกิดข้อผิดพลาด: ${response.statusCode}'),
          actions: [
            CupertinoDialogAction(
              child: const Text('ตกลง'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
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
        leading: const SizedBox.shrink(),


        trailing: Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF1B386A),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(CupertinoIcons.add_circled_solid, size: 20, color: Colors.white),
          SizedBox(width: 8),
          Text('เพิ่มเพื่อนด้วยชื่อ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
      onPressed: () async {
        final existingFriendIds = chatGroups.map<int>((e) => e['id'] as int).toList();
        await Navigator.push(
          context,
          CupertinoPageRoute(
            builder: (_) => AddFriendPage(existingFriendIds: existingFriendIds),
          ),
        );
        fetchFriends(); // รีเฟรชเมื่อกลับมา
      },
    ),

    CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF1B386A),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(CupertinoIcons.add_circled_solid, size: 20, color: Colors.white),
          SizedBox(width: 8),
          Text('เพิ่มเพื่อนด้วยรหัส', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
      onPressed: () {
        Navigator.push(
          context,
          CupertinoPageRoute(builder: (_) => CodePage_Friend()),
        );
      },
    ),
  ],
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
                          child: Text('', style: TextStyle(color: Colors.grey, decoration: TextDecoration.none)),
                        )
                      : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 200), // ✅ เพิ่มพื้นที่ว่างด้านล่าง
                          itemCount: filteredGroups.length,

                          itemBuilder: (context, index) {
                            final group = filteredGroups[index];
                            return CupertinoButton(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              // onPressed: () {
                              //   showCupertinoDialog(
                              //     context: context,
                              //     builder: (context) => CupertinoAlertDialog(
                              //       title: Text(group['name']),
                              //       actions: [
                              //         CupertinoDialogAction(
                              //           child: const Text('ตกลง'),
                              //           onPressed: () => Navigator.of(context).pop(),
                              //         )
                              //       ],
                              //     ),
                              //   );
                              // },
                              onPressed: () async {
                              final prefs = await SharedPreferences.getInstance();
                              final authToken = prefs.getString('token_api') ?? '';
                              final user = await getUserSession();
                              if (user == null) return;

                              final userId = user['id'];
                              final friendId = group['id'];

                              print('👉 ส่งไป API /group-chat/private');
                              print('user_id: $userId');
                              print('friend_id: $friendId');
                              print('token: $authToken');

                              

                              final url = Uri.parse('https://privatechat-api.team.orangeworkshop.info/api/group-chat/private');

                              final headers = {
                                'Content-Type': 'application/json',
                                'Authorization': 'Bearer $authToken',
                              };

                              final body = jsonEncode({
                                'user_id': userId,
                                'friend_id': friendId,
                              });

                              try {
                                final response = await http.post(url, headers: headers, body: body);

                                if (response.statusCode == 200) {
                                  final data = jsonDecode(response.body);
                                  final groupId = data['group_chat_id'].toString();

                                  print('📩 Response: ${response.statusCode} ${response.body}');

                                  Navigator.push(
                                    context,
                                    CupertinoPageRoute(
                                      builder: (context) => ChatPage_Code(
                                        groupName: group['name'],
                                        groupId: groupId,
                                      ),
                                    ),
                                  ).then((value) {
                                    fetchFriends(); // โหลดเพื่อนใหม่หากจำเป็น
                                  });
                                } else {
                                  print('API error: ${response.statusCode} ${response.body}');

                                  showCupertinoDialog(
                                  context: context,
                                  builder: (_) => CupertinoAlertDialog(
                                    title: const Text('เกิดข้อผิดพลาด'),
                                    content: Text('API: ${response.statusCode}\n${response.body}'),
                                    actions: [
                                      CupertinoDialogAction(
                                        child: const Text('ตกลง'),
                                        onPressed: () => Navigator.of(context).pop(),
                                      ),
                                    ],
                                  ),
                                );


                                }
                              } catch (e) {
                                print('API call error: $e');

                                showCupertinoDialog(
                                context: context,
                                builder: (_) => CupertinoAlertDialog(
                                  title: const Text('เกิดข้อผิดพลาด'),
                                  content: Text('API call error: $e'),
                                  actions: [
                                    CupertinoDialogAction(
                                      child: const Text('ตกลง'),
                                      onPressed: () => Navigator.of(context).pop(),
                                    ),
                                  ],
                                ),
                              );


                              }
                            },

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
                                    // child: Text(
                                    //   group['name'][0].toUpperCase(),
                                    //   style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                                    // ),
                                    child: group['image'] != null && group['image'].toString().isNotEmpty
    ? ClipOval(
        child: Image.network(
          group['image'],
          width: 48,
          height: 48,
          fit: BoxFit.cover,
        ),
      )
    : Text(
        group['name'][0].toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        group['name'],
                                        style: const TextStyle(fontSize: 18, color: Colors.black),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'รหัสเพื่อน : ${group['code'] ?? '-'}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  GestureDetector(
                                    onTap: () => _confirmDeleteFriend(group),
                                    child: const Icon(
                                      CupertinoIcons.delete,
                                      color: CupertinoColors.destructiveRed,
                                    ),
                                  ),
                                ],
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
