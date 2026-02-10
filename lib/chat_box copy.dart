import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
// ignore: unused_import
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// ignore: unused_import
import 'package:fluttertoast/fluttertoast.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:private_chat/main.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';

class ChatPage_Code extends StatefulWidget {
  final String groupId;
  final String groupName;

  const ChatPage_Code({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<ChatPage_Code> createState() => _ChatPage_CodeState();
}

class _ChatPage_CodeState extends State<ChatPage_Code> {

  // ====== SEARCH MESSAGE STATE ======
bool _isSearchMode = false;
final TextEditingController _searchController = TextEditingController();
String _searchQuery = '';

// ====== PINNED MESSAGE STATE ======
Set<String> _pinnedMessageIds = {};
StreamSubscription<QuerySnapshot>? _pinnedSub;
DocumentSnapshot? _lastDoc;

final ItemScrollController _itemScrollController = ItemScrollController();
final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();

List<String> _currentMessageOrder = []; // เก็บลำดับ id ตามที่แสดงจริง (หลัง filter/sort)

  // เริ่ม
  bool _isSelectingMessages = false;
Set<String> _selectedMessageIds = {}; 

  
  // ignore: unused_field
  final ScrollController _scrollController = ScrollController();

  // ignore: unused_field
  List<DocumentSnapshot> _messages = [];
  // ignore: unused_field
  bool _isLoadingMore = false;
  // ignore: unused_field
  bool _hasMore = true;
  // ignore: unused_field
  final int _messagesLimit = 600;


  final TextEditingController _textController = TextEditingController();
  // ignore: unused_field
  final ImagePicker _picker = ImagePicker();

  Map<int, bool> _hasUnread = {}; // ✅ ประกาศตัวแปรเก็บสถานะอ่านแล้ว
  // เพิ่มตัวแปรสำหรับเก็บ status ของข้อความที่เพื่อนอ่านแล้ว (สมมุติ)
// ignore: unused_field
Map<String, bool> _readByFriend = {}; // key = messageId


// เพิ่มตัวแปรเก็บข้อความล่าสุด
String? _lastMessageId;
// ignore: unused_field
String? _lastSenderId;

  final List<XFile> _selectedImages = [];
  final List<XFile> _selectedVideos = [];

  String? currentUserId;

  bool _isUploading = false; // แสดง loading ตอนส่งข้อความ
  bool _isLoadingUsers = true; // แสดง loading ตอนโหลดรายชื่อผู้ใช้

  Map<String, String> _userNamesCache = {}; // แคชชื่อผู้ใช้ {id: name}
  Map<String, String> _userloadpic = {}; // แคชชื่อผู้ใช้ {id: name}

bool _isLoadingUserId = true;

// Map<String, GlobalKey> _messageKeys = {};
Map<String, dynamic>? _replyingMessage;



Future<List<Map<String, dynamic>>> _loadMyFriends() async {
  final prefs = await SharedPreferences.getInstance();
  final authToken = prefs.getString('token_api') ?? '';
  final me = jsonDecode(prefs.getString('user_info')!);
  final userId = me['id'];

  final url = Uri.parse(
    'https://privatechat-api.team.orangeworkshop.info/api/manage-friend/get-by-id/$userId',
  );

  final res = await http.get(url, headers: {
    'Authorization': 'Bearer $authToken',
  });

  if (res.statusCode != 200) return [];

  final data = jsonDecode(res.body)['data'] as List<dynamic>;
  return data.map<Map<String, dynamic>>((u) => {
    'id': u['id'].toString(),
    'name': (u['name'] ?? '').toString(),
    'image': (u['image'] ?? '').toString(),
    'code': (u['code'] ?? '').toString(),
  }).toList();
}

void _openSendContactPicker() async {
  final friends = await _loadMyFriends();
  if (!mounted) return;

  if (friends.isEmpty) {
    _showToast("ยังไม่มีเพื่อนให้ส่ง");
    return;
  }

  showModalBottomSheet(
    context: context,
    builder: (_) => SafeArea(
      child: ListView.builder(
        itemCount: friends.length,
        itemBuilder: (_, i) {
          final f = friends[i];
          return ListTile(
            leading: CircleAvatar(
              backgroundImage: (f['image'] as String).isNotEmpty
                  ? NetworkImage(f['image'])
                  : null,
              child: (f['image'] as String).isEmpty
                  ? const Icon(Icons.person)
                  : null,
            ),
            title: Text(f['name']),
            subtitle: Text('รหัสเพื่อน: ${f['code'].isEmpty ? '-' : f['code']}'),
            onTap: () async {
              Navigator.pop(context);
              await _sendContactCardOfFriend(f);
            },
          );
        },
      ),
    ),
  );
}


Future<void> _sendContactCardOfFriend(Map<String, dynamic> friend) async {
  if (currentUserId == null) return;

  final contactId = (friend['id'] ?? '').toString();
  final contactName = (friend['name'] ?? '').toString();
  final contactImage = (friend['image'] ?? '').toString();
  final contactCode = (friend['code'] ?? '').toString();

  final messageId = const Uuid().v4();

  await FirebaseFirestore.instance
      .collection('chat_groups')
      .doc(widget.groupId)
      .collection('messages')
      .doc(messageId)
      .set({
    'text': '',
    'images': [],
    'videos': [],
    'senderId': currentUserId,
    'timestamp': FieldValue.serverTimestamp(),
    'readBy': [currentUserId],
    'replyTo': null,
    'reactions': {},
    'deletedFor': [],

    'type': 'contact',
    'contact': {
      'id': contactId,
      'name': contactName,
      'image': contactImage,
      'code': contactCode,
    },
  });

  _showToast("ส่ง Contact ของ ${contactName.isEmpty ? 'เพื่อน' : contactName} แล้ว");
}



Future<Map<String, dynamic>?> _getMe() async {
  final prefs = await SharedPreferences.getInstance();
  final userJson = prefs.getString('user_info');
  if (userJson == null) return null;
  return jsonDecode(userJson) as Map<String, dynamic>;
}

Future<void> _sendContactCard() async {
  if (currentUserId == null) return;

  final me = await _getMe();
  if (me == null) return;

  final contactId = me['id'].toString();
  final contactName = (me['name'] ?? '').toString();
  final contactImage = (me['image'] ?? '').toString();
  final contactCode = (me['code'] ?? '').toString();

  final messageId = const Uuid().v4();

  await FirebaseFirestore.instance
      .collection('chat_groups')
      .doc(widget.groupId)
      .collection('messages')
      .doc(messageId)
      .set({
    'text': '',                       // ไม่ต้องมีข้อความ
    'images': [],
    'videos': [],
    'senderId': currentUserId,
    'timestamp': FieldValue.serverTimestamp(),
    'readBy': [currentUserId],
    'replyTo': null,
    'reactions': {},
    'deletedFor': [],

    // ✅ contact payload
    'type': 'contact',
    'contact': {
      'id': contactId,
      'name': contactName,
      'image': contactImage,
      'code': contactCode,
    },
  });

  _showToast("ส่ง Contact แล้ว");
}


Widget _buildContactCard(Map<String, dynamic> c) {
  final cid = (c['id'] ?? '').toString();
  final name = (c['name'] ?? '').toString();
  final code = (c['code'] ?? '').toString();
  final image = (c['image'] ?? '').toString();

  final isMeCard = cid == currentUserId;

  return Container(
    width: 240,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Contact',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.none,
            color: Colors.orange,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: image.isNotEmpty ? NetworkImage(image) : null,
              child: image.isEmpty ? const Icon(Icons.person) : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Unknown' : name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.none,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    code.isNotEmpty ? 'รหัสเพื่อน: $code' : '',
                    style: const TextStyle(
                      fontSize: 11,
                      decoration: TextDecoration.none,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
        const SizedBox(height: 10),

        // ✅ ปุ่มเพิ่มเพื่อน
        if (!isMeCard)
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 6),
              color: CupertinoColors.activeBlue,
              child: const Text('เพิ่มเพื่อน'),
              onPressed: () => _addFriendFromContact(cid),
            ),
          )
        else
          const Text(
            'นี่คือ Contact ของคุณ',
            style: TextStyle(
              fontSize: 11,
              decoration: TextDecoration.none,
              color: Colors.white70,
            ),
          ),
      ],
    ),
  );
}



Future<void> _addFriendFromContact(String friendIdStr) async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token_api');
  final meJson = prefs.getString('user_info');

  if (token == null || meJson == null) {
    _showToast("ไม่พบ token หรือ user_info");
    return;
  }

  final me = jsonDecode(meJson);
  final myId = me['id'];

  final friendId = int.tryParse(friendIdStr);
  if (friendId == null) {
    _showToast("friendId ไม่ถูกต้อง");
    return;
  }

  final url = Uri.parse('https://privatechat-api.team.orangeworkshop.info/api/manage-friend/add');

  try {
    final res = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'user_id': myId,
        'friend_id': friendId,
      }),
    );

    if (res.statusCode == 200) {
      _showToast("เพิ่มเพื่อนสำเร็จ");
    } else {
      final body = jsonDecode(res.body);
      _showToast(body['message']?.toString() ?? 'เพิ่มเพื่อนไม่สำเร็จ');
    }
  } catch (e) {
    _showToast("เกิดข้อผิดพลาด: $e");
  }
}


