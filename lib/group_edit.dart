import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'edit_group_page.dart'; // นี่คือหน้าแก้รายละเอียดกลุ่ม

class edit_NewGroup extends StatefulWidget {
  final String groupId; // 👈 รับค่า groupId

  // ✅ รับมาจากหน้า ChatPage เพื่อเช็คว่าเป็นเจ้าของกลุ่มไหม
  final String? currentUserId;
  final String? createdBy;

  const edit_NewGroup({
    super.key,
    required this.groupId,
    this.currentUserId,
    this.createdBy,
  });

  @override
  State<edit_NewGroup> createState() => _edit_NewGroupState();
}

class _edit_NewGroupState extends State<edit_NewGroup> {
  List<Map<String, dynamic>> groupMembers = [];
  List<Map<String, dynamic>> searchResults = [];
  String searchText = '';
  bool isLoading = false;

  int? myUserId; // 👈 เก็บ userId ของตัวเอง

  // ✅ NEW: เก็บ id เพื่อนของเรา เพื่อเช็คว่าเพิ่มเพื่อนไปแล้วหรือยัง
  Set<int> myFriendIds = {};

  // ✅ NEW: ทุกคนสามารถเพิ่มสมาชิกเข้ากลุ่มได้
bool get canAddMembers => true;

  // ✅ เช็คว่าเป็นเจ้าของกลุ่มไหม (Owner เท่านั้นที่เห็นฟังก์ชันจัดการกลุ่มทั้งหมด)
  bool get isOwner {
    final me = (widget.currentUserId ?? '').trim();
    final owner = (widget.createdBy ?? '').trim();
    return me.isNotEmpty && owner.isNotEmpty && me == owner;
  }

  @override
  void initState() {
    super.initState();
    loadMyUserId(); // โหลด user id ก่อน
    fetchGroupMembers();
    _loadMyFriends(); // ✅ NEW
  }

