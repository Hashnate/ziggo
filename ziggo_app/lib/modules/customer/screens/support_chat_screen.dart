import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/ws_client.dart';
import '../../../core/storage/token_storage.dart';

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key, required this.ticket});

  /// Map straight from /complaints list — needs id, subject, description,
  /// category, status, created_at.
  final Map<String, dynamic> ticket;

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String _status = 'open';

  // ── Real-time support ──────────────────────────────────────────────────────
  final WsClient _ws = WsClient();
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  Timer? _pollTimer;
  // Track the last message ID so we only scroll on genuinely new messages.
  int _lastMsgId = 0;

  int get _ticketId => widget.ticket['id'] as int;

  @override
  void initState() {
    super.initState();
    _status = (widget.ticket['status']?.toString() ?? 'open');
    _load();
    _connectRealtime();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _wsSub?.cancel();
    _ws.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Real-time helpers ──────────────────────────────────────────────────────

  /// Connect the user WebSocket (same connection used for ride updates) and
  /// listen for `support_message` events targeting this ticket.
  Future<void> _connectRealtime() async {
    final token = await TokenStorage.getToken();
    if (token != null && token.isNotEmpty) {
      _ws.connect(token);
      _wsSub = _ws.events.listen((msg) {
        final event = msg['event'];
        final data = msg['data'] as Map<String, dynamic>?;
        if (event == 'support_message' &&
            data != null &&
            data['ticket_id']?.toString() == _ticketId.toString()) {
          // New message pushed from the server — reload the thread.
          _reload();
        }
      });
    }

    // Fallback: poll every 3 seconds so messages arrive even if WS is dead.
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _reload());
  }

  /// Silently refresh messages in the background (no loading spinner).
  Future<void> _reload() async {
    try {
      final resp =
          await ApiClient.instance.dio.get('/complaints/$_ticketId/messages');
      if (!mounted) return;
      final newMessages =
          List<Map<String, dynamic>>.from(resp.data as List);
      // Determine the latest message id from the new list.
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
      // Silent — don't disrupt the UI if polling fails.
    }
  }

  // ── Initial load (shows spinner) ──────────────────────────────────────────

  Future<void> _load() async {
    try {
      final resp = await ApiClient.instance.dio.get('/complaints/$_ticketId/messages');
      if (!mounted) return;
      final msgs = List<Map<String, dynamic>>.from(resp.data as List);
      setState(() {
        _messages = msgs;
        _lastMsgId = msgs.isNotEmpty ? (msgs.last['id'] as int? ?? 0) : 0;
        _loading = false;
        _error = null;
      });
      _scrollToBottom();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.response?.data?['detail']?.toString() ?? 'Failed to load conversation';
      });
    }
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final resp = await ApiClient.instance.dio.post(
        '/complaints/$_ticketId/messages',
        data: {'body': text},
      );
      if (!mounted) return;
      _messageController.clear();
      final newMsg = Map<String, dynamic>.from(resp.data as Map);
      setState(() {
        _messages = [..._messages, newMsg];
        _lastMsgId = newMsg['id'] as int? ?? _lastMsgId;
        _sending = false;
      });
      _scrollToBottom();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.response?.data?['detail']?.toString() ?? 'Failed to send'),
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

  ({Color color, String label}) _statusMeta(String s) {
    switch (s) {
      case 'resolved':
        return (color: AppColors.success, label: 'Resolved');
      case 'in_progress':
        return (color: AppColors.flash, label: 'In progress');
      case 'closed':
        return (color: AppColors.textTertiary, label: 'Closed');
      default:
        return (color: AppColors.warning, label: 'Open');
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = _statusMeta(_status);
    final subject = widget.ticket['subject']?.toString() ?? 'Ticket #$_ticketId';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Colors.black,
              child: Icon(Icons.support_agent, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'Ziggo Support · ${meta.label}',
                    style: TextStyle(
                      color: meta.color,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            // Pulse indicator shows live connection status
            _LiveDot(connected: _ws.isConnected),
            const SizedBox(width: 4),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                              const SizedBox(height: 12),
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              TextButton(onPressed: _load, child: const Text('Retry')),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        itemCount: _messages.length + 1, // +1 for the opening description
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _buildBubble(
                              body: widget.ticket['description']?.toString() ?? '',
                              isMe: true,
                              time: _formatTime(widget.ticket['created_at']?.toString()),
                              label: 'You',
                            );
                          }
                          final msg = _messages[index - 1];
                          final role = msg['sender_role']?.toString() ?? '';
                          final isAdmin = role == 'admin';
                          return _buildBubble(
                            body: msg['body']?.toString() ?? '',
                            isMe: !isAdmin,
                            time: _formatTime(msg['created_at']?.toString()),
                            label: isAdmin ? 'Ziggo Support' : 'You',
                          );
                        },
                      ),
          ),
          if (_status == 'closed')
            Container(
              color: AppColors.surfaceMuted,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline, size: 16, color: AppColors.textSecondary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This ticket is closed. Sending a new message will re-open it.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              12,
              8,
              12,
              12,
            ),
            child: Row(
                children: [
                  Expanded(
                    child: TextField(
                    controller: _messageController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Type a message…',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppColors.cardBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppColors.cardBorder),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: AppColors.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _sending ? null : _send,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: _sending
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(Icons.send_rounded, color: Colors.black),
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

  Widget _buildBubble({
    required String body,
    required bool isMe,
    required String time,
    required String label,
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
                Padding(
                  padding: const EdgeInsets.only(bottom: 3, left: 4, right: 4),
                  child: Text(
                    '$label · $time',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? Colors.black : AppColors.surfaceMuted,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
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
      return iso;
    }
  }
}

// ── Small animated dot to show live/offline status ────────────────────────────

class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.connected});
  final bool connected;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.connected) {
      return const SizedBox(
        width: 8,
        height: 8,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.grey,
            shape: BoxShape.circle,
          ),
        ),
      );
    }
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFF22C55E), // green-500
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
