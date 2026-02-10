import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_box.dart';
import 'code.dart';
import 'group_edit.dart';
import 'new_group_1.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  List<Map<String, dynamic>> chatGroups = [];
  String searchNameText = ''; // ✅ NEW: ค้นชื่อแชท
  bool isLoading = false;

  Map<int, int> _unreadCount = {};
  Map<int, bool> _hasUnread = {}; // (ยังไม่ได้ใช้ แต่เก็บไว้ตามของเดิม)

  String? currentUserId;

  String searchText = '';       // ✅ ค้นข้อความ (ต้องมี!)


    // =========================
  // ✅ SEARCH IN MESSAGES (NEW)
  // =========================
  bool _isSearchingMessages = false;

  // groupId -> true/false ว่าห้องนี้มีข้อความตรงกับ search
  final Map<String, bool> _messageMatchRoom = {};

  // debounce timer
  DateTime? _lastSearchAt;

  // =========================
  // ✅ MUTE
  // =========================
  final Map<String, bool> _mutedRooms = {}; // groupId -> muted
  final Map<String, bool> _mutingLoading = {}; // groupId -> loading

  // =========================
  // ✅ PIN (ปักหมุด)
  // =========================
  final Map<String, bool> _pinnedRooms = {}; // groupId -> pinned
  final Map<String, bool> _pinningLoading = {}; // groupId -> loading

  // -------------------------
  // ✅ listen mute per room
  // -------------------------
  void _listenMuteForRoom(String groupId) {
    if (currentUserId == null) return;

    FirebaseFirestore.instance
        .collection('chat_groups')
        .doc(groupId)
        .collection('mute_settings')
        .doc(currentUserId)
        .snapshots()
        .listen((doc) {
      final muted = (doc.data()?['muted'] == true);
      if (!mounted) return;
      setState(() {
        _mutedRooms[groupId] = muted;
      });
    });
  }

  void _initMuteListeners() {
    if (currentUserId == null) return;
    for (final g in chatGroups) {
      final gid = g['id'].toString();
      _listenMuteForRoom(gid);
    }
  }

  Future<void> _toggleMuteRoom(String groupId) async {
    if (currentUserId == null) return;

    final loading = _mutingLoading[groupId] == true;
    if (loading) return;

    final prev = _mutedRooms[groupId] == true;
    final next = !prev;

    setState(() {
      _mutingLoading[groupId] = true;
      _mutedRooms[groupId] = next; // optimistic
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token_api') ?? '';

      final url = Uri.parse(
        'https://privatechat-api.team.orangeworkshop.info/api/chat-notification/mute',
      );

      final res = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'user_id': currentUserId,
          'group_id': groupId,
          'muted': next,
        }),
      );

      if (res.statusCode == 200) {
        await FirebaseFirestore.instance
            .collection('chat_groups')
            .doc(groupId)
            .collection('mute_settings')
            .doc(currentUserId)
            .set(
          {'muted': next, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
      } else {
        setState(() => _mutedRooms[groupId] = prev); // rollback
        debugPrint('❌ mute api error: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      setState(() => _mutedRooms[groupId] = prev); // rollback
      debugPrint('❌ mute api exception: $e');
    } finally {
      if (!mounted) return;
      setState(() => _mutingLoading[groupId] = false);
    }
  }

  // -------------------------
  // ✅ listen pin per room
  // -------------------------
  void _listenPinForRoom(String groupId) {
    if (currentUserId == null) return;

    // 📌 โครงสร้าง Firestore:
    // chat_groups/{groupId}/pin_settings/{userId}  => { pinned: true/false }
    FirebaseFirestore.instance
        .collection('chat_groups')
        .doc(groupId)
        .collection('pin_settings')
        .doc(currentUserId)
        .snapshots()
        .listen((doc) {
      final pinned = (doc.data()?['pinned'] == true);
      if (!mounted) return;
      setState(() {
        _pinnedRooms[groupId] = pinned;
      });
    });
  }

  void _initPinListeners() {
    if (currentUserId == null) return;
    for (final g in chatGroups) {
      final gid = g['id'].toString();
      _listenPinForRoom(gid);
    }
  }

  Future<void> _togglePinRoom(String groupId) async {
    if (currentUserId == null) return;

    final loading = _pinningLoading[groupId] == true;
    if (loading) return;

    final prev = _pinnedRooms[groupId] == true;
    final next = !prev;

    setState(() {
      _pinningLoading[groupId] = true;
      _pinnedRooms[groupId] = next; // optimistic
    });

    try {
      // ✅ ถ้าคุณมี API ปักหมุด ให้ใส่ตรงนี้ได้ (เหมือน mute)
      // ตอนนี้จะเซฟที่ Firestore อย่างเดียว เพื่อให้ใช้งานได้ทันที
      await FirebaseFirestore.instance
          .collection('chat_groups')
          .doc(groupId)
          .collection('pin_settings')
          .doc(currentUserId)
          .set(
        {'pinned': next, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (e) {
      setState(() => _pinnedRooms[groupId] = prev); // rollback
      debugPrint('❌ pin exception: $e');
    } finally {
      if (!mounted) return;
      setState(() => _pinningLoading[groupId] = false);
    }
  }

  @override
  void initState() {
    super.initState();
    fetchChatGroups().then((_) {
      _initMuteListeners(); // ✅ เริ่ม listen mute ทุกห้อง
      _initPinListeners(); // ✅ เริ่ม listen pin ทุกห้อง
      initChatListener();
    });
  }

  Future<Map<String, dynamic>?> getUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user_info');
    if (userJson == null) return null;
    return jsonDecode(userJson) as Map<String, dynamic>;
  }

  Future<void> fetchChatGroups() async {
    setState(() {
      isLoading = true;
    });

    final user = await getUserSession();
    if (user == null) {
      setState(() {
        isLoading = false;
      });
      return;
    }

    currentUserId = user['id'].toString();
    final userId = user['id'];

    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('token_api') ?? '';
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $authToken',
    };

    try {
      final url = Uri.parse(
        'https://privatechat-api.team.orangeworkshop.info/api/user/group-chat-by-id/$userId',
      );
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> groupChatData = jsonDecode(response.body)['data'];
        chatGroups = groupChatData
            .map<Map<String, dynamic>>(
              (group) => {
                'id': group['id'],
                'name': group['name'],
                'code': group['code'],
                'hour': group['hour'],
                'image': group['image'],
                'created_by': group['created_by'].toString(),
              },
            )
            .toList();

        setState(() {
          isLoading = false;
        });
      } else {
        print('GroupChat API: ${response.statusCode} ${response.body}');
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      print('Fetch error: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  void initChatListener() async {
    final user = await getUserSession();
    if (user == null) return;
    final userId = user['id'].toString();

    for (var group in chatGroups) {
      final groupId = group['id'].toString();
      final groupIdInt = int.tryParse(groupId) ?? -1;

      FirebaseFirestore.instance
          .collection('chat_groups')
          .doc(groupId)
          .collection('messages')
          .snapshots()
          .listen((snapshot) async {
        if (snapshot.docs.isEmpty) return;

        int unreadCount = 0;

        for (var doc in snapshot.docs) {
          final message = doc.data();
          final readBy = (message['readBy'] as List<dynamic>?) ?? [];
          final senderId = message['senderId']?.toString() ?? '';

          if (senderId != userId && !readBy.contains(userId)) {
            unreadCount++;
          }
        }

        if (!mounted) return;
        setState(() {
          _unreadCount[groupIdInt] = unreadCount;
        });
      });
    }
  }

  /// ฟังก์ชันใหม่ ใช้ดึงชื่อเดียวและ url ของภาพ (ใช้ | แทน /)
  Map<String, String?> extractNameAndImage(String originalName, String userId) {
    final parts = originalName.split('|'); // เปลี่ยนจาก / เป็น |
    for (var part in parts) {
      final match =
          RegExp(r'^([^\(]+)\((\d+)\)\[(.*?)\]$').firstMatch(part.trim());
      if (match != null) {
        final name = match.group(1)!.trim();
        final id = match.group(2)!;
        final url = match.group(3)!;
        if (id != userId) {
          return {'name': name, 'url': url.isNotEmpty ? url : null};
        }
      }
    }
    // fallback
    final fallbackName =
        originalName.replaceAll(RegExp(r'\[.*?\]'), '').trim();
    return {'name': fallbackName, 'url': null};
  }

  bool canShowManageButton(String name, String? createdBy) {
    // (คงของเดิม) : แสดงปุ่ม gear เฉพาะชื่อที่ไม่ใช่ format chat ส่วนตัว
    return !(name.contains('/') || name.contains('(') || name.contains(')'));
  }


   // =========================
  // ✅ SEARCH messages in rooms (NEW)
  // =========================
  Future<void> _searchInRoomMessages(String keyword) async {
    if (currentUserId == null) return;

  final q = keyword.trim().toLowerCase();

if (q.isEmpty) {
  if (!mounted) return;
  setState(() {
    _isSearchingMessages = false;
    _messageMatchRoom.clear();
  });
  return;
}

if (q.length < 2) {
  if (!mounted) return;
  setState(() {
    _isSearchingMessages = false;
    _messageMatchRoom.clear();
  });
  return;
}

    // debounce แบบง่าย: ถ้าพิมพ์ถี่เกิน 350ms ให้รอรอบถัดไป
    final now = DateTime.now();
    _lastSearchAt = now;
    await Future.delayed(const Duration(milliseconds: 350));
    // ถ้าเวลาถูกอัปเดต แปลว่ามีการพิมพ์ใหม่ -> ยกเลิกการค้นรอบนี้
    if (_lastSearchAt != now) return;

    if (!mounted) return;
    setState(() {
      _isSearchingMessages = true;
      _messageMatchRoom.clear();
    });

    // ✅ ป้องกันหน่วง: จำกัดจำนวนห้องที่สแกน
    // ปรับเลขได้: 20-40 กำลังดี
    const maxRoomsToScan = 30;

    // ✅ จำกัดจำนวนข้อความต่อห้อง
    // ปรับได้: 50-200 ตามที่ต้องการ
    const perRoomLimit = 120;

    final rooms = chatGroups.take(maxRoomsToScan).toList();

    try {
      for (final g in rooms) {
        final groupId = g['id'].toString();

      final snap = await FirebaseFirestore.instance
    .collection('chat_groups')
    .doc(groupId)
    .collection('messages')
    .orderBy('timestamp', descending: true) // ✅ ใช้ timestamp ตามของจริง
    .limit(perRoomLimit)
    .get();

bool found = false;

for (final d in snap.docs) {
  final data = d.data();

  // ✅ ของจริงคือ text
  final text = (data['text'] ?? '').toString();

  if (text.toLowerCase().contains(q)) {
    found = true;
    break;
  }
}

        if (!mounted) return;
        setState(() {
          _messageMatchRoom[groupId] = found;
        });
      }
    } catch (e) {
      debugPrint('❌ search messages error: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _isSearchingMessages = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1) filter ตาม search
   final qMsg = searchText.trim().toLowerCase();       // ค้นข้อความ
final qName = searchNameText.trim().toLowerCase();  // ค้นชื่อห้อง

final filteredGroups = chatGroups.where((group) {
  final groupId = group['id'].toString();
  final name = (group['name'] ?? '').toString().toLowerCase();

  // ✅ match ชื่อห้อง
  final nameMatch = qName.isEmpty ? true : name.contains(qName);

  // ✅ match ข้อความ (ใช้ผลจาก _messageMatchRoom)
  final msgMatch = qMsg.isEmpty ? true : (_messageMatchRoom[groupId] == true);

  // ถ้าใส่ทั้ง 2 ช่อง -> ต้องตรงทั้งคู่
  return nameMatch && msgMatch;
}).toList();


    // 2) ✅ sort ให้ปักหมุดขึ้นก่อน
    filteredGroups.sort((a, b) {
      final aId = a['id'].toString();
      final bId = b['id'].toString();
      final aPinned = _pinnedRooms[aId] == true ? 1 : 0;
      final bPinned = _pinnedRooms[bId] == true ? 1 : 0;

      // pinned desc
      final pinnedCmp = bPinned.compareTo(aPinned);
      if (pinnedCmp != 0) return pinnedCmp;

      // fallback: เรียงชื่อ
      final an = (a['name'] ?? '').toString();
      final bn = (b['name'] ?? '').toString();
      return an.toLowerCase().compareTo(bn.toLowerCase());
    });

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        backgroundColor: const Color(0xFF1B386A),
        leading: const SizedBox.shrink(),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: const Color(0xFF1B386A),
              child: Row(
                children: const [
                  Icon(
                    CupertinoIcons.add_circled_solid,
                    size: 20,
                    color: Colors.white,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'เพิ่มกลุ่มโดยรหัส',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  CupertinoPageRoute(builder: (_) => CodePage()),
                ).then((value) {
                  fetchChatGroups();
                });
              },
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: const Color(0xFF1B386A),
              child: Row(
                children: const [
                  Icon(
                    CupertinoIcons.group_solid,
                    size: 20,
                    color: Colors.white,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'สร้างกลุ่มใหม่',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  CupertinoPageRoute(builder: (_) => NewGroup()),
                ).then((value) {
                  fetchChatGroups();
                });
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
  child: Column(
    children: [
      // ✅ ช่องค้นชื่อแชท
      CupertinoSearchTextField(
        placeholder: 'ค้นหาชื่อแชท',
        onChanged: (value) {
          setState(() {
            searchNameText = value;
          });
        },
      ),
      const SizedBox(height: 10),

      // ✅ ช่องค้นข้อความ
      CupertinoSearchTextField(
        placeholder: 'ค้นหาข้อความ',
        onChanged: (value) {
          setState(() {
            searchText = value; // ใช้ตัวเดิมเป็น "ค้นข้อความ"
          });

          // ค้นในข้อความ (เหมือนเดิม)
          _searchInRoomMessages(value);
        },
      ),
    ],
  ),
),

            if (_isSearchingMessages)
  const Padding(
    padding: EdgeInsets.only(bottom: 6),
    child: CupertinoActivityIndicator(),
  ),

            Expanded(
              child: isLoading
                  ? const Center(child: CupertinoActivityIndicator())
                  : filteredGroups.isEmpty
                      ? const Center(
                          child: Text(
                            '',
                            style: TextStyle(
                              color: Colors.grey,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: fetchChatGroups,
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 200),
                            itemCount: filteredGroups.length,
                            itemBuilder: (context, index) {
                              final group = filteredGroups[index];

                              final groupId = group['id'].toString();
                              final groupIdInt =
                                  int.tryParse(group['id'].toString()) ?? -1;

                              final unreadCount = _unreadCount[groupIdInt] ?? 0;

                              // mute state
                              final isMuted = _mutedRooms[groupId] == true;
                              final isMuting = _mutingLoading[groupId] == true;

                              // pin state
                              final isPinned = _pinnedRooms[groupId] == true;
                              final isPinning =
                                  _pinningLoading[groupId] == true;

                              // ชื่อ/รูป
                              final nameAndImage = extractNameAndImage(
                                group['name'].toString(),
                                currentUserId ?? '',
                              );
                              final displayName = nameAndImage['name']!;

                              final imageUrl = (group['image'] != null &&
                                      group['image'].toString().isNotEmpty)
                                  ? group['image'].toString()
                                  : nameAndImage['url'];

                              final isGroupChat = group['code'] != null &&
                                  group['code'].toString().isNotEmpty;
                              final groupLabel = isGroupChat ? " 🧑‍🤝‍🧑" : "";
                              final displayNameWithLabel =
                                  "$displayName$groupLabel";

                              return CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                onPressed: () async {
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  final authToken =
                                      prefs.getString('token_api') ?? '';

                                  final headers = {
                                    'Content-Type': 'application/json',
                                    'Authorization': 'Bearer $authToken',
                                  };

                                  final userId = currentUserId ?? '';

                                  final touchUrl = Uri.parse(
                                    'https://privatechat-api.team.orangeworkshop.info/api/group-chat-user/touch/$groupId/$userId',
                                  );
                                  final cleanUrl = Uri.parse(
                                    'https://privatechat-api.team.orangeworkshop.info/api/chatting-room/clean-expired/$groupId',
                                  );

                                  try {
                                    await http.get(touchUrl, headers: headers);
                                    await http.get(cleanUrl, headers: headers);
                                  } catch (e) {
                                    print('Touch/Clean API error: $e');
                                  }

                                  Navigator.push(
                                    context,
                                    CupertinoPageRoute(
                                      builder: (context) => ChatPage_Code(
                                        groupName: displayName,
                                        groupId: groupId,
                                      ),
                                    ),
                                  ).then((value) {
                                    fetchChatGroups();
                                  });
                                },
                                child: Row(
                                  children: [
                                    Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(24),
                                          child: imageUrl != null
                                              ? Image.network(
                                                  imageUrl,
                                                  width: 48,
                                                  height: 48,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error,
                                                      stackTrace) {
                                                    return Container(
                                                      width: 48,
                                                      height: 48,
                                                      decoration: BoxDecoration(
                                                        color: Colors
                                                            .blue.shade300,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(24),
                                                      ),
                                                      alignment:
                                                          Alignment.center,
                                                      child: Text(
                                                        displayName[0]
                                                            .toUpperCase(),
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 20,
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                )
                                              : Container(
                                                  width: 48,
                                                  height: 48,
                                                  decoration: BoxDecoration(
                                                    color:
                                                        Colors.blue.shade300,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            24),
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    displayName[0]
                                                        .toUpperCase(),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 20,
                                                    ),
                                                  ),
                                                ),
                                        ),

                                        // ✅ unread badge
                                        if (unreadCount > 0)
                                          Positioned(
                                            right: 0,
                                            top: 0,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.all(4),
                                              decoration: const BoxDecoration(
                                                color: CupertinoColors
                                                    .systemRed,
                                                shape: BoxShape.circle,
                                              ),
                                              constraints:
                                                  const BoxConstraints(
                                                minWidth: 20,
                                                minHeight: 20,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  unreadCount.toString(),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(width: 12),

                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  displayNameWithLabel,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                              ),
                                           
                                            ],
                                          ),
                                          const SizedBox(height: 4),

                                          if ((group['code'] ?? '')
                                              .toString()
                                              .isNotEmpty)
                                            Text(
                                              'รหัสกลุ่ม : ${group['code']}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade500,
                                              ),
                                            ),
                                          if ((group['code'] ?? '')
                                              .toString()
                                              .isNotEmpty)
                                            const SizedBox(height: 4),

                                          if (group['hour'] != null &&
                                              group['hour'] != 0)
                                            Text(
                                              'ลบข้อความเก่าที่เกิน : ${group['hour']} วัน',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade500,
                                              ),
                                            ),
                                          if (group['hour'] != null &&
                                              group['hour'] != 0)
                                            const SizedBox(height: 4),
                                        ],
                                      ),
                                    ),

                                    // =========================
                                    // ✅ ปุ่มปักหมุด (อยู่ข้างๆปุ่มแจ้งเตือน)
                                    // =========================
                                    CupertinoButton(
                                      padding: const EdgeInsets.all(6),
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(20),
                                      onPressed: () => _togglePinRoom(groupId),
                                      child: isPinning
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CupertinoActivityIndicator(
                                                  radius: 9),
                                            )
                                          : Icon(
                                              isPinned
                                                  ? CupertinoIcons.pin_fill
                                                  : CupertinoIcons.pin,
                                              size: 20,
                                              color: isPinned
                                                  ? CupertinoColors
                                                      .systemOrange
                                                  : CupertinoColors
                                                      .inactiveGray,
                                            ),
                                    ),
                                    const SizedBox(width: 6),

                                    // =========================
                                    // ✅ ปุ่มเปิด/ปิดแจ้งเตือน (mute)
                                    // =========================
                                    CupertinoButton(
                                      padding: const EdgeInsets.all(6),
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(20),
                                      onPressed: () =>
                                          _toggleMuteRoom(groupId),
                                      child: isMuting
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CupertinoActivityIndicator(
                                                  radius: 9),
                                            )
                                          : Icon(
                                              isMuted
                                                  ? CupertinoIcons
                                                      .bell_slash_fill
                                                  : CupertinoIcons.bell_fill,
                                              size: 20,
                                              color: isMuted
                                                  ? CupertinoColors.systemRed
                                                  : CupertinoColors.activeBlue,
                                            ),
                                    ),
                                    const SizedBox(width: 6),

                                    // =========================
                                    // ✅ ปุ่มจัดการกลุ่ม
                                    // =========================
                                    if (canShowManageButton(
                                      group['name'],
                                      group['created_by']?.toString(),
                                    ))
                                      CupertinoButton(
                                        padding: const EdgeInsets.all(6),
                                        color: Colors.grey.shade200,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        child: const Icon(
                                          CupertinoIcons.gear,
                                          size: 20,
                                          color: Colors.black87,
                                        ),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            CupertinoPageRoute(
                                              builder: (_) => edit_NewGroup(
                                                groupId:
                                                    group['id'].toString(),
                                                createdBy: group['created_by']
                                                    ?.toString(),
                                                currentUserId: currentUserId,
                                              ),
                                            ),
                                          ).then((_) {
                                            fetchChatGroups();
                                          });
                                        },
                                      ),
                                  ],
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