  Future<Map<String, dynamic>?> getUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user_info');
    if (userJson == null) return null;
    return jsonDecode(userJson) as Map<String, dynamic>;
  }

  Future<void> loadMyUserId() async {
    final userInfo = await getUserSession();
    setState(() {
      myUserId = userInfo?['id'];
    });
  }



  void confirmLeaveGroup() {
  showCupertinoDialog(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: const Text("ออกจากกลุ่ม"),
      content: const Text("คุณต้องการออกจากกลุ่มนี้หรือไม่?"),
      actions: [
        CupertinoDialogAction(
          child: const Text("ยกเลิก"),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CupertinoDialogAction(
          isDestructiveAction: true,
          child: const Text("ออกจากกลุ่ม"),
          onPressed: () {
            Navigator.of(context).pop();

            if (myUserId != null) {
              removeUserFromGroup(myUserId.toString());
            }
          },
        ),
      ],
    ),
  );
}

  // ✅ NEW: โหลดรายชื่อเพื่อนของเรา (ใช้ endpoint เดียวกับที่คุณใช้ที่อื่น)
  Future<void> _loadMyFriends() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString('token_api') ?? '';
      final userInfo = await getUserSession();
      final uid = userInfo?['id'];
      if (uid == null) return;

      final url = Uri.parse(
        'https://privatechat-api.team.orangeworkshop.info/api/manage-friend/get-by-id/$uid',
      );

      final res = await http.get(url, headers: {
        'Authorization': 'Bearer $authToken',
      });

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> friends = data['data'] ?? [];

        setState(() {
          myFriendIds = friends
              .map((f) => int.tryParse(f['id'].toString()) ?? -1)
              .where((id) => id != -1)
              .toSet();
        });
      } else {
        // ไม่ทำให้ระบบเดิมพัง แค่ log
        print('❌ Load friends error: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      print('❌ Load friends exception: $e');
    }
  }

  Future<void> fetchGroupMembers() async {
    setState(() => isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('token_api') ?? '';

    final url = Uri.parse(
        'https://privatechat-api.team.orangeworkshop.info/api/group-chat/${widget.groupId}/members');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $authToken',
    };

    final response = await http.get(url, headers: headers);

    if (response.statusCode == 200) {
      final Map<String, dynamic> jsonResponse = jsonDecode(response.body);
      final List<dynamic> members = jsonResponse['data']['members'];

      setState(() {
        groupMembers = members
            .map<Map<String, dynamic>>((u) => {
                  'id': u['id'],
                  'name': u['name'],
                  'image': u['image'],
                })
            .toList();
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
      print('Group members API error: ${response.body}');
    }
  }

  // ✅ ค้นหาเพื่อ "เพิ่มเข้ากลุ่ม" (แสดงเฉพาะ owner)
  Future<void> searchFriendsByName(String name) async {
    if (name.isEmpty) {
      setState(() => searchResults = []);
      return;
    }

    setState(() => isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString('token_api') ?? '';
      final userInfo = await getUserSession();
      final myUserId = userInfo?['id'];

      final url = Uri.https(
        'privatechat-api.team.orangeworkshop.info',
        '/api/user/by-name',
        {
          'name': name,
          'id_group': widget.groupId, // ส่ง groupId
        },
      );
      final response = await http.get(url, headers: {
        'Authorization': 'Bearer $authToken',
      });

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        final List<dynamic> data = jsonResponse['data'] ?? [];

        final filteredData = data.where((u) {
          final id = u['id'];
          return id != myUserId; // ไม่โชว์ตัวเอง
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
        setState(() => searchResults = []);
        print('Search API error: ${response.body}');
      }
    } catch (e) {
      print('Exception: $e');
      setState(() => searchResults = []);
    } finally {
      setState(() => isLoading = false);
    }
  }

  void confirmDeleteGroup() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text("ยืนยันการลบกลุ่ม"),
        content: const Text("คุณต้องการลบกลุ่มนี้หรือไม่?"),
        actions: [
          CupertinoDialogAction(
            child: const Text("ยกเลิก"),
            onPressed: () => Navigator.of(context).pop(),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text("ยืนยัน"),
            onPressed: () {
              Navigator.of(context).pop();
              deleteGroup();
            },
          ),
        ],
      ),
    );
  }

  Future<void> deleteGroup() async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('token_api') ?? '';

    final url = Uri.parse(
        'https://privatechat-api.team.orangeworkshop.info/api/group-chat/${widget.groupId}');

    try {
      final response = await http.delete(url, headers: {
        'Authorization': 'Bearer $authToken',
        'Content-Type': 'application/json',
      });

      final jsonResponse = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (context.mounted) {
          Navigator.of(context).pop(); // กลับหน้าเดิม
        }
      } else {
        final message = jsonResponse['message'] ?? 'ไม่สามารถลบกลุ่มได้';
        if (context.mounted) {
          showCupertinoDialog(
            context: context,
            builder: (context) => CupertinoAlertDialog(
              title: const Text("ล้มเหลว"),
              content: Text(message),
              actions: [
                CupertinoDialogAction(
                  child: const Text("ตกลง"),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text("ล้มเหลว"),
            content: Text("เกิดข้อผิดพลาด: $e"),
            actions: [
              CupertinoDialogAction(
                child: const Text("ตกลง"),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      }
    }
  }

  void confirmRemoveUser(Map<String, dynamic> user) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text("ยืนยันการลบ"),
        content: Text("คุณต้องการลบ ${user['name']} ออกจากกลุ่มหรือไม่?"),
        actions: [
          CupertinoDialogAction(
            child: const Text("ยกเลิก"),
            onPressed: () => Navigator.of(context).pop(),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text("ยืนยัน"),
            onPressed: () {
              Navigator.of(context).pop();
              removeUserFromGroup(user['id'].toString());
            },
          ),
        ],
      ),
    );
  }

  Future<void> removeUserFromGroup(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('token_api') ?? '';

    final url = Uri.parse(
        'https://privatechat-api.team.orangeworkshop.info/api/group-chat/${widget.groupId}/members/$userId');

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $authToken',
    };

    final response = await http.delete(url, headers: headers);
    final Map<String, dynamic> jsonResponse = jsonDecode(response.body);
    
    if (response.statusCode == 200) {
    // ✅ ถ้าเป็นการ "ออกจากกลุ่มเอง" ให้เด้งกลับหน้าก่อนทันที
    final isLeavingSelf = myUserId != null && userId == myUserId.toString();
    if (isLeavingSelf) {
      if (!mounted) return;
      Navigator.of(context).pop(true); // กลับไปหน้า ChatPage
      return;
    }

    // ✅ กรณี owner ลบคนอื่น: ทำเหมือนเดิม
    setState(() {
      groupMembers.removeWhere((m) => m['id'].toString() == userId);
    });
    } else {
      final errorMessage = jsonResponse['message'] ?? 'ไม่สามารถลบได้';
      if (context.mounted) {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text("ล้มเหลว"),
            content: Text(errorMessage),
            actions: [
              CupertinoDialogAction(
                child: const Text("ตกลง"),
                onPressed: () => Navigator.of(context).pop(),
              )
            ],
          ),
        );
      }
    }
  }

  Future<void> addUserToGroup(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('token_api') ?? '';

    final userToAdd = searchResults.firstWhere(
      (u) => u['id'].toString() == userId,
      orElse: () => {},
    );

    if (userToAdd.isEmpty) return;

    final url = Uri.parse(
        'https://privatechat-api.team.orangeworkshop.info/api/group-chat/${widget.groupId}/members/$userId');

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $authToken',
    };

    try {
      final response = await http.post(url, headers: headers);
      final Map<String, dynamic> jsonResponse = jsonDecode(response.body);

      if (response.statusCode == 200) {
        setState(() {
          groupMembers.add(userToAdd);
          searchResults.removeWhere((u) => u['id'].toString() == userId);
        });
      } else {
        final message = jsonResponse['message'] ?? 'ไม่สามารถเพิ่มได้';
        if (context.mounted) {
          showCupertinoDialog(
            context: context,
            builder: (context) => CupertinoAlertDialog(
              title: const Text("ล้มเหลว"),
              content: Text(message),
              actions: [
                CupertinoDialogAction(
                  child: const Text("ตกลง"),
                  onPressed: () => Navigator.of(context).pop(),
                )
              ],
            ),
          );
        }
      }
    } catch (e) {
      print('Exception: $e');
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

  // ✅ เพิ่มเพื่อนจากสมาชิกในกลุ่ม (สมาชิก/เจ้าของทำได้ทั้งคู่)
  Future<void> addFriend(int friendId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token_api');
    final userInfo = await getUserSession();

    if (token == null || userInfo == null) return;

    final url = Uri.parse(
      'https://privatechat-api.team.orangeworkshop.info/api/manage-friend/add',
    );

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
        setState(() {
          myFriendIds.add(friendId);
        });
        _showSuccessDialog('เพิ่มเพื่อนสำเร็จแล้ว');
      } else {
        final body = json.decode(response.body);
        final msg = body['message'] ?? 'เพิ่มเพื่อนไม่สำเร็จ';
        if (context.mounted) {
          showCupertinoDialog(
            context: context,
            builder: (context) => CupertinoAlertDialog(
              title: const Text("ล้มเหลว"),
              content: Text(msg),
              actions: [
                CupertinoDialogAction(
                  child: const Text("ตกลง"),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      print('เกิดข้อผิดพลาด: $e');
    }
  }

  Widget _buildUserTile(Map<String, dynamic>? user, {bool isMember = false}) {
    if (user == null) return const SizedBox();

    final isSelf = myUserId != null && user['id'] == myUserId;
    final name = user['name'] ?? 'ไม่มีชื่อ';
    final image = user['image'];

    final int uid = int.tryParse(user['id'].toString()) ?? -1;
    final bool alreadyFriend = myFriendIds.contains(uid);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: isMember ? CupertinoColors.systemGrey6 : CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isMember
              ? CupertinoColors.systemGrey4
              : CupertinoColors.systemGrey3,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.blue.shade300,
            backgroundImage: (image != null && image.toString().isNotEmpty)
                ? NetworkImage(image)
                : null,
            child: (image == null || image.toString().isEmpty)
                ? Text(
                    name[0].toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        decoration: TextDecoration.none),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name + (isSelf ? " (คุณ)" : ""),
              style: const TextStyle(
                fontSize: 16,
                decoration: TextDecoration.none,
                color: Colors.black,
              ),
            ),
          ),

          // ✅ สมาชิก/เจ้าของ เห็นปุ่มเพิ่มเพื่อนได้เหมือนกัน (เฉพาะรายการสมาชิก + ไม่ใช่ตัวเอง)
          if (isMember && !isSelf) ...[
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              color: CupertinoColors.activeBlue,
              onPressed: alreadyFriend
                  ? null
                  : () {
                      addFriend(uid);
                    },
              child: Text(
                alreadyFriend ? "เพิ่มแล้ว" : "เพิ่มเพื่อน",
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
          ],

// ✅ เพิ่ม: ทุกคนเห็น / ลบ: เห็นเฉพาะ Owner
if (!isMember || (isMember && isOwner && !isSelf))
  CupertinoButton(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    color: isMember
        ? CupertinoColors.destructiveRed
        : CupertinoColors.activeGreen,
    child: Text(isMember ? "ลบ" : "เพิ่ม",
        style: const TextStyle(color: Colors.white)),
    onPressed: () {
      if (isMember) {
        confirmRemoveUser(user); // owner เท่านั้นถึงจะเห็นปุ่มนี้
      } else {
        addUserToGroup(user['id'].toString()); // ทุกคนเพิ่มได้
      }
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
        middle: Text(
          isOwner ? 'จัดการกลุ่ม' : 'สมาชิกกลุ่ม',
          style: const TextStyle(color: CupertinoColors.white),
        ),
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(CupertinoIcons.back, color: Colors.white),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [

            // ✅ แถบสถานะ: เจ้าของ/สมาชิก (วางก่อนช่องค้นหา)
Padding(
  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
  child: Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: isOwner
          ? CupertinoColors.activeBlue.withOpacity(0.12)
          : CupertinoColors.systemGrey5,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: isOwner
            ? CupertinoColors.activeBlue.withOpacity(0.35)
            : CupertinoColors.systemGrey3,
      ),
    ),
    child: Row(
      children: [
        Icon(
          isOwner ? CupertinoIcons.star_fill : CupertinoIcons.person_2_fill,
          size: 18,
          color: isOwner ? CupertinoColors.activeBlue : CupertinoColors.systemGrey,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            isOwner ? 'สถานะของคุณ: หัวหน้ากลุ่ม' : 'สถานะของคุณ: สมาชิกกลุ่ม',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isOwner ? CupertinoColors.activeBlue : CupertinoColors.black,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    ),
  ),
),

          // ✅ Search + เพิ่มคนเข้ากลุ่ม (ทุกคน)
if (canAddMembers)
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: CupertinoSearchTextField(
                  placeholder: 'ค้นหาเพื่อเพิ่มคนเข้ากลุ่ม',
                  onChanged: (value) {
                    searchText = value;
                    searchFriendsByName(value.trim());
                  },
                ),
              ),

            Expanded(
              child: isLoading
                  ? const Center(child: CupertinoActivityIndicator())
                  : (canAddMembers && searchText.isNotEmpty)
                      ? Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              child: CupertinoButton.filled(
                                child: const Text("จัดการกลุ่ม"),
                                onPressed: () {
                                  setState(() {
                                    searchText = '';
                                    searchResults.clear();
                                  });
                                },
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                itemCount: searchResults.length,
                                itemBuilder: (context, index) {
                                  final user = searchResults[index];
                                  final alreadyInGroup = groupMembers
                                      .any((m) => m['id'] == user['id']);
                                  return _buildUserTile(user,
                                      isMember: alreadyInGroup);
                                },
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            // ✅ ทุกคนเห็นรายชื่อสมาชิก + เพิ่มเพื่อนได้
                            Expanded(
                              child: ListView.builder(
                                itemCount: groupMembers.length,
                                itemBuilder: (context, index) {
                                  final member = groupMembers[index];
                                  return _buildUserTile(member, isMember: true);
                                },
                              ),
                            ),

                            // ✅ Owner เท่านั้น: แก้ไขรายละเอียดกลุ่ม + ลบกลุ่ม
                            if (isOwner)
                              Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          CupertinoPageRoute(
                                            builder: (_) => EditGroupPage(
                                              groupId: widget.groupId,
                                            ),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 16),
                                        decoration: BoxDecoration(
                                          color: CupertinoColors.activeBlue,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        alignment: Alignment.center,
                                        child: const Text(
                                          "แก้ไขรายละเอียดกลุ่ม",
                                          style: TextStyle(
                                            color: CupertinoColors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    GestureDetector(
                                      onTap: () => confirmDeleteGroup(),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 16),
                                        decoration: BoxDecoration(
                                          color: CupertinoColors.destructiveRed,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        alignment: Alignment.center,
                                        child: const Text(
                                          "ลบกลุ่ม",
                                          style: TextStyle(
                                            color: CupertinoColors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),


                              // ✅ สมาชิก (ไม่ใช่ Owner): ออกจากกลุ่มเองได้
                              if (!isOwner)
                                Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: GestureDetector(
                                    onTap: () => confirmLeaveGroup(),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      decoration: BoxDecoration(
                                        color: CupertinoColors.destructiveRed,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      alignment: Alignment.center,
                                      child: const Text(
                                        "ออกจากกลุ่ม",
                                        style: TextStyle(
                                          color: CupertinoColors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