Future<void> _pinMessage(String messageId, Map<String, dynamic> messageData) async {
  if (currentUserId == null) return;

  final ref = FirebaseFirestore.instance
      .collection('chat_groups')
      .doc(widget.groupId)
      .collection('pinned_messages')
      .doc(messageId);

  await ref.set({
    'messageId': messageId,
    'pinnedAt': FieldValue.serverTimestamp(),
    'pinnedBy': currentUserId,

    // เก็บ preview ไว้โชว์แถบบน (ไม่จำเป็นแต่แนะนำ)
    'text': messageData['text'] ?? '',
    'senderName': messageData['senderName'] ?? (_userNamesCache[messageData['senderId']?.toString()] ?? ''),
    'timestamp': messageData['timestamp'],
  }, SetOptions(merge: true));
}

Future<void> _unpinMessage(String messageId) async {
  final ref = FirebaseFirestore.instance
      .collection('chat_groups')
      .doc(widget.groupId)
      .collection('pinned_messages')
      .doc(messageId);

  await ref.delete();
}


Future<void> _openImageGallery(
  List<String> imageUrls, {
  required String initialUrl,
  String? messageText,
}) async {
  if (imageUrls.isEmpty) return;

  final initialIndex = imageUrls.indexOf(initialUrl).clamp(0, imageUrls.length - 1);
  final pageController = PageController(initialPage: initialIndex);

  int currentIndex = initialIndex;

  // ✅ คุมสถานะการซูม เพื่อกัน PageView แย่ง gesture
  final TransformationController tfc = TransformationController();
  final ValueNotifier<bool> isZoomed = ValueNotifier<bool>(false);

  void updateZoomState() {
    final scale = tfc.value.getMaxScaleOnAxis();
    isZoomed.value = scale > 1.01; // เกิน 1 นิดๆ ถือว่าซูมอยู่
  }

  tfc.addListener(updateZoomState);

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false, // ✅ กันปิดด้วยการแตะมั่วๆ
    builder: (_) {
      return StatefulBuilder(
        builder: (context, setLocalState) {
          return Material(
            color: Colors.black,
            child: SafeArea(
              child: Stack(
                children: [
                  // ✅ PageView + InteractiveViewer (ซูม/ลาก)
                  Positioned.fill(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: isZoomed,
                      builder: (_, zoomed, __) {
                        return PageView.builder(
                          controller: pageController,
                          itemCount: imageUrls.length,
                          physics: zoomed
                              ? const NeverScrollableScrollPhysics() // ✅ ซูมอยู่ → ห้ามปัดหน้า
                              : const BouncingScrollPhysics(),       // ✅ ไม่ซูม → ปัดหน้าได้
                          onPageChanged: (i) {
                            setLocalState(() => currentIndex = i);

                            // ✅ เปลี่ยนหน้าแล้ว reset การซูม ไม่ให้ค่าซูมจากรูปก่อนหน้าค้าง
                            tfc.value = Matrix4.identity();
                            isZoomed.value = false;
                          },
                          itemBuilder: (context, index) {
                            final url = imageUrls[index];

                            return Center(
                              child: InteractiveViewer(
                                transformationController: tfc,
                                panEnabled: true,
                                scaleEnabled: true,
                                minScale: 1.0,
                                maxScale: 6.0,
                                boundaryMargin: const EdgeInsets.all(120),
                                child: Image.network(
                                  url,
                                  fit: BoxFit.contain,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.broken_image,
                                    color: Colors.white70,
                                    size: 64,
                                  ),
                                  loadingBuilder: (context, child, progress) {
                                    if (progress == null) return child;
                                    return const Center(child: CupertinoActivityIndicator());
                                  },
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),

                  // ✅ ปุ่มปิด (มุมบนซ้าย)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),

                  // ✅ ตัวเลขหน้า (ล่างกลาง)
                  Positioned(
                    bottom: (messageText != null && messageText.trim().isNotEmpty) ? 90 : 18,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '${currentIndex + 1} / ${imageUrls.length}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                  ),

                  // ✅ ข้อความใต้รูป (ถ้ามี)
                  if (messageText != null && messageText.trim().isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        color: Colors.black54,
                        child: Text(
                          messageText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),

                  // ✅ ปุ่มดาวน์โหลด (มุมล่างขวา)
                  Positioned(
                    right: 12,
                    bottom: (messageText != null && messageText.trim().isNotEmpty) ? 52 : 12,
                    child: FloatingActionButton(
                      backgroundColor: Colors.black54,
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Icon(Icons.download, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  tfc.removeListener(updateZoomState);
  tfc.dispose();
  isZoomed.dispose();

  if (result == true) {
    final url = imageUrls[currentIndex];
    await _saveImage(url);
  }
}



void _openMultiForwardSheet() async {
  final targets = await _loadForwardTargets();

  showModalBottomSheet(
    context: context,
    builder: (_) {
      return SafeArea(
        child: ListView.builder(
          itemCount: targets.length,
          itemBuilder: (_, index) {
            final t = targets[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: (t['image']!.isNotEmpty)
                    ? NetworkImage(t['image']!)
                    : null,
              ),
              title: Text(t['name']!),
              onTap: () async {
                String? targetGroupId;

                if (t['type'] == 'group') {
                  targetGroupId = t['id'];
                } else {
                  targetGroupId = await _getPrivateChatGroupId(t['id']!);
                }

                if (targetGroupId != null) {
                  for (var messageId in _selectedMessageIds) {
                    final doc = await FirebaseFirestore.instance
                        .collection('chat_groups')
                        .doc(widget.groupId)
                        .collection('messages')
                        .doc(messageId)
                        .get();

                    if (doc.exists) {
                      await _forwardMessageToTarget(
                        messageId,
                        doc.data() as Map<String, dynamic>,
                        targetGroupId,
                      );
                    }
                  }

                  Navigator.pop(context);
                  _showToast(
                    "Forwarded ${_selectedMessageIds.length} messages.",
                  );

                  setState(() {
                    _isSelectingMessages = false;
                    _selectedMessageIds.clear();
                  });
                }
              },
            );
          },
        ),
      );
    },
  );
}



void _showEmojiPicker(String messageId) {
  final emojis = ['👍','👎','👌','👀','❤️','🔥','🤣','😲','😭','✅','❌','🚨'];

  showModalBottomSheet(
    context: context,
    builder: (context) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 16,
          children: emojis.map((emoji) {
            return GestureDetector(
              onTap: () {
                _toggleReaction(messageId, emoji);
                Navigator.pop(context);
              },
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 32),
              ),
            );
          }).toList(),
        ),
      );
    },
  );
}



Future<void> _unsendMessage(String messageId) async {
  await FirebaseFirestore.instance
      .collection('chat_groups')
      .doc(widget.groupId)
      .collection('messages')
      .doc(messageId)
      .delete();
}


Future<void> _deleteForMe(String messageId) async {
  await FirebaseFirestore.instance
      .collection('chat_groups')
      .doc(widget.groupId)
      .collection('messages')
      .doc(messageId)
      .set({
        'deletedFor': FieldValue.arrayUnion([currentUserId])
      }, SetOptions(merge: true));
}

void _editMessage(String messageId, Map<String, dynamic> messageData) {
  final controller = TextEditingController(text: messageData['text']);

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text("Edit message"),
      content: TextField(
        controller: controller,
        maxLines: 3,
        decoration: const InputDecoration(hintText: "แก้ไขข้อความ"),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("ยกเลิก"),
        ),
        TextButton(
          onPressed: () async {
            await FirebaseFirestore.instance
                .collection('chat_groups')
                .doc(widget.groupId)
                .collection('messages')
                .doc(messageId)
                .update({
              'text': controller.text,
              'edited': true,
            });

            Navigator.pop(context);
          },
          child: const Text("บันทึก"),
        ),
      ],
    ),
  );
}

Future<String?> _getPrivateChatGroupId(String friendId) async {
  final prefs = await SharedPreferences.getInstance();
  final authToken = prefs.getString('token_api') ?? '';
  final userInfo = jsonDecode(prefs.getString('user_info')!);
  final userId = userInfo['id'];

  final res = await http.post(
    Uri.parse('https://privatechat-api.team.orangeworkshop.info/api/group-chat/private'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $authToken',
    },
    body: jsonEncode({
      'user_id': userId,
      'friend_id': friendId,
    }),
  );

  if (res.statusCode == 200) {
    final data = jsonDecode(res.body);
    return data['group_chat_id'].toString();
  }

  print("❌ ERROR private chat: ${res.body}");
  return null;
}


Future<List<Map<String, String>>> _loadForwardTargets() async {
  List<Map<String, String>> list = [];

  final prefs = await SharedPreferences.getInstance();
  final authToken = prefs.getString('token_api') ?? '';
  final userId = jsonDecode(prefs.getString('user_info')!)['id'];

  // ⭐ โหลดแชทกลุ่ม
  final url = Uri.parse(
      'https://privatechat-api.team.orangeworkshop.info/api/user/group-chat-by-id/$userId');

  final res = await http.get(url, headers: {
    'Authorization': 'Bearer $authToken',
  });

  if (res.statusCode == 200) {
    final groups = jsonDecode(res.body)['data'];
    for (var g in groups) {
      final isGroupChat = g['code'] != null && g['code'].toString().isNotEmpty;

      if (!isGroupChat) continue;

      list.add({
        'type': 'group',
        'id': g['id'].toString(),
        'name': g['name'],
        'image': g['image'] ?? '',   // ⭐ เพิ่มรูปกลุ่ม
      });
    }
  }

  // ⭐ โหลดเพื่อน
  final url2 = Uri.parse(
      'https://privatechat-api.team.orangeworkshop.info/api/manage-friend/get-by-id/$userId');

  final res2 = await http.get(url2, headers: {
    'Authorization': 'Bearer $authToken',
  });

  if (res2.statusCode == 200) {
    final friends = jsonDecode(res2.body)['data'];
    for (var f in friends) {
      list.add({
        'type': 'friend',
        'id': f['id'].toString(),
        'name': f['name'],
        'image': f['image'] ?? '',   // ⭐ เพิ่มรูปเพื่อน
      });
    }
  }

  return list;
}




Future<void> _forwardMessageToTarget(
  String messageId,
  Map<String, dynamic> data,
  String targetGroupId,
) async {

  print("========================================");
  print(" 🚀 เริ่มส่งต่อข้อความ ");
  print("========================================");

  final senderName = _userNamesCache[currentUserId] ?? "Unknown";
  final senderImage = _userloadpic[currentUserId] ?? "";

  final originalSenderId = (data['senderId'] ?? '').toString();
  final originalName = (data['senderName'] ?? _userNamesCache[originalSenderId] ?? '').toString();

  final payload = {
    'text': data['text'] ?? '',
    'images': data['images'] ?? [],
    'videos': data['videos'] ?? [],
    'senderId': currentUserId,
    'senderName': senderName,        // ⭐ เพิ่ม
    'senderImage': senderImage,      // ⭐ เพิ่ม
    'timestamp': FieldValue.serverTimestamp(),
    'readBy': [currentUserId],

    // ⭐ เพื่อให้รู้ว่ามาจากข้อความไหน
    'forwardFromGroup': widget.groupId,
    'forwardOriginalId': messageId,

    // ⭐ ต้องมีเพื่อให้ bubble ไม่ error
    'replyTo': null,
    'reactions': {},
    'deletedFor': [],

// ✅ forwardFromName
    'forwardFromName': originalName,
  };

  print("📦 payload ที่จะส่งต่อ = $payload");

  try {
    final result = await FirebaseFirestore.instance
        .collection('chat_groups')
        .doc(targetGroupId)
        .collection('messages')
        .add(payload);

    print("✅ ADD สำเร็จ messageId ใหม่ = ${result.id}");
    print("========================================");

  } catch (e, s) {
    print("❌ ERROR ส่งต่อผิดพลาด");
    print("Error: $e");
    print("Stack: $s");
  }
}


void _openForwardSheet(String messageId, Map<String, dynamic> messageData) async {
  final targets = await _loadForwardTargets();

  showModalBottomSheet(
    context: context,
    builder: (_) {
      return SafeArea(
        child: ListView.builder(
          itemCount: targets.length,
          itemBuilder: (_, index) {
            final t = targets[index];
            return ListTile(
               leading: CircleAvatar(
                radius: 22,
                backgroundImage: (t['image'] != null && t['image']!.isNotEmpty)
                    ? NetworkImage(t['image']!)
                    : null,
                child: (t['image'] == null || t['image']!.isEmpty)
                    ? const Icon(Icons.person)
                    : null,
              ),
              title: Text(t['name']!),
              onTap: () async {

                String? targetGroupId;

                if (t['type'] == 'group') {
                  // ⭐ ส่งเข้ากลุ่มปกติ
                  targetGroupId = t['id'];
                } else {
                  // ⭐ Forward หาเพื่อน ต้องสร้างห้องแชทส่วนตัวก่อน
                  print("🔍 หา group_chat_id ของเพื่อน ${t['name']}");
                  targetGroupId = await _getPrivateChatGroupId(t['id']!);
                }

                if (targetGroupId != null) {
                  await _forwardMessageToTarget(
                    messageId,
                    messageData,
                    targetGroupId,
                  );
                  Navigator.of(context, rootNavigator: true).pop();
                  _showToast("Sendding Success.");
                } else {
                  _showToast("เกิดข้อผิดพลาด ไม่พบห้องแชท");
                }
              },
            );
          },
        ),
      );
    },
  );
}



void _showMessageOptions(Map<String, dynamic> messageData, String messageId) {
  final isMe = messageData['senderId'] == currentUserId;
  final isPinned = _pinnedMessageIds.contains(messageId);

  showModalBottomSheet(
    context: context,
    builder: (_) {
      return SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                _setReplyMessage(messageData, messageId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.emoji_emotions),
              title: const Text('Reaction'),
              onTap: () {
                Navigator.pop(context);
                _showEmojiPicker(messageId);
              },
            ),

            if (isMe) ...[
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit message'),
                onTap: () {
                  Navigator.pop(context);
                  _editMessage(messageId, messageData);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever),
                title: const Text('Unsend message'),
                onTap: () {
                  Navigator.pop(context);
                  _unsendMessage(messageId);
                },
              ),
            ],

            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Delete from my view'),
              onTap: () {
                Navigator.pop(context);
                _deleteForMe(messageId);
              },
            ),

           ListTile(
            leading: const Icon(Icons.forward),
            title: const Text('Forward'),
            onTap: () {
              Navigator.pop(context);
             _openForwardSheet(messageId, messageData);
            },
          ),


          ListTile(
            leading: const Icon(Icons.check_box),
            title: const Text('Select messages'),
            onTap: () {
              Navigator.pop(context);
              setState(() {
                _isSelectingMessages = true;
                _selectedMessageIds.clear();
                _selectedMessageIds.add(messageId); // ข้อความที่กดค้างอันแรก
              });
            },
          ),


          ListTile(
  leading: Icon(isPinned ? Icons.push_pin_outlined : Icons.push_pin),
  title: Text(isPinned ? 'Unpin' : 'Pin'),
  onTap: () async {
    Navigator.pop(context);
    if (isPinned) {
      await _unpinMessage(messageId);
      _showToast("Unpinned");
    } else {
      await _pinMessage(messageId, messageData);
      _showToast("Pinned");
    }
  },
),
          
          ],
        ),
      );
    },
  );
}


void scrollToMessageSimple(String messageId) {
  final index = _currentMessageOrder.indexOf(messageId);

  if (index == -1) {
    print("❌ messageId ไม่อยู่ในช่วงที่โหลด/แสดง: $messageId");
    return;
  }

  if (_itemScrollController.isAttached) {
    _itemScrollController.scrollTo(
      index: index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.15,
    );
  } else {
    print("❌ ItemScrollController ยังไม่ attach");
  }
}

void _setReplyMessage(Map<String, dynamic> message, String messageId) {
  setState(() {
    _replyingMessage = {
      'id': messageId,
      'text': message['text'] ?? '',
      'images': message['images'] ?? [],
      'videos': message['videos'] ?? [],
      'senderName': message['senderName'] ?? '',
    };
  });
}

void _cancelReply() {
  setState(() {
    _replyingMessage = null;
  });
}


Widget _buildReactions(String messageId, Map<String, dynamic> reactions) {
  if (reactions.isEmpty) return const SizedBox.shrink();

  return Wrap(
    spacing: 6,
    children: reactions.entries.map((entry) {
      final emoji = entry.key;
      final users = List<String>.from(entry.value ?? []);
      final count = users.length;
      final isMine = currentUserId != null && users.contains(currentUserId);

      return GestureDetector(
        onTap: () => _showWhoReacted(emoji, users),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isMine ? Colors.blue[100] : Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16 , decoration: TextDecoration.none,)),
           if (count > 0) ...[
            const SizedBox(width: 4),
            Text(
              count.toString(),
              style: const TextStyle(
                fontSize: 12.0, // ปรับขนาดตรงนี้ เล็กลงหรือใหญ่ขึ้นตามต้องการ
                decoration: TextDecoration.none,
              ),
            ),
          ],
            ],
          ),
        ),
      );
    }).toList(),
  );
}


