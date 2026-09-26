import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../domain/models/support_conversation.dart';
import '../domain/models/support_message.dart';
import '../services/support_chat_providers.dart';
import '../services/support_chat_service.dart';

// ── UUID helper ───────────────────────────────────────────────────────────────

String _newUuid() {
  final rng = math.Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20, 32)}';
}

// ── Pending message model ─────────────────────────────────────────────────────

enum _SendStatus { sending, failed }

class _PendingMsg {
  final String localId;
  final String text;
  final Uint8List? imageBytes;
  final String? attachmentMimeType;
  _SendStatus status = _SendStatus.sending;
  String? error;

  _PendingMsg({
    required this.localId,
    required this.text,
    this.imageBytes,
    this.attachmentMimeType,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SupportChatScreen
// ─────────────────────────────────────────────────────────────────────────────

class SupportChatScreen extends ConsumerStatefulWidget {
  const SupportChatScreen({super.key, this.inModal = false});

  final bool inModal;

  static void show(BuildContext context) {
    if (MediaQuery.of(context).size.width >= 768) {
      showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierLabel: '',
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (ctx, anim, _) => const _SupportChatDialog(),
        transitionBuilder: (ctx, anim, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SupportChatScreen()),
      );
    }
  }

  @override
  ConsumerState<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends ConsumerState<SupportChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final bool _sending = false;
  SupportConversation? _conversation;
  final List<_PendingMsg> _pendingMsgs = [];

  // Input gate: false when conv is closed, true when open or after onNewChat tapped
  bool _inputEnabled = false;
  // Set true the moment "Start a New Chat" is tapped so the UI switches
  // to active state immediately, before _initConversation() returns.
  bool _activatingNewChat = false;

  // Scroll management
  bool _atBottom = true;
  bool _hasNewMessages = false;

  // Unread divider
  bool _firstLoadDone = false;
  int? _unreadFromIndex;

  // Realtime channels
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _typingChannel;

  // Typing indicator
  bool _adminIsTyping = false;
  Timer? _adminTypingTimeout;
  Timer? _typingThrottle;
  bool _typingThrottled = false;

  // Attachment
  Uint8List? _pendingImageBytes;
  String? _pendingImageMime;
  String? _pendingImageFilename;

  @override
  void initState() {
    super.initState();
    _msgCtrl.addListener(_onMsgChanged);
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initConversation());
  }

  @override
  void dispose() {
    _msgCtrl.removeListener(_onMsgChanged);
    _scrollCtrl.removeListener(_onScroll);
    _typingThrottle?.cancel();
    _adminTypingTimeout?.cancel();
    if (_messagesChannel != null) {
      Supabase.instance.client.removeChannel(_messagesChannel!);
    }
    if (_typingChannel != null) {
      Supabase.instance.client.removeChannel(_typingChannel!);
    }
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final atBottom = _scrollCtrl.position.maxScrollExtent -
            _scrollCtrl.position.pixels <=
        150;
    if (_atBottom != atBottom) {
      setState(() {
        _atBottom = atBottom;
        if (atBottom) _hasNewMessages = false;
      });
    }
  }

  void _subscribeTyping(String convId) {
    if (_typingChannel != null) return;
    _typingChannel = Supabase.instance.client
        .channel('support-typing-$convId')
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            if (payload['role'] != 'admin' || !mounted) return;
            _adminTypingTimeout?.cancel();
            if (!_adminIsTyping) setState(() => _adminIsTyping = true);
            _adminTypingTimeout = Timer(const Duration(seconds: 3), () {
              if (mounted) setState(() => _adminIsTyping = false);
            });
          },
        )
        .subscribe();
  }

  void _subscribeMessages(String convId) {
    if (_messagesChannel != null) return;
    _messagesChannel = Supabase.instance.client
        .channel('support-messages-$convId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'support_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: convId,
          ),
          callback: (_) {
            if (!mounted) return;
            ref.invalidate(supportMessagesProvider(convId));
            ref.invalidate(supportConversationProvider);
            if (_atBottom) {
              _scrollToBottom();
            } else {
              setState(() => _hasNewMessages = true);
            }
          },
        )
        // Listens for is_read_by_admin updates so customer's sent-message
        // receipts update in real time when admin opens the conversation.
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'support_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: convId,
          ),
          callback: (_) {
            if (!mounted) return;
            ref.invalidate(supportMessagesProvider(convId));
          },
        )
        .subscribe();
  }

  void _onMsgChanged() {
    final conv = _conversation;
    if (conv == null || (conv.isClosed && !_activatingNewChat) || _typingChannel == null) return;
    if (_typingThrottled || _msgCtrl.text.isEmpty) return;
    _typingThrottled = true;
    _typingChannel!.sendBroadcastMessage(
      event: 'typing',
      payload: {'role': 'customer'},
    );
    _typingThrottle = Timer(const Duration(milliseconds: 1500), () {
      _typingThrottled = false;
    });
  }

  Future<void> _initConversation() async {
    try {
      final conv =
          await ref.read(supportChatServiceProvider).getOrCreateConversation();
      if (!mounted) return;
      setState(() {
        _conversation = conv;
        _inputEnabled = !conv.isClosed;
        _activatingNewChat = false;
      });
      ref.invalidate(supportMessagesProvider(conv.id));
      ref.read(supportChatServiceProvider).markRead(conv.id);
      _subscribeTyping(conv.id);
      _subscribeMessages(conv.id);
    } catch (e) {
      debugPrint('[Support] initConversation error: $e');
      if (mounted) setState(() => _activatingNewChat = false);
    }
  }

  void _onFirstLoad(List<SupportMessage> messages) {
    if (_firstLoadDone) return;
    _firstLoadDone = true;
    int? idx;
    for (int i = 0; i < messages.length; i++) {
      if (!messages[i].isReadByCustomer && !messages[i].isFromCustomer) {
        idx = i;
        break;
      }
    }
    setState(() => _unreadFromIndex = idx);
    _scrollToBottom();
  }

  bool _isIdempotentConflict(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('unique') ||
        s.contains('duplicate') ||
        s.contains('23505');
  }

  Future<void> _send() async {
    final msg = _msgCtrl.text.trim();
    if ((msg.isEmpty && _pendingImageBytes == null) ||
        _conversation == null ||
        _sending ||
        !_inputEnabled) {
      return;
    }

    final wasActivating = _activatingNewChat;
    final localId = _newUuid();
    final pending = _PendingMsg(
      localId: localId,
      text: msg,
      imageBytes: _pendingImageBytes,
      attachmentMimeType: _pendingImageMime,
    );
    final imageBytes = _pendingImageBytes;
    final imageMime = _pendingImageMime;
    final imageFilename = _pendingImageFilename;

    setState(() {
      _pendingMsgs.add(pending);
      _pendingImageBytes = null;
      _pendingImageMime = null;
      _pendingImageFilename = null;
    });

    _typingThrottle?.cancel();
    _typingThrottled = false;
    _msgCtrl.clear();
    _scrollToBottom();

    final convId = _conversation!.id;

    try {
      final svc = ref.read(supportChatServiceProvider);
      String? attachPath;

      if (imageBytes != null && imageMime != null) {
        attachPath = await svc.uploadAttachment(
          conversationId: convId,
          bytes: imageBytes,
          filename: imageFilename ?? '$localId.jpg',
          mimeType: imageMime,
        );
      }

      await svc.sendMessage(
        convId,
        msg.isEmpty && attachPath != null ? '📎 Image' : msg,
        messageId: localId,
        attachmentUrl: attachPath,
        attachmentType: imageMime,
      );

      setState(() => _pendingMsgs.remove(pending));
      ref.invalidate(supportMessagesProvider(convId));
      if (wasActivating) {
        // Optimistically mark active. Do NOT clear _activatingNewChat here —
        // keep it true until ref.listen confirms the DB has committed the
        // closed→pending_admin transition, preventing the race where the
        // realtime channel fires a stale closed status and disables input.
        if (mounted) {
          setState(() {
            _conversation = _conversation!.copyWith(status: 'pending_admin');
            _inputEnabled = true;
          });
        }
      } else {
        final updated = await svc.getOrCreateConversation();
        if (mounted) {
          setState(() {
            _conversation = updated;
            _activatingNewChat = false;
            _inputEnabled = !updated.isClosed;
          });
        }
      }
      _scrollToBottom();
    } catch (e) {
      if (_isIdempotentConflict(e)) {
        setState(() {
          _pendingMsgs.remove(pending);
          if (wasActivating) {
            _conversation = _conversation!.copyWith(status: 'pending_admin');
            _inputEnabled = true;
            // Keep _activatingNewChat = true; ref.listen clears it.
          } else {
            _activatingNewChat = false;
          }
        });
        ref.invalidate(supportMessagesProvider(convId));
        return;
      }
      if (mounted) {
        setState(() {
          pending.status = _SendStatus.failed;
          pending.error = e.toString();
        });
      }
    }
  }

  Future<void> _retrySend(_PendingMsg msg) async {
    final convId = _conversation?.id;
    if (convId == null) return;
    final wasActivating = _activatingNewChat;

    setState(() {
      msg.status = _SendStatus.sending;
      msg.error = null;
    });

    try {
      final svc = ref.read(supportChatServiceProvider);
      String? attachPath;

      if (msg.imageBytes != null && msg.attachmentMimeType != null) {
        attachPath = await svc.uploadAttachment(
          conversationId: convId,
          bytes: msg.imageBytes!,
          filename: '${msg.localId}.jpg',
          mimeType: msg.attachmentMimeType!,
        );
      }

      await svc.sendMessage(
        convId,
        msg.text.isEmpty && attachPath != null ? '📎 Image' : msg.text,
        messageId: msg.localId,
        attachmentUrl: attachPath,
        attachmentType: msg.attachmentMimeType,
      );

      setState(() {
        _pendingMsgs.remove(msg);
        if (wasActivating) {
          _conversation = _conversation!.copyWith(status: 'pending_admin');
          _inputEnabled = true;
          // Keep _activatingNewChat = true; ref.listen clears it.
        } else {
          _activatingNewChat = false;
        }
      });
      ref.invalidate(supportMessagesProvider(convId));
      _scrollToBottom();
    } catch (e) {
      if (_isIdempotentConflict(e)) {
        setState(() {
          _pendingMsgs.remove(msg);
          if (wasActivating) {
            _conversation = _conversation!.copyWith(status: 'pending_admin');
            _inputEnabled = true;
            // Keep _activatingNewChat = true; ref.listen clears it.
          } else {
            _activatingNewChat = false;
          }
        });
        ref.invalidate(supportMessagesProvider(convId));
        return;
      }
      if (mounted) {
        setState(() {
          msg.status = _SendStatus.failed;
          msg.error = e.toString();
        });
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    final ext = picked.name.split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
    setState(() {
      _pendingImageBytes = bytes;
      _pendingImageMime = mime;
      _pendingImageFilename = picked.name;
    });
  }

  Future<void> _confirmEndChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'End Chat?',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This will close the conversation. You can reopen it any time by sending a new message.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.error,
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text(
                          'End Chat',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref.read(supportChatServiceProvider).closeConversation();
      ref.invalidate(supportConversationProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Failed to close conversation. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildBody() {
    final conv = _conversation;
    if (conv == null) return const _LoadingView();

    return Column(
      children: [
        if ((!conv.isClosed || _activatingNewChat) && widget.inModal)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.do_not_disturb_on_outlined, size: 14),
              label: const Text('End Chat',
                  style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
              ),
              onPressed: _confirmEndChat,
            ),
          ),
        Expanded(
          child: _activatingNewChat
              ? _NewChatArea(
                  pendingMsgs: _pendingMsgs,
                  scrollCtrl: _scrollCtrl,
                  onRetry: _retrySend,
                )
              : conv.isClosed
              ? _ChatEndedState(
                  onNewChat: () {
                    setState(() {
                      _firstLoadDone = false;
                      _unreadFromIndex = null;
                      _inputEnabled = true;
                      _activatingNewChat = true;
                      _pendingMsgs.clear();
                    });
                    // No RPC here — first sendMessage reopens conv via DB trigger.
                  },
                )
              : Stack(
                  children: [
                    _MessageList(
                      conversationId: conv.id,
                      scrollCtrl: _scrollCtrl,
                      pendingMsgs: _pendingMsgs,
                      unreadFromIndex: _unreadFromIndex,
                      onFirstLoad: _onFirstLoad,
                      onRetry: _retrySend,
                      service: ref.read(supportChatServiceProvider),
                    ),
                    if (_hasNewMessages && !_atBottom)
                      Positioned(
                        bottom: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _NewMsgBadge(onTap: () {
                            setState(() => _hasNewMessages = false);
                            _scrollToBottom();
                          }),
                        ),
                      ),
                  ],
                ),
        ),
        if (_adminIsTyping && (!conv.isClosed || _activatingNewChat))
          const _TypingIndicator('Admin is typing'),
        _ReplyInput(
          ctrl: _msgCtrl,
          sending: _sending,
          pendingImageBytes: _pendingImageBytes,
          disabled: !_inputEnabled,
          onSend: _send,
          onPickImage: _pickImage,
          onClearImage: () => setState(() {
            _pendingImageBytes = null;
            _pendingImageMime = null;
            _pendingImageFilename = null;
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<SupportConversation>>(
      supportConversationProvider,
      (_, next) => next.whenData((conv) {
        if (!mounted) return;
        setState(() {
          _conversation = conv;
          if (!conv.isClosed) {
            // Conversation is confirmed active — clear activation flag and
            // ensure input is enabled. This is the authoritative path out of
            // _activatingNewChat, preventing the race condition where the
            // realtime channel fires before the DB trigger commits the
            // closed → pending_admin status change.
            _activatingNewChat = false;
            _inputEnabled = true;
          } else if (!_activatingNewChat) {
            // Confirmed closed and not mid-activation (e.g. admin closed it).
            _inputEnabled = false;
          }
          // If _activatingNewChat is true and conv is still closed (stale
          // fetch during race window), do nothing — keep input enabled.
        });
      }),
    );

    if (widget.inModal) return _buildBody();

    return Scaffold(
      backgroundColor: AppColors.surfaceVariant,
      appBar: AppBar(
        title: const Text('Support Chat'),
        centerTitle: false,
        actions: [
          if (_conversation != null &&
              (!_conversation!.isClosed || _activatingNewChat))
            IconButton(
              icon: const Icon(Icons.do_not_disturb_on_outlined),
              tooltip: 'End Chat',
              onPressed: _confirmEndChat,
            ),
          if (_conversation != null &&
              (!_conversation!.isClosed || _activatingNewChat))
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _StatusBadge(_conversation!.status),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }
}

// ── Floating dialog container (desktop ≥768px) ────────────────────────────────

class _SupportChatDialog extends StatelessWidget {
  const _SupportChatDialog();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = (size.width * 0.9).clamp(340.0, 680.0);
    final h = (size.height * 0.85).clamp(500.0, size.height * 0.92);

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              behavior: HitTestBehavior.opaque,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: const ColoredBox(color: Color(0x70000000)),
              ),
            ),
          ),
          Center(
            child: SizedBox(
              width: w,
              height: h,
              child: Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                elevation: 24,
                shadowColor: Colors.black38,
                child: Column(
                  children: [
                    const _DialogHeader(),
                    Expanded(
                      child: Builder(
                        builder: (ctx) => MediaQuery.removePadding(
                          context: ctx,
                          removeTop: true,
                          child: const SupportChatScreen(inModal: true),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: AppColors.border, width: 0.8)),
      ),
      padding: const EdgeInsets.only(left: 20, right: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.support_agent_rounded,
                size: 17, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Support Chat',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    fontSize: 15,
                  ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
            style: IconButton.styleFrom(
                foregroundColor: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge(this.status);

  String get _label {
    switch (status) {
      case 'pending_admin':
        return 'Awaiting Response';
      case 'pending_customer':
        return 'Reply Received';
      case 'closed':
        return 'Closed';
      default:
        return 'Open';
    }
  }

  Color get _color {
    switch (status) {
      case 'pending_admin':
        return const Color(0xFFE67E22);
      case 'pending_customer':
        return const Color(0xFF38A169);
      case 'closed':
        return const Color(0xFF9E9E9E);
      default:
        return const Color(0xFF3B82F6);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withAlpha(30),
        border: Border.all(color: _color.withAlpha(100)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _color,
        ),
      ),
    );
  }
}

// ── Message list ──────────────────────────────────────────────────────────────

class _MessageList extends ConsumerWidget {
  final String conversationId;
  final ScrollController scrollCtrl;
  final List<_PendingMsg> pendingMsgs;
  final int? unreadFromIndex;
  final void Function(List<SupportMessage>) onFirstLoad;
  final void Function(_PendingMsg) onRetry;
  final SupportChatService service;

  const _MessageList({
    required this.conversationId,
    required this.scrollCtrl,
    required this.pendingMsgs,
    required this.unreadFromIndex,
    required this.onFirstLoad,
    required this.onRetry,
    required this.service,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(supportMessagesProvider(conversationId));

    return async.when(
      skipLoadingOnReload: true,
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 40, color: AppColors.textHint),
            const SizedBox(height: 8),
            Text('Could not load messages',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () =>
                  ref.invalidate(supportMessagesProvider(conversationId)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (messages) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => onFirstLoad(messages));

        if (messages.isEmpty && pendingMsgs.isEmpty) {
          return const _EmptyConversation();
        }

        final total = messages.length + pendingMsgs.length;

        return ListView.builder(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          itemCount: total,
          itemBuilder: (ctx, i) {
            if (i < messages.length) {
              final msg = messages[i];
              final prev = i > 0 ? messages[i - 1] : null;
              final showDateSep =
                  prev == null || !_sameDay(prev.createdAt, msg.createdAt);
              final showUnread = unreadFromIndex != null && i == unreadFromIndex;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showDateSep) _DateSeparator(msg.createdAt),
                  if (showUnread) const _UnreadDivider(),
                  _MessageBubble(
                    message: msg,
                    service: service,
                  ),
                ],
              );
            }
            final p = pendingMsgs[i - messages.length];
            return _PendingBubble(pending: p, onRetry: () => onRetry(p));
          },
        );
      },
    );
  }

  static bool _sameDay(DateTime a, DateTime b) {
    final al = a.toLocal();
    final bl = b.toLocal();
    return al.year == bl.year &&
        al.month == bl.month &&
        al.day == bl.day;
  }
}

// ── Empty conversation ────────────────────────────────────────────────────────

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.support_agent_rounded,
                  size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              'How can we help?',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Send us a message and our team\nwill get back to you shortly.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.6,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Chat ended state ──────────────────────────────────────────────────────────

class _ChatEndedState extends StatelessWidget {
  final VoidCallback onNewChat;

  const _ChatEndedState({required this.onNewChat});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF718096).withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  size: 36, color: Color(0xFF718096)),
            ),
            const SizedBox(height: 16),
            Text(
              'Chat Closed',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'This conversation has been closed.\nNeed help again?',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.6,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onNewChat,
              icon: const Icon(Icons.add_comment_outlined, size: 16),
              label: const Text('Start a New Chat'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── New chat area (shown immediately after "Start a New Chat") ────────────────

class _NewChatArea extends StatelessWidget {
  final List<_PendingMsg> pendingMsgs;
  final ScrollController scrollCtrl;
  final void Function(_PendingMsg) onRetry;

  const _NewChatArea({
    required this.pendingMsgs,
    required this.scrollCtrl,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (pendingMsgs.isEmpty) return const _EmptyConversation();
    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: pendingMsgs.length,
      itemBuilder: (_, i) {
        final p = pendingMsgs[i];
        return _PendingBubble(pending: p, onRetry: () => onRetry(p));
      },
    );
  }
}

// ── Date separator ────────────────────────────────────────────────────────────

final _dateFmt = DateFormat('MMMM d, yyyy');

class _DateSeparator extends StatelessWidget {
  final DateTime date;

  const _DateSeparator(this.date);

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final local = date.toLocal();
    final isToday = local.year == today.year &&
        local.month == today.month &&
        local.day == today.day;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              isToday ? 'Today' : _dateFmt.format(local),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textHint,
                    fontSize: 11,
                  ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

// ── Unread divider ────────────────────────────────────────────────────────────

class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Expanded(
              child: Divider(color: Color(0xFF3B82F6), thickness: 0.8)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withAlpha(20),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: const Color(0xFF3B82F6).withAlpha(80)),
            ),
            child: const Text(
              'New Messages',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3B82F6),
              ),
            ),
          ),
          const Expanded(
              child: Divider(color: Color(0xFF3B82F6), thickness: 0.8)),
        ],
      ),
    );
  }
}

