import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../core/network/api_client.dart';

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

  int get _ticketId => widget.ticket['id'] as int;

  @override
  void initState() {
    super.initState();
    _status = (widget.ticket['status']?.toString() ?? 'open');
    _load();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final resp = await ApiClient.instance.dio.get('/complaints/$_ticketId/messages');
      if (!mounted) return;
      setState(() {
        _messages = List<Map<String, dynamic>>.from(resp.data as List);
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
      setState(() {
        _messages = [..._messages, Map<String, dynamic>.from(resp.data as Map)];
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
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.black),
              onPressed: _load,
              tooltip: 'Refresh',
            ),
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
            padding: EdgeInsets.fromLTRB(
              12,
              8,
              12,
              12 + MediaQuery.of(context).viewInsets.bottom,
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