void _showWhoReacted(String emoji, List<String> users) {
  List<String> names = users.map((id) => _userNamesCache[id] ?? 'Unknown').toList();

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('คนที่กด $emoji'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: names.map((name) => ListTile(
            leading: Text(emoji, style: const TextStyle(fontSize: 20)),
            title: Text(name),
          )).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ปิด'),
        ),
      ],
    ),
  );
}



void _toggleReaction(String messageId, String emoji) async {
  if (currentUserId == null) return;

  final docRef = FirebaseFirestore.instance
      .collection('chat_groups')
      .doc(widget.groupId)
      .collection('messages')
      .doc(messageId);

  await FirebaseFirestore.instance.runTransaction((transaction) async {
    final snapshot = await transaction.get(docRef);
    Map<String, dynamic> reactions =
        Map<String, dynamic>.from(snapshot.get('reactions') ?? {});

    List users = List.from(reactions[emoji] ?? []);

    if (users.contains(currentUserId)) {
      users.remove(currentUserId);

      // ถ้าไม่มีคนกดเลย → ลบ key ออกจาก map
      if (users.isEmpty) {
        reactions.remove(emoji);
      } else {
        reactions[emoji] = users;
      }

    } else {
      users.add(currentUserId);
      reactions[emoji] = users;
    }

    transaction.update(docRef, {'reactions': reactions});
  });
}