// ── New message badge ─────────────────────────────────────────────────────────

class _NewMsgBadge extends StatelessWidget {
  final VoidCallback onTap;

  const _NewMsgBadge({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
                color: Color(0x30000000),
                blurRadius: 8,
                offset: Offset(0, 3)),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_downward_rounded,
                size: 13, color: Colors.white),
            SizedBox(width: 4),
            Text('New message',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────

const _kAdminBubbleColor = Colors.white;

class _MessageBubble extends StatelessWidget {
  final SupportMessage message;
  final SupportChatService service;

  const _MessageBubble({required this.message, required this.service});

  @override
  Widget build(BuildContext context) {
    final isCustomer = message.isFromCustomer;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment:
            isCustomer ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          child: Column(
            crossAxisAlignment: isCustomer
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  isCustomer ? 'You' : 'Support',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF718096),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isCustomer ? AppColors.primary : _kAdminBubbleColor,
                  border: isCustomer
                      ? null
                      : Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: isCustomer
                        ? const Radius.circular(16)
                        : const Radius.circular(4),
                    bottomRight: isCustomer
                        ? const Radius.circular(4)
                        : const Radius.circular(16),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0A000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.hasContext)
                      _ContextChipCustomer(
                        contextType: message.contextType!,
                        contextId: message.contextId!,
                        isAdmin: !isCustomer,
                      ),
                    if (message.hasContext && message.message.isNotEmpty)
                      const SizedBox(height: 6),
                    if (message.hasAttachment)
                      _AttachmentViewCustomer(
                        storagePath: message.attachmentUrl!,
                        mimeType: message.attachmentType,
                        service: service,
                        isAdmin: !isCustomer,
                      ),
                    if (message.hasAttachment && message.message.isNotEmpty)
                      const SizedBox(height: 6),
                    if (message.message.isNotEmpty)
                      Text(
                        message.message,
                        style: TextStyle(
                          fontSize: 13,
                          color: isCustomer
                              ? Colors.white
                              : AppColors.textPrimary,
                          height: 1.5,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message.formattedTime,
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFFA0AEC0)),
                    ),
                    if (isCustomer) ...[
                      const SizedBox(width: 4),
                      Icon(
                        message.isReadByAdmin
                            ? Icons.done_all_rounded
                            : Icons.done_rounded,
                        size: 13,
                        color: message.isReadByAdmin
                            ? const Color(0xFF38A169)
                            : const Color(0xFFCBD5E0),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pending bubble ────────────────────────────────────────────────────────────

class _PendingBubble extends StatelessWidget {
  final _PendingMsg pending;
  final VoidCallback onRetry;

  const _PendingBubble({required this.pending, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isFailed = pending.status == _SendStatus.failed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Opacity(
              opacity: isFailed ? 0.7 : 0.6,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isFailed ? AppColors.error : AppColors.primary,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(4),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0A000000),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (pending.imageBytes != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            pending.imageBytes!,
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                        ),
                      if (pending.text.isNotEmpty)
                        Text(
                          pending.text,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white,
                            height: 1.5,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 4),
            child: isFailed
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 12, color: AppColors.error),
                      const SizedBox(width: 4),
                      const Text('Failed',
                          style: TextStyle(
                              fontSize: 10, color: AppColors.error)),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: onRetry,
                        child: const Text('Retry',
                            style: TextStyle(
                                fontSize: 10,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Color(0xFFA0AEC0)),
                      ),
                      SizedBox(width: 4),
                      Text('Sending…',
                          style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFFA0AEC0))),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Context chip (customer side) ──────────────────────────────────────────────

class _ContextChipCustomer extends StatelessWidget {
  final String contextType;
  final String contextId;
  final bool isAdmin;

  const _ContextChipCustomer({
    required this.contextType,
    required this.contextId,
    this.isAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    final isBooking = contextType == 'booking';
    final baseColor = isAdmin
        ? const Color(0xFFE2E8F0)
        : const Color(0xFFEBF8FF);
    final textColor =
        isAdmin ? const Color(0xFF4A5568) : const Color(0xFF2B6CB0);

    return GestureDetector(
      onTap: () {
        if (isBooking) {
          context.push('/notification-booking/$contextId');
        } else {
          context.push('/refund-queries/$contextId');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isBooking
                  ? Icons.receipt_long_outlined
                  : Icons.currency_rupee_outlined,
              size: 13,
              color: textColor,
            ),
            const SizedBox(width: 5),
            Text(
              isBooking ? 'View Booking' : 'View Refund',
              style: TextStyle(
                fontSize: 11,
                color: textColor,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Attachment view (customer side) ───────────────────────────────────────────

class _AttachmentViewCustomer extends StatefulWidget {
  final String storagePath;
  final String? mimeType;
  final SupportChatService service;
  final bool isAdmin;

  const _AttachmentViewCustomer({
    required this.storagePath,
    required this.mimeType,
    required this.service,
    this.isAdmin = false,
  });

  @override
  State<_AttachmentViewCustomer> createState() =>
      _AttachmentViewCustomerState();
}

class _AttachmentViewCustomerState extends State<_AttachmentViewCustomer> {
  String? _signedUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = await widget.service.getSignedAttachmentUrl(widget.storagePath);
    if (mounted) {
      setState(() {
        _signedUrl = url;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isImage =
        widget.mimeType != null && widget.mimeType!.startsWith('image/');

    if (_loading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: AppColors.textHint,
        ),
      );
    }

    if (_signedUrl == null) {
      return const Text('⚠ Attachment unavailable',
          style: TextStyle(
              fontSize: 11,
              color: AppColors.textHint));
    }

    if (isImage) {
      return GestureDetector(
        onTap: () => _openUrl(_signedUrl!),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            _signedUrl!,
            width: 180,
            height: 160,
            fit: BoxFit.cover,
            errorBuilder: (ctx, err, _) => const Text('⚠ Image failed',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textHint)),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _openUrl(_signedUrl!),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFC),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.insert_drive_file_outlined,
              size: 16,
              color: Color(0xFF718096),
            ),
            const SizedBox(width: 6),
            Text(
              'View Attachment',
              style: TextStyle(
                fontSize: 12,
                color: widget.isAdmin
                    ? AppColors.textPrimary
                    : AppColors.primary,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}

// ── Reply input ───────────────────────────────────────────────────────────────

class _ReplyInput extends StatelessWidget {
  final TextEditingController ctrl;
  final bool sending;
  final bool disabled;
  final Uint8List? pendingImageBytes;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final VoidCallback onClearImage;

  const _ReplyInput({
    required this.ctrl,
    required this.sending,
    required this.pendingImageBytes,
    required this.onSend,
    required this.onPickImage,
    required this.onClearImage,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pendingImageBytes != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(pendingImageBytes!,
                        width: 48, height: 48, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Image attached',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 16, color: AppColors.textHint),
                    onPressed: onClearImage,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 8,
              top: 8,
              bottom: MediaQuery.of(context).padding.bottom + 8,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: disabled ? null : onPickImage,
                  icon: const Icon(Icons.image_outlined),
                  color: disabled
                      ? AppColors.textHint.withAlpha(80)
                      : pendingImageBytes != null
                          ? AppColors.primary
                          : AppColors.textHint,
                  iconSize: 22,
                  tooltip: 'Add image',
                  padding: const EdgeInsets.all(4),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    enabled: !disabled,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: disabled
                          ? 'Start a new chat to continue…'
                          : 'Type a message…',
                      hintStyle: const TextStyle(
                          color: AppColors.textHint, fontSize: 14),
                      border: const OutlineInputBorder(
                        borderRadius:
                            BorderRadius.all(Radius.circular(24)),
                        borderSide:
                            BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: const OutlineInputBorder(
                        borderRadius:
                            BorderRadius.all(Radius.circular(24)),
                        borderSide:
                            BorderSide(color: AppColors.border),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(24)),
                        borderSide: BorderSide(
                            color: AppColors.border.withAlpha(100)),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius:
                            BorderRadius.all(Radius.circular(24)),
                        borderSide: BorderSide(
                            color: AppColors.primary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
                    onSubmitted: disabled ? null : (_) => onSend(),
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: sending
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          onPressed: disabled ? null : onSend,
                          icon: const Icon(Icons.send_rounded),
                          color: disabled
                              ? AppColors.textHint.withAlpha(80)
                              : AppColors.primary,
                          iconSize: 22,
                          tooltip: 'Send',
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Typing indicator ──────────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  final String label;

  const _TypingIndicator(this.label);

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> {
  static const _frames = ['', '.', '..', '...'];
  int _frame = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (mounted) setState(() => _frame = (_frame + 1) % _frames.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 2),
      child: Text(
        '${widget.label}${_frames[_frame]}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textHint,
              fontStyle: FontStyle.italic,
              fontSize: 12,
            ),
      ),
    );
  }
}

// ── Loading view ──────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator(strokeWidth: 2));
  }
}
