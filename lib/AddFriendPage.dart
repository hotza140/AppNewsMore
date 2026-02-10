import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AddFriendPage extends StatefulWidget {
  final List<int> existingFriendIds;

  const AddFriendPage({super.key, required this.existingFriendIds});

  @override
  State<AddFriendPage> createState() => _AddFriendPageState();
}

class _AddFriendPageState extends State<AddFriendPage> {
  List<Map<String, dynamic>> searchResults = [];
  bool isLoading = false;
  String searchText = '';

  Future<Map<String, dynamic>?> getUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user_info');
    if (userJson == null) return null;
    return jsonDecode(userJson) as Map<String, dynamic>;
  }

  Future<void> searchFriendsByName(String name) async {
    if (name.isEmpty) {
      setState(() {
        searchResults = [];
      });
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString('token_api') ?? '';
      final userInfo = await getUserSession();
      final myUserId = userInfo?['id'];

      final url = Uri.https(
  'privatechat-api.team.orangeworkshop.info',
  '/api/user/by-name',
  {
    'name': name,       // ส่งค่า name
    'id_group': '',     // ถ้าอยากส่งว่างก็ใส่ string ว่าง
  },
);
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $authToken',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        final List<dynamic> data = jsonResponse['data'] ?? [];

        final filteredData = data.where((u) {
          final id = u['id'];
          return id != myUserId && !widget.existingFriendIds.contains(id);
        }).toList();

        setState(() {
          searchResults = filteredData.map<Map<String, dynamic>>((u) {
            return {
              'id': u['id'],
              'name': u['name'],
              'image': u['image'],
            };
          }).toList();
        });
      } else {
        print('API error: ${response.statusCode}');
        setState(() {
          searchResults = [];
        });
      }
    } catch (e) {
      print('Exception: $e');
      setState(() {
        searchResults = [];
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _showSuccessDialog(String message) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('สำเร็จ'),
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

  Future<void> addFriend(int friendId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token_api');
    final userInfo = await getUserSession();

    print('ส่ง id เรา : ${userInfo?['id']}, id เพื่อน: $friendId');

    if (token == null || userInfo == null) {
      print('User not logged in or no token');
      return;
    }

    final url = Uri.parse('https://privatechat-api.team.orangeworkshop.info/api/manage-friend/add');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'user_id': userInfo['id'],
          'friend_id': friendId,
        }),
      );

      if (response.statusCode == 200) {
        print('เพิ่มเพื่อนสำเร็จ');

        setState(() {
          searchResults.removeWhere((element) => element['id'] == friendId);
        });

        _showSuccessDialog('เพิ่มเพื่อนสำเร็จแล้ว');
      } else {
        final body = json.decode(response.body);
        print('เพิ่มเพื่อนไม่สำเร็จ: ${response.statusCode}, message: ${body['message']}');
      }
    } catch (e) {
      print('เกิดข้อผิดพลาด: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final existingIds = widget.existingFriendIds;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('เพิ่มเพื่อนด้วยชื่อ'),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: CupertinoSearchTextField(
                placeholder: 'พิมพ์ชื่อเพื่อนที่ต้องการเพิ่ม',
                onChanged: (value) {
                  searchText = value;
                  searchFriendsByName(value.trim());
                },
              ),
            ),
            if (isLoading)
              const Center(child: CupertinoActivityIndicator())
            else
              Expanded(
                child: searchResults.isEmpty
                    ? const Center(child: Text(''))
                    : Material(
                        child: ListView.builder(
                          itemCount: searchResults.length,
                          itemBuilder: (context, index) {
                            final friend = searchResults[index];
                            final friendId = friend['id'] as int;
                            final alreadyFriend = existingIds.contains(friendId);

                            return ListTile(
                              leading: friend['image'] != null && friend['image'].toString().isNotEmpty
                                  ? CircleAvatar(backgroundImage: NetworkImage(friend['image']))
                                  : CircleAvatar(child: Text(friend['name'][0].toUpperCase())),
                              title: Text(friend['name']),
                              trailing: CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: alreadyFriend ? null : () => addFriend(friendId),
                                child: Text(
                                  alreadyFriend ? 'เพิ่มแล้ว' : 'เพิ่ม',
                                  style: TextStyle(
                                    color: alreadyFriend ? CupertinoColors.inactiveGray : CupertinoColors.activeBlue,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