String _shortenReplyText(Map<String, dynamic> reply) {
  String content = '';
  if (reply['text']?.toString().isNotEmpty == true) {
    content = reply['text'];
    // ตัดให้เหลือ 4 คำ
    List<String> words = content.split(' ');
    if (words.length > 4) {
      content = words.sublist(0, 4).join(' ') + '...';
    }
  } else if (reply['images'] != null && (reply['images'] as List).isNotEmpty) {
    content = '[รูปภาพ]';
  } else if (reply['videos'] != null && (reply['videos'] as List).isNotEmpty) {
    content = '[วิดีโอ]';
  }
  return content;
}


Widget _buildReplyContent(Map<String, dynamic> reply) {
  // ถ้ามีข้อความ → แสดงข้อความปกติ
  if (reply['text']?.toString().isNotEmpty == true) {
    String content = reply['text'];
    List<String> words = content.split(' ');
    if (words.length > 4) {
      content = words.sublist(0, 4).join(' ') + '...';
    }
    return Text(
      content,
      style: const TextStyle(
        color: Colors.black87,
        fontStyle: FontStyle.italic,
        decoration: TextDecoration.none,
        fontSize: 15.0,
      ),
    );
  }

  // ถ้ามีรูปภาพ → แสดง thumbnail
  final images = (reply['images'] as List<dynamic>? ?? []).cast<String>();
  if (images.isNotEmpty) {
    return SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: images.map((url) {
          return GestureDetector(
            onTap: () {
              // กดดูภาพเต็มหน้าจอ
              // คุณอาจสร้างฟังก์ชัน _openImageFullScreen(url)
            },
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              child: Image.network(
                url,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ถ้ามีวิดีโอ → แสดง thumbnail วิดีโอ
  final videos = (reply['videos'] as List<dynamic>? ?? []).cast<String>();
  if (videos.isNotEmpty) {
    return SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: videos.map((url) {
          return Container(
            margin: const EdgeInsets.only(right: 6),
            width: 60,
            height: 60,
            child: VideoWidget(url: url),
          );
        }).toList(),
      ),
    );
  }

  // ถ้าไม่มีข้อความหรือสื่อ → แสดง placeholder
  return const SizedBox(
    height: 24,
    child: Center(
      child: Text(
        'Video',
        style: TextStyle(
          fontStyle: FontStyle.italic,
          color: Colors.black45,
          decoration: TextDecoration.none,
          fontSize: 15.0, // ปรับขนาดตรงนี้ เล็กลงหรือใหญ่ขึ้นตามต้องการ
        ),
      ),
    ),
  );
}


@override
void initState() {
  super.initState();

    _loadUserId();
    _loadUserListFromApi();
    _setPresenceActive(true);

    fetchUnreadNotifications();

     _loadInitialMessages();

   
   _pinnedSub = FirebaseFirestore.instance
    .collection('chat_groups')
    .doc(widget.groupId)
    .collection('pinned_messages')
    .snapshots()
    .listen((snap) {
  setState(() {
    _pinnedMessageIds = snap.docs.map((d) => d.id).toSet();
  });
});

  // ✅ เคลียร์ badge/notification ตอนเข้าหน้าแชท
  Future.delayed(const Duration(milliseconds: 300), () async {
    await flutterLocalNotificationsPlugin.cancelAll(); // ล้าง notification ทั้งหมด
    FlutterAppBadger.removeBadge(); // ล้าง badge บนไอคอนทั้ง iOS/Android
  });

  _itemPositionsListener.itemPositions.addListener(() {
  final positions = _itemPositionsListener.itemPositions.value;
  if (positions.isEmpty) return;

  // เพราะ reverse:true → เวลาเลื่อนไป "ข้อความเก่า" เราจะเข้าใกล้ index ท้ายๆ
  final maxIndex = positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);

  // ใกล้ท้ายลิสต์แล้วค่อยโหลดเพิ่ม
  if (_hasMore && !_isLoadingMore && maxIndex >= _currentMessageOrder.length - 8) {
  _loadMoreMessages();
}
});
}

Future<void> _loadInitialMessages() async {
  final query = await FirebaseFirestore.instance
      .collection('chat_groups')
      .doc(widget.groupId)
      .collection('messages')
      .orderBy('timestamp', descending: true)
      .limit(_messagesLimit)
      .get();

  setState(() {
    _messages = query.docs;
    _hasMore = query.docs.length == _messagesLimit;
    _lastDoc = query.docs.isNotEmpty ? query.docs.last : null; // ✅ สำคัญ
  });
}

Future<void> _loadMoreMessages() async {
  if (_isLoadingMore || !_hasMore) return;
  if (_lastDoc == null) return;

  _isLoadingMore = true;

  final query = await FirebaseFirestore.instance
      .collection('chat_groups')
      .doc(widget.groupId)
      .collection('messages')
      .orderBy('timestamp', descending: true)
      .startAfterDocument(_lastDoc!)
      .limit(_messagesLimit)
      .get();

  setState(() {
    _messages.addAll(query.docs);
    _hasMore = query.docs.length == _messagesLimit;
    if (query.docs.isNotEmpty) _lastDoc = query.docs.last; // ✅ อัปเดตตัวล่าสุด
  });

  _isLoadingMore = false;
}

   Stream<QuerySnapshot> _lastMessagesStream() {
    return FirebaseFirestore.instance
        .collection('chat_groups')
        .doc(widget.groupId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(600) 
        .snapshots();
  }


  @override
  void dispose() {
    _pinnedSub?.cancel();
    _searchController.dispose(); // ✅ add
    _scrollController.dispose();
    _setPresenceActive(false);
    super.dispose();
  }


// @override
// void dispose() {
//   _setPresenceActive(false);
//   super.dispose();
// }

Future<void> _loadCurrentUserId() async {
  final prefs = await SharedPreferences.getInstance();
  final userInfoJson = prefs.getString('user_info');
  if (userInfoJson != null) {
    final userInfo = jsonDecode(userInfoJson);
    setState(() {
      currentUserId = userInfo['id'].toString();
    });
  }
}


Future<void> _setPresenceActive(bool isActive) async {
  final prefs = await SharedPreferences.getInstance();
  final userInfoJson = prefs.getString('user_info');
  if (userInfoJson == null) return;
  final userInfo = jsonDecode(userInfoJson);
  final userId = userInfo['id'].toString();

  await FirebaseFirestore.instance
      .collection('chat_presence')
      .doc(widget.groupId)
      .collection('users')
      .doc(userId)
      .set({
        'isActive': isActive,
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}


  void _showCupertinoAlert(String message) {
  showCupertinoDialog(
    context: context,
    builder: (_) => CupertinoAlertDialog(
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


Future<void> _loadUserId() async {
  final prefs = await SharedPreferences.getInstance();
  final userJson = prefs.getString('user_info');
  if (userJson != null) {
    final userData = jsonDecode(userJson);
    currentUserId = userData['id'].toString();
    print("✅ Loaded currentUserId: $currentUserId");
  } else {
    print("🚨 ไม่พบ user_info ใน SharedPreferences");
  }

  setState(() {
    _isLoadingUserId = false;
  });
}

  Future<void> _loadUserListFromApi() async {
    setState(() {
      _isLoadingUsers = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString('token_api') ?? '';

      final response = await http.get(
        Uri.parse('https://privatechat-api.team.orangeworkshop.info/api/user/selectall'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final Map<String, String> loadedUsers = {};
        final Map<String, String> loadpic = {};
        for (var user in data) {
          final idStr = user['id'].toString();
          final name = user['name'] ?? 'Unknown';
          final image = user['image'] ?? '';
          loadedUsers[idStr] = name;
          loadpic[idStr] = image;
        }
        setState(() {
          _userNamesCache = loadedUsers;
          _userloadpic = loadpic;
          _isLoadingUsers = false;
        });
      } else {
        print('API Error: ${response.statusCode}');
        setState(() {
          _isLoadingUsers = false;
        });
      }
    } catch (e) {
      print('Failed to load user list: $e');
      setState(() {
        _isLoadingUsers = false;
      });
    }
  }


  // ฟังก์ชันเช็คสถานะเพื่อน (สมมุติใช้ Firestore)
Future<bool> _checkFriendActiveStatus() async {
  final friendInfoJson = await SharedPreferences.getInstance().then((prefs) => prefs.getString('friend_info'));
  if (friendInfoJson == null) return false; // ไม่มีข้อมูลเพื่อน ให้ส่ง noti เถอะ

  final friendInfo = jsonDecode(friendInfoJson);
  final friendId = friendInfo['id'].toString();

  final doc = await FirebaseFirestore.instance
      .collection('chat_presence')
      .doc(widget.groupId)
      .collection('users')
      .doc(friendId)
      .get();

  if (!doc.exists) return false;

  final data = doc.data();
  if (data == null) return false;

  // สมมุติใช้ field 'isActive' เป็น bool
  return data['isActive'] == true;
}

// ฟังก์ชันส่ง noti
Future<void> _sendNotificationToFriend() async {
 final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token_api');
  final userInfoJson = prefs.getString('user_info');

  if (token == null || userInfoJson == null) return;

  final userInfo = jsonDecode(userInfoJson);
  final userId = userInfo['id'].toString();

  final url = Uri.parse('https://privatechat-api.team.orangeworkshop.info/api/send-noti');

  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    },
    body: jsonEncode({
      'user_id': userId,
      'group_id': widget.groupId,
    }),
  );

  if (response.statusCode == 200) {
    print('ส่ง noti สำเร็จ');
  } else {
    final body = json.decode(response.body);
    print('ส่ง noti ล้มเหลว: ${body['message']}');
  }
}

Future<void> _markMessageAsRead(String messageId) async {
  if (currentUserId == null) return;

  final docRef = FirebaseFirestore.instance
      .collection('chat_groups')
      .doc(widget.groupId)
      .collection('messages')
      .doc(messageId);

  await docRef.set({
    'readBy': FieldValue.arrayUnion([currentUserId])
  }, SetOptions(merge: true));
}



Future<void> _sendMessage() async {
  print("🟢 sendMessage เรียกใช้งานแล้ว");
  print("currentUserId = $currentUserId");

  if (currentUserId == null) {
    _showCupertinoAlert('ไม่สามารถส่งข้อความได้: ยังไม่ได้โหลดรหัสผู้ใช้งาน');
    return;
  }

  final text = _textController.text.trim();
  if (text.isEmpty && _selectedImages.isEmpty && _selectedVideos.isEmpty) return;

  setState(() {
    _isUploading = true;
  });

  final messageId = const Uuid().v4();
  List<String> images = [];
  List<String> videos = [];

  try {
    // อัปโหลดรูปภาพ
    for (var image in _selectedImages) {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance
          .ref('chat_images/${widget.groupId}/$messageId/$fileName');
      final bytes = await image.readAsBytes();
      await ref.putData(bytes);
      final url = await ref.getDownloadURL();
      images.add(url);
    }

    // อัปโหลดวิดีโอ
    for (var video in _selectedVideos) {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.mp4';
      final ref = FirebaseStorage.instance
          .ref('chat_videos/${widget.groupId}/$messageId/$fileName');
      final bytes = await video.readAsBytes();
      await ref.putData(bytes);
      final url = await ref.getDownloadURL();
      videos.add(url);
    }


    // บันทึกข้อความและลิงก์ภาพ/วิดีโอลง Firestore
    await FirebaseFirestore.instance
        .collection('chat_groups')
        .doc(widget.groupId)
        .collection('messages')
        .doc(messageId) // ใช้ doc แบบกำหนด id
        .set({
      'text': text,
      'images': images,
      'videos': videos,
      'senderId': currentUserId,
      'timestamp': FieldValue.serverTimestamp(),
      'readBy': [currentUserId], // ✅ เพิ่ม currentUserId ลง array readBy
      'replyTo': _replyingMessage, // ✅ เพิ่มตรงนี้
      'reactions': {}, // ✅ เพิ่ม field reactions ว่างตอนสร้างข้อความ
      'deletedFor': [],
    });

    print('ส่งข้อความสำเร็จ');

     // ✅ ล้าง text field & selection ทันที
    _textController.clear();
    _selectedImages.clear();
    _selectedVideos.clear();
    _replyingMessage = null;

    // // เช็คสถานะเพื่อนก่อนส่ง noti
    // bool friendIsActive = await _checkFriendActiveStatus();
    // // bool friendIsActive = false; // ไม่ต้องเช็คสถานะแล้ว ส่งทุกครั้ง
    // if (!friendIsActive) {
    //   await _sendNotificationToFriend();
    // }

    await _sendNotificationToFriend(); // เรียกทุกครั้ง ไม่เช็คสถานะ

    // --- ส่ง HTTP GET 2 API ตามที่ขอ ---
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('token_api') ?? '';

    try {
      final response1 = await http.get(
        Uri.parse('https://privatechat-api.team.orangeworkshop.info/api/group-chat/touch/${widget.groupId}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );
      print('API 1 status: ${response1.statusCode}');

      final response2 = await http.get(
        Uri.parse('https://privatechat-api.team.orangeworkshop.info/api/group-chat-user/touch/${widget.groupId}/$currentUserId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );
      print('API 2 status: ${response2.statusCode}');
    } catch (e) {
      print('Error เรียก API หลังส่งข้อความ: $e');
    }

    
    setState(() {
      // _textController.clear();
      // _selectedImages.clear();
      // _selectedVideos.clear();
      // _replyingMessage = null;
    });
  } catch (e) {
    print('Upload error: $e');
  } finally {
    setState(() {
      _isUploading = false;
    });
  }
}


  // เลือกรูปภาพ
// เลือกรูปภาพหลายภาพ
// เลือกรูปภาพ (หลายภาพพร้อมกัน)

Future<void> _pickImage() async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedImages.addAll(
          result.files.map((f) => XFile(f.path!)),
        );
      });
    }
  } catch (e) {
    print('FilePicker error: $e');
  }
}

  // เลือกวิดีโอ
  Future<void> _pickVideo() async {
  try {
    // จำกัดไม่ให้เลือกเกิน 4 ไฟล์รวมรูปกับวิดีโอ
    if (_selectedImages.length + _selectedVideos.length >= 4) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true, // ✅ เลือกได้หลายวิดีโอ
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        // แปลงเป็น XFile เพื่อใช้ต่อได้เหมือนเดิม
        _selectedVideos.addAll(
          result.files
              .map((f) => XFile(f.path!))
              .take(4 - (_selectedImages.length + _selectedVideos.length)), 
              // ✅ กันไม่ให้เกิน 4 ไฟล์รวมกัน
        );
      });
    }
  } catch (e) {
    print('FilePicker video error: $e');
  }
}




Future<void> _saveAllMedia(List<String> images, List<String> videos) async {
  if (!await _requestPermission()) {
    _showToast('กรุณาให้สิทธิ์การเข้าถึงไฟล์');
    return;
  }

  int savedCount = 0;

  // เซฟรูปภาพทั้งหมด
  for (String imageUrl in images) {
    try {
      var response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        var documentDirectory = await getTemporaryDirectory();
        File file = File('${documentDirectory.path}/${DateTime.now().millisecondsSinceEpoch}.jpg');
        await file.writeAsBytes(response.bodyBytes);
        bool? result = await GallerySaver.saveImage(file.path, albumName: "PrivateChat");
        if (result == true) savedCount++;
      }
    } catch (e) {
      print("Error saving image: $e");
    }
  }

  // เซฟวิดีโอทั้งหมด
  for (String videoUrl in videos) {
    try {
      var response = await http.get(Uri.parse(videoUrl));
      if (response.statusCode == 200) {
        var documentDirectory = await getTemporaryDirectory();
        File file = File('${documentDirectory.path}/${DateTime.now().millisecondsSinceEpoch}.mp4');
        await file.writeAsBytes(response.bodyBytes);
        bool? result = await GallerySaver.saveVideo(file.path, albumName: "PrivateChat");
        if (result == true) savedCount++;
      }
    } catch (e) {
      print("Error saving video: $e");
    }
  }

  _showToast("บันทึกไฟล์ทั้งหมดแล้ว ($savedCount ไฟล์)");
}



Future<void> _saveImage(String url) async {

  if (!await _requestPermission()) {
    _showToast('กรุณาให้สิทธิ์การเข้าถึงภาพ');
    return;
  }

  try {
    var response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      _showToast('ไม่สามารถดาวน์โหลดภาพได้');
      return;
    }

    var documentDirectory = await getTemporaryDirectory();
    File file = File('${documentDirectory.path}/${DateTime.now().millisecondsSinceEpoch}.jpg');
    await file.writeAsBytes(response.bodyBytes);

    bool? result = await GallerySaver.saveImage(file.path, albumName: "PrivateChat");
    _showToast(result == true ? 'บันทึกรูปภาพแล้ว' : 'ไม่สามารถบันทึกรูปภาพได้');
  } catch (e) {
    print("Error saving image: $e");
    _showToast('ไม่สามารถบันทึกรูปได้');
  }
}

Future<void> _saveVideo(String url) async {

  if (!await _requestPermission()) {
    _showToast('กรุณาให้สิทธิ์การเข้าถึงวิดีโอ');
    return;
  }

  try {
    var response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      _showToast('ไม่สามารถดาวน์โหลดวิดีโอได้');
      return;
    }

    var documentDirectory = await getTemporaryDirectory();
    File file = File('${documentDirectory.path}/${DateTime.now().millisecondsSinceEpoch}.mp4');
    await file.writeAsBytes(response.bodyBytes);

    bool? result = await GallerySaver.saveVideo(file.path, albumName: "PrivateChat");
    if (result == true) {
      _showToast('บันทึกวิดีโอแล้ว');
    } else {
      _showToast('ไม่สามารถบันทึกวิดีโอได้');
    }
  } catch (e) {
    print("Error saving video: $e");
    _showToast('ไม่สามารถบันทึกวิดีโอได้');
  }
}

// ฟังก์ชันขอ permission
Future<bool> _requestPermission() async {
  if (Platform.isAndroid) {
    if (await Permission.storage.isGranted) return true;

    if (await Permission.photos.isGranted && await Permission.videos.isGranted) return true;

    Map<Permission, PermissionStatus> statuses = await [
      Permission.storage,
      Permission.photos,
      Permission.videos,
    ].request();

    return statuses.values.every((status) => status.isGranted);
  } else if (Platform.isIOS) {
    var status = await Permission.photos.status;
    if (!status.isGranted) {
      status = await Permission.photos.request();
    }
    return status.isGranted;
  }
  return false;
}


// ฟังก์ชันโชว์ SnackBar
void _showToast(String message) {
  Fluttertoast.showToast(
    msg: message,
    toastLength: Toast.LENGTH_SHORT,
    gravity: ToastGravity.BOTTOM,
    backgroundColor: Colors.black54,
    textColor: Colors.white,
    fontSize: 16.0,
  );
}


_openImageFullScreen(String imageUrl, {String? messageText}) async {
  final result = await showDialog(
    context: context,
    useRootNavigator: true,
    builder: (_) => GestureDetector(
      onTap: () => Navigator.of(context, rootNavigator: true).pop(false),
      child: Container(
        color: Colors.black87,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: InteractiveViewer(
                child: Image.network(imageUrl),
              ),
            ),

            // ======= แสดงข้อความใต้รูป ========
            if (messageText != null && messageText.trim().isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Colors.black54,
                child: Text(
                  messageText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),

            // ปุ่มดาวน์โหลด
            Container(
              padding: const EdgeInsets.only(bottom: 20),
              child: IconButton(
                icon: const Icon(Icons.download, color: Colors.white, size: 30),
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).pop(true),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  if (result == true) {
    await _saveImage(imageUrl);
  }
}

_openVideoFullScreen(String videoUrl) async {
  final result = await showDialog(
    context: context,
    useRootNavigator: true,
    builder: (_) => GestureDetector(
      onTap: () => Navigator.of(context, rootNavigator: true).pop(false),
      child: Container(
        color: Colors.black87,
        alignment: Alignment.center,
        child: Stack(
          children: [
            Center(child: _FullScreenVideoPlayer(url: videoUrl)),
            Positioned(
              bottom: 30,
              right: 30,
              child: IconButton(
                icon: const Icon(Icons.download, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  if (result == true) {
    await _saveVideo(videoUrl);
  }
}


Future<void> fetchUnreadNotifications() async {
  try {
    final prefs = await SharedPreferences.getInstance();

    // ดึงข้อความล่าสุด 50 ข้อความ
    final messagesQuery = await FirebaseFirestore.instance
        .collection('chat_groups')
        .doc(widget.groupId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(10)
        .get();

    if (messagesQuery.docs.isEmpty) return;

    String? friendId;       // ข้อความล่าสุดของเพื่อน
    String? lastMyMessageId; // ข้อความล่าสุดของเราเอง

    for (var doc in messagesQuery.docs) {
      final senderId = doc.data()['senderId']?.toString();

      if (senderId != currentUserId && friendId == null) {
        friendId = senderId;
      }
      if (senderId == currentUserId && lastMyMessageId == null) {
        lastMyMessageId = doc.id;
      }
      if (friendId != null && lastMyMessageId != null) break;
    }

    if (friendId == null || lastMyMessageId == null) return;

    _lastMessageId = lastMyMessageId;

    print('🟢 friendId ล่าสุดของเพื่อน: $friendId');
    print('🟢 lastMessageId ของเรา: $_lastMessageId');

    // เรียก API ของเพื่อนเพื่อตรวจสอบ unread
    final authToken = prefs.getString('token_api') ?? '';
    final url = Uri.parse(
      'https://privatechat-api.team.orangeworkshop.info/api/chatting-room/notifications/unread-count/$friendId'
    );

    final response = await http.get(url, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $authToken',
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List<dynamic> unreadGroupIdsRaw = data['กลุ่มที่ยังไม่ได้อ่าน'] ?? [];
      final Set<int> unreadGroupIds =
          unreadGroupIdsRaw.map((id) => int.tryParse(id.toString()) ?? -1).toSet();

      final groupIdInt = int.tryParse(widget.groupId) ?? -1;
      setState(() {
        // ❌ เปลี่ยนชื่อ _hasUnread ให้ตรงกับ concept
        _hasUnread = {groupIdInt: unreadGroupIds.contains(groupIdInt)};
      });
      print('🟩 _hasUnread updated: $_hasUnread');
    } else {
      print('❌ Unread API error: ${response.statusCode} ${response.body}');
    }
  } catch (e) {
    print('❌ Unread fetch error: $e');
  }
}


Future<bool> _showConfirmDialog(String message) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("ยืนยันการดาวน์โหลด"),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("ยกเลิก"),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("ตกลง"),
            ),
          ],
        ),
      ) ??
      false;
}

Future<void> _confirmStartPrivateChat(String friendId, String friendName) async {
  bool confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("เริ่มแชทส่วนตัว"),
          content: Text("คุณต้องการเริ่มแชทกับ $friendName หรือไม่?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("ยกเลิก"),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("ตกลง"),
            ),
          ],
        ),
      ) ??
      false;

  if (confirm) {
    await _startPrivateChat(friendId, friendName);
  }
}


Future<void> _startPrivateChat(String friendId, String friendName) async {
  final prefs = await SharedPreferences.getInstance();
  final authToken = prefs.getString('token_api') ?? '';
  final userInfoJson = prefs.getString('user_info');
  if (userInfoJson == null) return;

  final user = jsonDecode(userInfoJson);
  final userId = user['id'];

  print('👉 ส่งไป API /group-chat/private');
  print('user_id: $userId');
  print('friend_id: $friendId');

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
            groupName: friendName,
            groupId: groupId,
          ),
        ),
      ).then((value) {
        // โหลดรายชื่อเพื่อนใหม่ ถ้าจำเป็น
        fetchUnreadNotifications();
      });
    } else {
      print('API error: ${response.statusCode} ${response.body}');
      _showCupertinoAlert('เกิดข้อผิดพลาด: ${response.body}');
    }
  } catch (e) {
    print('API call error: $e');
    _showCupertinoAlert('เกิดข้อผิดพลาด: $e');
  }
}


 Widget _buildMessage(Map<String, dynamic> data, String messageId) {
    final isPinned = _pinnedMessageIds.contains(messageId); // ✅ ย้ายขึ้นบน
   final deletedFor = (data['deletedFor'] as List<dynamic>? ?? []).cast<String>();
  if (deletedFor.contains(currentUserId)) {
    return const SizedBox.shrink();
  }
  final senderId = data['senderId']?.toString() ?? '';
  final isMe = senderId == currentUserId;
  final text = data['text'] as String? ?? '';
  final timestamp = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
  final images = (data['images'] as List<dynamic>? ?? []).cast<String>();
  final videos = (data['videos'] as List<dynamic>? ?? []).cast<String>();

  final isForwarded = data['forwardOriginalId'] != null;
  final fromName = (data['forwardFromName'] ?? '').toString();

  final senderName = _userNamesCache[senderId] ?? 'ไม่ทราบชื่อ';
  final picture = _userloadpic[senderId] ?? '';

  final type = (data['type'] ?? '').toString();
  final contact = data['contact'] as Map<String, dynamic>?;
  final isContact = type == 'contact' && contact != null;

  // อ่านแล้ว
  final readBy = (data['readBy'] as List<dynamic>? ?? []).cast<String>();
  bool isRead = false;

  final reply = data['replyTo'] as Map<String, dynamic>?;

  if (senderId == currentUserId) {
    // ข้อความของเราเอง → อ่านแล้วถ้าเพื่อนอ่านแล้ว
    isRead = readBy.length > 1;
  } else {
    // ข้อความของคนอื่น → อ่านแล้วถ้าเราอยู่ใน readBy
    isRead = readBy.contains(currentUserId);

    // ✅ mark as read อัตโนมัติ
    if (!isRead) {
      _markMessageAsRead(messageId); // ใช้ messageId ที่ส่งเข้ามา
    }
  }



return KeyedSubtree(
 key: ValueKey(messageId), // ✅ ใช้ ValueKey แทน GlobalKey
  child: GestureDetector(
  onLongPress: () {
    if (_isSelectingMessages) return; // ถ้าอยู่โหมดเลือก ไม่โชว์เมนู
    _showMessageOptions(data, messageId);
  },
  onTap: () {
    if (_isSelectingMessages) {
      setState(() {
        if (_selectedMessageIds.contains(messageId)) {
          _selectedMessageIds.remove(messageId);
        } else {
          _selectedMessageIds.add(messageId);
        }
      });
    }
  },

    child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // ⭐ Checkbox แสดงเฉพาะตอนเลือกหลายข้อความ
    if (_isSelectingMessages)
  Material(
    color: Colors.transparent,
    child: Checkbox(
      value: _selectedMessageIds.contains(messageId),
      onChanged: (val) {
        setState(() {
          if (val == true) {
            _selectedMessageIds.add(messageId);
          } else {
            _selectedMessageIds.remove(messageId);
          }
        });
      },
    ),
  ),
  Flexible(
  fit: FlexFit.loose,
  child: Align(
    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF1B386A) : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [



              // ✅ เพิ่มตรงนี้ (ก่อน isPinned/Row ก็ได้)
  if (isForwarded)
  Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      fromName.isNotEmpty ? 'Forwarded from $fromName' : 'Forwarded',
      style: const TextStyle(
        fontSize: 11,
        color: Colors.orange,
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.none,
      ),
    ),
  ),

            // ใน bubble header แถวชื่อ หรือมุมขวา
if (isPinned)
  const Padding(
    padding: EdgeInsets.only(left: 6),
    child: Icon(Icons.push_pin, size: 20, color: Color.fromARGB(255, 243, 54, 2)),
  ),

Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    if (picture.isNotEmpty)
  GestureDetector(
    onTap: () {
      if (senderId == currentUserId) return;
      _confirmStartPrivateChat(senderId, senderName);
    },
    child: CircleAvatar(
      radius: 14,
      backgroundImage: NetworkImage(picture),
      backgroundColor: Colors.grey.shade200,
    ),
  )
else
  GestureDetector(
    onTap: () {
      if (senderId == currentUserId) return;
      _confirmStartPrivateChat(senderId, senderName);
    },
    child: const CircleAvatar(
      radius: 14,
      backgroundColor: Colors.grey,
      child: Icon(Icons.person, size: 16, color: Colors.white),
    ),
  ),
    const SizedBox(width: 6),
    
  Flexible(
      child: Text(
      senderName,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 14,
        color: isMe ? Colors.white70 : Colors.black87,
        decoration: TextDecoration.none,
       ),
    )
  ),
  ],
),




if (reply != null)
  GestureDetector(
    onTap: () {
       scrollToMessageSimple(reply['id']);
    },
    child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isMe ? Colors.white24 : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: Colors.blueAccent, width: 3)),
      ),
      child: _buildReplyContent(reply),
    ),
  ),



            const SizedBox(height: 4),

            // ✅ 1) ถ้าเป็น contact → แสดงการ์ด contact อย่างเดียว
