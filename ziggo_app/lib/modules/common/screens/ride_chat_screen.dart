import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/ws_client.dart';
import '../../../core/storage/token_storage.dart';

class RideChatScreen extends StatefulWidget {
  static bool isOpen = false;

  final int bookingId;
  final String otherParticipantName;
  final bool isDriver;

  const RideChatScreen({
    super.key,
    required this.bookingId,
    required this.otherParticipantName,
    required this.isDriver,
  });

  @override
  State<RideChatScreen> createState() => _RideChatScreenState();
}

class _RideChatScreenState extends State<RideChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  // ── Real-time chat ─────────────────────────────────────────────────────────
  final WsClient _ws = WsClient();
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  Timer? _pollTimer;
  int _lastMsgId = 0;

  @override
  void initState() {
    super.initState();
    RideChatScreen.isOpen = true;
    _load();
    _connectRealtime();
  }

  @override
  void dispose() {
    RideChatScreen.isOpen = false;
    _pollTimer?.cancel();
    _wsSub?.cancel();
    _ws.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Real-time helpers ──────────────────────────────────────────────────────

  Future<void> _connectRealtime() async {
    final token = await TokenStorage.getToken();
    if (token != null && token.isNotEmpty) {
      _ws.connect(token);
      _wsSub = _ws.events.listen((msg) {
        final event = msg['event'];
        final data = msg['data'] as Map<String, dynamic>?;
        if (event == 'chat_message' &&
            data != null &&
            data['booking_id']?.toString() == widget.bookingId.toString()) {
          // If we receive a message from websocket, we can add it to our list
          final senderType = data['sender_type']?.toString();
          
          bool isMe = false;
          if (widget.isDriver && senderType == 'driver') isMe = true;
          if (!widget.isDriver && senderType == 'customer') isMe = true;

          // if it's from us, we already added it locally during _send, so skip.
          if (!isMe) {
            final newMsg = {
              'id': DateTime.now().millisecondsSinceEpoch, // fake id
              'body': data['message'],
              'sender_type': senderType,
              'created_at': DateTime.now().toIso8601String(),
            };
            if (mounted) {
              setState(() {
                _messages.add(newMsg);
              });
              _scrollToBottom();
            }
          }
        }
      });
    }

    // Fallback polling
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _reload());
  }

  Future<void> _reload() async {
    try {
      final resp = await ApiClient.instance.dio.get('/bookings/${widget.bookingId}/messages');
      if (!mounted) return;
      final newMessages = List<Map<String, dynamic>>.from(resp.data as List);
      final newLastId = newMessages.isNotEmpty
          ? (newMessages.last['id'] as int? ?? 0)
          : 0;
      final hasNew = newLastId > _lastMsgId;
      if (hasNew) {
        setState(() {
          _messages = newMessages;
          _lastMsgId = newLastId;
        });
        _scrollToBottom();
      }
    } catch (_) {
      // Endpoint might not exist yet or failed, just ignore silent polling errors
    }
  }

  Future<void> _load() async {
    try {
      final resp = await ApiClient.instance.dio.get('/bookings/${widget.bookingId}/messages');
      if (!mounted) return;
      final msgs = List<Map<String, dynamic>>.from(resp.data as List);
      setState(() {
        _messages = msgs;
        _lastMsgId = msgs.isNotEmpty ? (msgs.last['id'] as int? ?? 0) : 0;
        _loading = false;
        _error = null;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      // If endpoint doesn't exist (e.g. 404), just start empty
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _sendText(String text) async {
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    
    // Add locally for instant feedback
    final localMsg = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'body': text,
      'sender_type': widget.isDriver ? 'driver' : 'customer',
      'created_at': DateTime.now().toIso8601String(),
    };
    setState(() {
      _messages.add(localMsg);
    });
    _scrollToBottom();

    try {
      await ApiClient.instance.dio.post(
        '/bookings/${widget.bookingId}/message',
        data: {'message': text}, 
      );
      if (!mounted) return;
      _messageController.clear();
      setState(() {
        _sending = false;
      });
      _reload(); // Reload to get true ID and timestamp if possible
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send message'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.otherParticipantName,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Text(
              'Active Ride Chat',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone, color: Colors.black),
            onPressed: () {
              // Usually handled by tapping the phone icon on the main screen
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(height: 1, color: AppColors.divider),
          
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final senderType = msg['sender_type']?.toString();
                      
                      bool isMe = false;
                      if (widget.isDriver && senderType == 'driver') isMe = true;
                      if (!widget.isDriver && senderType == 'customer') isMe = true;
                      
                      final body = (msg['message'] ?? msg['body'])?.toString() ?? '';

                      return _buildBubble(
                        body: body,
                        isMe: isMe,
                        time: _formatTime(msg['created_at']?.toString()),
                      );
                    },
                  ),
          ),
          
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildPresetBubble("I'm here"),
                _buildPresetBubble("Be right there"),
                _buildPresetBubble("I'm looking for you"),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (val) => _sendText(val),
                    decoration: InputDecoration(
                      hintText: 'Type your message',
                      filled: true,
                      fillColor: AppColors.surfaceMuted,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: AppColors.surfaceMuted,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _sending ? null : () => _sendText(_messageController.text),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: _sending
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(Icons.arrow_upward_rounded, color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetBubble(String text) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8, top: 4),
      child: InkWell(
        onTap: () => _sendText(text),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.textTertiary),
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBubble({
    required String body,
    required bool isMe,
    required String time,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isMe ? const Color(0xFF2B2B2B) : AppColors.surfaceMuted,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isMe ? 20 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 20),
                    ),
                  ),
                  child: Text(
                    body,
                    style: TextStyle(
                      color: isMe ? Colors.white : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (time.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                    child: Text(
                      time,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    } catch (_) {
      return '';
    }
  }
}