if (isContact) ...[
  _buildContactCard(Map<String, dynamic>.from(contact!)),
  const SizedBox(height: 6),
] else ...[
if (text.isNotEmpty)
  GestureDetector(
    onLongPress: () {
      Clipboard.setData(ClipboardData(text: text));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('คัดลอกข้อความแล้ว')),
      );
    },
   child: Container(
  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
  decoration: BoxDecoration(
    color: (_isSearchMode &&
            _searchQuery.isNotEmpty &&
            text.toLowerCase().contains(_searchQuery.toLowerCase()))
        ? Colors.yellow.withOpacity(0.35)
        : Colors.transparent,
    borderRadius: BorderRadius.circular(6),
  ),
  child: SelectableText(
    text,
    style: TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 18,
      color: isMe ? Colors.white : Colors.black,
      decoration: TextDecoration.none,
      height: 1.3,
    ),
  ),
),
  ),

  


const SizedBox(height: 4),

            if (images.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: images.map((url) {
                  return GestureDetector(
                    onTap: () => _openImageGallery(
  images,
  initialUrl: url,
  messageText: text,
),
                    child: Image.network(
                      url,
                      width: 160,
                      height: 160,
                      fit: BoxFit.cover,
                    ),
                  );
                }).toList(),
              ),
            if (videos.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: videos.map((url) {
                  return GestureDetector(
                    onTap: () => _openVideoFullScreen(url),
                    child: VideoWidget(url: url),
                  );
                }).toList(),
              ),
            const SizedBox(height: 4),
            ],

            Text(
  DateFormat('dd MMM yyyy HH:mm').format(timestamp),
  style: TextStyle(
    fontSize: 12,
    color: isMe ? Colors.white70 : Colors.black54,
    decoration: TextDecoration.none,
    fontStyle: FontStyle.italic, // เพิ่มความนุ่มนวล
  ),
),


 const SizedBox(height: 7),

  _buildReactions(messageId, Map<String, dynamic>.from(data['reactions'] ?? {})),

            const SizedBox(height: 10),

if (isMe && isRead)
  Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'อ่านแล้ว',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    ),
  ),

  if (images.isNotEmpty || videos.isNotEmpty)
  TextButton.icon(
    onPressed: () async {
      bool confirm = await _showConfirmDialog(
          "คุณต้องการบันทึกรูปและวิดีโอทั้งหมดหรือไม่?");
      if (confirm) {
        _saveAllMedia(images, videos);
      }
    },
    icon: const Icon(Icons.download),
    label: const Text("บันทึกทั้งหมด"),
  ),
          
           ],      // ✔ ปิด children ของ Column
        ),         // ✔ ปิด Column
      ),           // ✔ ปิด Container
    ),             // ✔ ปิด Align
  ),               // ✔ ปิด Expanded
],                // ❗ ปิด children: [] ของ Row หลัก
),   
),             // ❗ ปิด Row หลัก
);                // ❗ ปิด GestureDetector
}

@override
Widget build(BuildContext context) {
  if (_isLoadingUsers || _isLoadingUserId) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.groupName, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1B386A),
        border: null,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(CupertinoIcons.back, color: Colors.white),
        ),

         // ✅ เพิ่ม trailing ปุ่มค้นหา
  trailing: CupertinoButton(
    padding: EdgeInsets.zero,
    child: Icon(
      _isSearchMode ? CupertinoIcons.clear_circled_solid : CupertinoIcons.search,
      color: Colors.white,
      size: 22,
    ),
    onPressed: () {
      setState(() {
        _isSearchMode = !_isSearchMode;
        if (!_isSearchMode) {
          _searchQuery = '';
          _searchController.clear();
        }
      });
    },
  ),

      ),
      child: const Center(
        child: CupertinoActivityIndicator(radius: 20),
      ),
    );
  }

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.groupName, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1B386A),
        border: null,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(CupertinoIcons.back, color: Colors.white),
        ),
         trailing: CupertinoButton( // ✅ ต้องมีด้วย
      padding: EdgeInsets.zero,
      child: Icon(
        _isSearchMode ? CupertinoIcons.clear_circled_solid : CupertinoIcons.search,
        color: Colors.white,
        size: 22,
      ),
      onPressed: () {
        setState(() {
          _isSearchMode = !_isSearchMode;
          if (!_isSearchMode) {
            _searchQuery = '';
            _searchController.clear();
          }
        });
      },
    ),
      ),
      child: SafeArea(
        child: Column(
          children: [

            // ✅ Search Bar (แสดงเฉพาะตอนเปิดโหมดค้นหา)
if (_isSearchMode)
  Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
    color: CupertinoColors.systemGrey6,
    child: Column(
      children: [
        CupertinoTextField(
          controller: _searchController,
          placeholder: 'ค้นหาข้อความ...',
          clearButtonMode: OverlayVisibilityMode.editing,
          onChanged: (v) {
            setState(() {
              _searchQuery = v.trim();
            });
          },
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _searchQuery.isEmpty ? 'พิมพ์คำเพื่อค้นหา' : 'กำลังค้นหา: "$_searchQuery"',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    ),
  ),


  StreamBuilder<QuerySnapshot>(
  stream: FirebaseFirestore.instance
      .collection('chat_groups')
      .doc(widget.groupId)
      .collection('pinned_messages')
      .orderBy('pinnedAt', descending: true)
      .limit(30)
      .snapshots(),
  builder: (context, snap) {
    if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();

    final pinnedDocs = snap.data!.docs;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: CupertinoColors.systemGrey6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.push_pin, size: 16),
              SizedBox(width: 6),
              Text("Pinned",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, decoration: TextDecoration.none)),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: pinnedDocs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final d = pinnedDocs[i].data() as Map<String, dynamic>;
                final mid = pinnedDocs[i].id;

                final preview = (d['text'] ?? '').toString().replaceAll('\n', ' ').trim();
                final sender = (d['senderName'] ?? '').toString().trim();
                final label = preview.isNotEmpty
                    ? (preview.length > 10 ? '${preview.substring(0, 10)}...' : preview)
                    : '[Media]';

                return GestureDetector(
                 onTap: () => scrollToMessageSimple(mid),
                  onLongPress: () async {
                    await _unpinMessage(mid);
                    _showToast("Unpinned");
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black12),
                    ),
                   child: ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: 240),
  child: Text(
    sender.isNotEmpty ? '$sender: $label' : label,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(fontSize: 12, decoration: TextDecoration.none),
  ),
),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  },
),

         Expanded(
  child: StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection('chat_groups')
        .doc(widget.groupId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(600)
        .snapshots(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CupertinoActivityIndicator());
      }

       // ✅ เพิ่มบรรทัดนี้ (นี่แหละที่หายไป)
  final liveDocs = snapshot.data!.docs;

     final Map<String, DocumentSnapshot> byId = {};

// live มาก่อน
for (final d in liveDocs) {
  byId[d.id] = d;
}

// แล้วค่อยเติมของเก่า
for (final d in _messages) {
  byId.putIfAbsent(d.id, () => d);
}

final combined = byId.values.toList();

combined.sort((a, b) {
  final at = (a.data() as Map)['timestamp'] as Timestamp?;
  final bt = (b.data() as Map)['timestamp'] as Timestamp?;
  final aMs = at?.millisecondsSinceEpoch ?? 0;
  final bMs = bt?.millisecondsSinceEpoch ?? 0;
  return bMs.compareTo(aMs);
});

      // ✅ FILTER เมื่อเปิดโหมดค้นหา
List<DocumentSnapshot> displayDocs = combined;

if (_isSearchMode && _searchQuery.isNotEmpty) {
  final q = _searchQuery.toLowerCase();
  displayDocs = combined.where((d) {
    final data = (d.data() as Map<String, dynamic>);
    final text = (data['text'] ?? '').toString().toLowerCase();
    return text.contains(q);
  }).toList();
}

// ✅ อัปเดตลำดับ id ตามที่แสดงจริง (หลัง filter แล้ว)
_currentMessageOrder = displayDocs.map((d) => d.id).toList();

     return SelectionArea(
  child: ScrollablePositionedList.builder(
    itemScrollController: _itemScrollController,
    itemPositionsListener: _itemPositionsListener,
    reverse: true,
    itemCount: displayDocs.length,
    itemBuilder: (context, index) {
      final doc = displayDocs[index];
      return _buildMessage(doc.data() as Map<String, dynamic>, doc.id);
    },
  ),
);
    },
  ),
),



            // แสดงภาพและวิดีโอที่เลือกก่อนส่ง
            if (_selectedImages.isNotEmpty || _selectedVideos.isNotEmpty)
              Container(
                height: 100,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    ..._selectedImages.map((img) {
                      return Stack(
                        children: [
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            child: kIsWeb
                                ? FutureBuilder<Uint8List>(
                                    future: img.readAsBytes(),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                              ConnectionState.done &&
                                          snapshot.hasData) {
                                        return Image.memory(snapshot.data!,
                                            width: 100,
                                            height: 100,
                                            fit: BoxFit.cover);
                                      } else {
                                        return const SizedBox(
                                          width: 100,
                                          height: 100,
                                          child: CupertinoActivityIndicator(),
                                        );
                                      }
                                    },
                                  )
                                : Image.file(File(img.path),
                                    width: 100, height: 100, fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedImages.remove(img);
                                });
                              },
                              child: const Icon(CupertinoIcons.clear_circled_solid,
                                  color: Colors.red),
                            ),
                          ),
                        ],
                      );
                    }),
                    ..._selectedVideos.map((vid) {
                      return Stack(
                        children: [
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            child: SizedBox(
                              width: 100,
                              height: 100,
                              child: VideoWidget(url: vid.path, isLocal: true),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedVideos.remove(vid);
                                });
                              },
                              child: const Icon(CupertinoIcons.clear_circled_solid,
                                  color: Colors.red),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),

            // ส่วนกรอกข้อความและปุ่มส่ง
Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  color: CupertinoColors.systemGrey6,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [

      // ⭐ แถบเลือกข้อความหลายอัน (ถูกต้องแล้ว)
      if (_isSelectingMessages)
      Container(
  color: Colors.blue.shade50,
  padding: const EdgeInsets.all(8),
  child: Row(
    children: [
      Flexible(
        child: Text(
          "${_selectedMessageIds.length} ข้อความที่เลือก",
          // overflow: TextOverflow.ellipsis,
          style: const TextStyle(
    decoration: TextDecoration.none,
    fontSize: 13,
  ),
        ),
      ),
      const Spacer(),
      CupertinoButton(
  padding: const EdgeInsets.symmetric(horizontal: 6),
  minSize: 30,
  color: CupertinoColors.systemRed.withOpacity(0.15),
  child: const Text(
    "Cancel",
    style: TextStyle(
      fontSize: 14,
      color: CupertinoColors.systemRed,
    ),
  ),
  onPressed: () {
    setState(() {
      _isSelectingMessages = false;
      _selectedMessageIds.clear();
    });
  },
),

const SizedBox(width: 6), // ⭐ ระยะห่างระหว่างปุ่ม

CupertinoButton(
  padding: const EdgeInsets.symmetric(horizontal: 6),
  minSize: 30,
  color: CupertinoColors.systemGreen,
  child: const Text(
    "Forward",
    style: TextStyle(
      fontSize: 14,
      color: CupertinoColors.white,
    ),
  ),
  onPressed:
      _selectedMessageIds.isEmpty ? null : _openMultiForwardSheet,
),


    ],
  ),
),


      // ================================
      // 🔽 ส่วน Reply (เดิม)
      // ================================
      if (_replyingMessage != null)
        Container(
          width: double.infinity,
          color: Colors.grey[200],
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.reply, color: Colors.blue),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _shortenReplyText(_replyingMessage!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    decoration: TextDecoration.none,
                    fontSize: 12.0,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: _cancelReply,
              ),
            ],
          ),
        ),

      const SizedBox(height: 4),

      // ================================
      // 🔽 แถวพิมพ์ข้อความ (เดิม)
      // ================================
      Row(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            child: const Icon(CupertinoIcons.photo),
            onPressed: _pickImage,
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            child: const Icon(CupertinoIcons.videocam),
            onPressed: _pickVideo,
          ),

          Expanded(
            child: CupertinoTextField(
              controller: _textController,
              placeholder: 'พิมพ์ข้อความ...',
              enabled: !_isUploading,
              maxLines: null,
              minLines: 1,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              inputFormatters: [DigitJoinFormatter()], // ✅ เพิ่มบรรทัดนี้
            ),
          ),

          CupertinoButton(
            padding: EdgeInsets.zero,
            child: _isUploading
                ? const CupertinoActivityIndicator()
                : const Icon(CupertinoIcons.arrow_up_circle_fill),
            onPressed: currentUserId == null || _isUploading
                ? null
                : _sendMessage,
          ),


          CupertinoButton(
  padding: EdgeInsets.zero,
  child: const Icon(CupertinoIcons.person_crop_circle_badge_plus),
  onPressed: _openSendContactPicker,
),

        ],
      ),

    ],
  ),
)


          ],
        ),
      ),
    );
  }
}

class DigitJoinFormatter extends TextInputFormatter {
  // ✅ จับเฉพาะ "ช่องว่าง" ที่คั่นอยู่ "ระหว่างเลข"
  // รองรับเลขอารบิก 0-9 และเลขไทย ๐-๙
  static final RegExp _betweenDigitsSpace = RegExp(
    r'(?<=[0-9\u0E50-\u0E59])[\s\u00A0\u200B\u200C\u200D\uFEFF\u202F\u2009]+(?=[0-9\u0E50-\u0E59])',
  );

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final fixed = newValue.text.replaceAll(_betweenDigitsSpace, '');

    // ถ้าไม่เปลี่ยน ไม่ต้องสร้างค่าใหม่
    if (fixed == newValue.text) return newValue;

    return TextEditingValue(
      text: fixed,
      selection: TextSelection.collapsed(offset: fixed.length),
    );
  }
}

class VideoWidget extends StatefulWidget {
  final String url;
  final bool isLocal;

  const VideoWidget({required this.url, this.isLocal = false, super.key});

  @override
  State<VideoWidget> createState() => _VideoWidgetState();
}

class _VideoWidgetState extends State<VideoWidget> {
  late VideoPlayerController _controller;
  bool initialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.isLocal) {
      _controller = VideoPlayerController.file(File(widget.url))
        ..initialize().then((_) {
          setState(() {
            initialized = true;
          });
        });
    } else {
      _controller = VideoPlayerController.network(widget.url)
        ..initialize().then((_) {
          setState(() {
            initialized = true;
          });
        });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!initialized) {
      return const SizedBox(
        width: 100,
        height: 100,
        child: CupertinoActivityIndicator(),
      );
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        // GestureDetector แค่ส่วนวิดีโอ (thumbnail) สำหรับเล่น/หยุด
        GestureDetector(
          onTap: () {
            setState(() {
              if (_controller.value.isPlaying) {
                _controller.pause();
              } else {
                _controller.play();
              }
            });
          },
          child: SizedBox(
            width: 100,
            height: 100,
            child: VideoPlayer(_controller),
          ),
        ),

        if (!_controller.value.isPlaying)
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow,
              color: Colors.white,
              size: 30,
            ),
          ),

        // ปุ่ม fullscreen แยก GestureDetector ออกมา เพื่อให้กดแล้วขยายจอ (ไม่เล่น/หยุดวิดีโอ)
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () {
              final chatPageState = context.findAncestorStateOfType<_ChatPage_CodeState>();
              if (chatPageState != null) {
                chatPageState._openVideoFullScreen(widget.url);
              }
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.fullscreen,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FullScreenVideoPlayer extends StatefulWidget {
  final String url;

  const _FullScreenVideoPlayer({required this.url, Key? key}) : super(key: key);

  @override
  State<_FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<_FullScreenVideoPlayer> {
  late VideoPlayerController _controller;
  bool initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.url)
      ..initialize().then((_) {
        setState(() {
          initialized = true;
          _controller.play();
          _controller.setLooping(true);
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        color: Colors.black87,
        child: Center(
          child: initialized
              ? AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                )
              : const CupertinoActivityIndicator(),
        ),
      ),
    );
  }
}

// ignore: subtype_of_sealed_class
class _FakeDoc implements QueryDocumentSnapshot {
  final String id;
  final Map<String, dynamic> _data;
  _FakeDoc({required this.id, required Map<String, dynamic> data}) : _data = data;

  @override
  Map<String, dynamic> data() => _data;

  // dummy properties
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

