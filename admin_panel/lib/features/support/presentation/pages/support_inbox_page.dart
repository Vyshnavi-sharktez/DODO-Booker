import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/admin_search_bar.dart';
import '../../../settings/application/providers/settings_providers.dart';
import '../../application/support_providers.dart';
import '../../data/support_repository.dart';
import '../../domain/models/support_conversation.dart';
import '../../domain/models/support_message.dart';

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
  final String? contextType;
  final String? contextId;
  _SendStatus status = _SendStatus.sending;
  String? error;

  _PendingMsg({
    required this.localId,
    required this.text,
    this.imageBytes,
    this.attachmentMimeType,
    this.contextType,
    this.contextId,
  });
}

// ── Context reference ─────────────────────────────────────────────────────────

class _ContextRef {
  final String type;
  final String id;
  final String label;

  const _ContextRef(
      {required this.type, required this.id, required this.label});
}

// ── Canned replies ────────────────────────────────────────────────────────────

const _kCannedReplies = [
  'Thank you for reaching out. Our team is looking into this and will get back to you shortly.',
  'We have received your request and will resolve it within 24 hours.',
  'We apologize for the inconvenience. Could you please provide more details about the issue?',
  'Could you please share your booking number so we can assist you better?',
  'Your issue has been escalated to our technical team.',
  'Your issue has been resolved. Please let us know if you need any further assistance.',
];

// ── Pending file ──────────────────────────────────────────────────────────────

class _PendingFile {
  final Uint8List bytes;
  final String filename;
  final String mimeType;

  const _PendingFile(
      {required this.bytes, required this.filename, required this.mimeType});
}

// ─────────────────────────────────────────────────────────────────────────────
// SupportInboxPage
// ─────────────────────────────────────────────────────────────────────────────

class SupportInboxPage extends ConsumerStatefulWidget {
  const SupportInboxPage({super.key});

  @override
  ConsumerState<SupportInboxPage> createState() => _SupportInboxPageState();
}

class _SupportInboxPageState extends ConsumerState<SupportInboxPage> {
  static const _statusTabs = [
    ('active', 'Active'),
    ('pending_admin', 'Needs Reply'),
    ('pending_customer', 'Awaiting'),
    ('closed', 'Closed'),
    ('all', 'All'),
  ];

  @override
  void dispose() {
    ref.read(selectedSupportConversationIdProvider.notifier).state = null;
    ref.read(selectedSupportHistoryModeProvider.notifier).state = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentStatus = ref.watch(supportStatusFilterProvider);
    final asyncConversations = ref.watch(supportConversationsProvider);
    final selectedId = ref.watch(selectedSupportConversationIdProvider);
    final viewHistory = ref.watch(selectedSupportHistoryModeProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          SizedBox(
            width: 340,
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Support Chat',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A202C),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              ref.invalidate(supportConversationsProvider),
                          icon: const Icon(Icons.refresh_rounded),
                          tooltip: 'Refresh',
                          iconSize: 18,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _statusTabs.map((tab) {
                          final (key, label) = tab;
                          final selected = currentStatus == key;
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: ChoiceChip(
                              label: Text(label),
                              selected: selected,
                              onSelected: (_) => ref
                                  .read(supportStatusFilterProvider.notifier)
                                  .state = key,
                              selectedColor:
                                  AppColors.primary.withAlpha(25),
                              labelStyle: TextStyle(
                                fontSize: 11,
                                color: selected
                                    ? AppColors.primary
                                    : const Color(0xFF718096),
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                              side: BorderSide(
                                color: selected
                                    ? AppColors.primary.withAlpha(100)
                                    : const Color(0xFFE2E8F0),
                              ),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              visualDensity: VisualDensity.compact,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: AdminSearchBar(
                      hintText: 'Search by name or phone…',
                      onChanged: (v) => ref
                          .read(supportSearchQueryProvider.notifier)
                          .state = v,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Divider(height: 1),
                  Expanded(
                    child: asyncConversations.when(
                      skipLoadingOnReload: true,
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Color(0xFFE53E3E)),
                              const SizedBox(height: 8),
                              Text(e.toString(),
                                  style: const TextStyle(fontSize: 12),
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: () => ref
                                    .invalidate(supportConversationsProvider),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      data: (conversations) => conversations.isEmpty
                          ? const _EmptyListView()
                          : ListView.separated(
                              itemCount: conversations.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (ctx, i) => _ConversationTile(
                                conversation: conversations[i],
                                isSelected: conversations[i].id == selectedId &&
                                    conversations[i].viewAsHistory ==
                                        viewHistory,
                                onTap: () {
                                  ref
                                      .read(
                                          selectedSupportConversationIdProvider
                                              .notifier)
                                      .state = conversations[i].id;
                                  ref
                                      .read(selectedSupportHistoryModeProvider
                                          .notifier)
                                      .state = conversations[i].viewAsHistory;
                                },
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: selectedId == null
                ? const _EmptySelectionView()
                : _ChatPane(
                    key: ValueKey((selectedId, viewHistory)),
                    conversationId: selectedId,
                    viewHistory: viewHistory,
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Conversation list tile ─────────────────────────────────────────────────────

class _ConversationTile extends StatelessWidget {
  final SupportConversation conversation;
  final bool isSelected;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.conversation,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final hasUnread = c.unreadAdminCount > 0 && !c.viewAsHistory;
    final timeStr = c.lastMessageAt != null
        ? DateFormat('d MMM').format(c.lastMessageAt!.toLocal())
        : DateFormat('d MMM').format(c.createdAt.toLocal());

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isSelected
            ? AppColors.primary.withAlpha(12)
            : c.viewAsHistory
                ? const Color(0xFFFFF8E1)
                : hasUnread
                    ? const Color(0xFFFFFAF0)
                    : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: hasUnread
                  ? Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE53E3E),
                        shape: BoxShape.circle,
                      ),
                    )
                  : const SizedBox(width: 8),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.customerName ?? 'Customer',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: hasUnread || isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: const Color(0xFF1A202C),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        timeStr,
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFFA0AEC0)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (c.customerPhone != null)
                    Text(
                      c.customerPhone!,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF718096)),
                    ),
                  if (c.lastMessagePreview != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      c.lastMessagePreview!,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF718096)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      c.viewAsHistory
                          ? _StatusBadge(
                              label: 'Prior Episode',
                              color: const Color(0xFF8B6914),
                            )
                          : _StatusBadge(
                              label: c.statusLabel, color: c.statusColor),
                      if (hasUnread) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE53E3E),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${c.unreadAdminCount}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
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

// ── Chat pane ──────────────────────────────────────────────────────────────────

class _ChatPane extends ConsumerStatefulWidget {
  final String conversationId;
  final bool viewHistory;

  const _ChatPane({
    super.key,
    required this.conversationId,
    this.viewHistory = false,
  });

  @override
  ConsumerState<_ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends ConsumerState<_ChatPane> {
  final _scrollCtrl = ScrollController();
  bool _markingRead = false;
  bool _firstLoadDone = false;
  int? _unreadFromIndex;
  bool _atBottom = true;
  bool _hasNewMessages = false;
  final List<_PendingMsg> _pendingMsgs = [];

  RealtimeChannel? _typingChannel;
  RealtimeChannel? _readStatusChannel;
  bool _customerIsTyping = false;
  Timer? _customerTypingTimeout;
  bool _typingThrottled = false;

  bool _searchActive = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    if (!widget.viewHistory) {
      _subscribeTyping();
      _subscribeReadStatus();
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _customerTypingTimeout?.cancel();
    if (_typingChannel != null) {
      Supabase.instance.client.removeChannel(_typingChannel!);
    }
    if (_readStatusChannel != null) {
      Supabase.instance.client.removeChannel(_readStatusChannel!);
    }
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

  void _subscribeTyping() {
    _typingChannel = Supabase.instance.client
        .channel('support-typing-${widget.conversationId}')
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            if (payload['role'] != 'customer' || !mounted) return;
            _customerTypingTimeout?.cancel();
            if (!_customerIsTyping) {
              setState(() => _customerIsTyping = true);
            }
            _customerTypingTimeout = Timer(const Duration(seconds: 3), () {
              if (mounted) setState(() => _customerIsTyping = false);
            });
          },
        )
        .subscribe();
  }

  // Listens for is_read_by_customer updates so admin's sent-message receipts
  // update in real time when the customer opens the conversation.
  void _subscribeReadStatus() {
    _readStatusChannel = Supabase.instance.client
        .channel('support-read-status-${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'support_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (_) {
            if (!mounted) return;
            ref.invalidate(supportMessagesProvider(widget.conversationId));
          },
        )
        .subscribe();
  }

  void _sendTyping() {
    if (_typingThrottled) return;
    _typingThrottled = true;
    _typingChannel?.sendBroadcastMessage(
      event: 'typing',
      payload: {'role': 'admin'},
    );
    Future.delayed(
        const Duration(milliseconds: 1500), () => _typingThrottled = false);
  }

  void _onFirstLoad(List<SupportMessage> messages) {
    if (_firstLoadDone) return;
    _firstLoadDone = true;
    int? idx;
    for (int i = 0; i < messages.length; i++) {
      if (!messages[i].isReadByAdmin && !messages[i].isFromAdmin) {
        idx = i;
        break;
      }
    }
    setState(() => _unreadFromIndex = idx);
    if (!widget.viewHistory) _markReadOnOpen();
    _scrollToBottom();
  }

  Future<void> _markReadOnOpen() async {
    if (_markingRead) return;
    _markingRead = true;
    try {
      await ref
          .read(supportRepositoryProvider)
          .markConversationRead(widget.conversationId);
      ref.invalidate(supportConversationsProvider);
      ref.invalidate(
          supportConversationDetailProvider(widget.conversationId));
    } catch (_) {
    } finally {
      _markingRead = false;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _isIdempotentConflict(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('unique') ||
        s.contains('duplicate') ||
        s.contains('23505');
  }

  Future<void> _sendMessage({
    required String text,
    _PendingFile? file,
    _ContextRef? context,
  }) async {
    final localId = _newUuid();
    final pending = _PendingMsg(
      localId: localId,
      text: text,
      imageBytes: (file != null && file.mimeType.startsWith('image/'))
          ? file.bytes
          : null,
      attachmentMimeType: file?.mimeType,
      contextType: context?.type,
      contextId: context?.id,
    );
    setState(() => _pendingMsgs.add(pending));
    _scrollToBottom();

    try {
      final repo = ref.read(supportRepositoryProvider);
      String? attachPath;
      if (file != null) {
        attachPath = await repo.uploadAttachment(
          conversationId: widget.conversationId,
          bytes: file.bytes,
          filename: file.filename,
          mimeType: file.mimeType,
        );
      }
      await repo.sendAdminMessage(
        widget.conversationId,
        text.isEmpty && attachPath != null ? '📎 Attachment' : text,
        messageId: localId,
        attachmentUrl: attachPath,
        attachmentType: file?.mimeType,
        contextType: context?.type,
        contextId: context?.id,
      );
      setState(() => _pendingMsgs.remove(pending));
      ref.invalidate(supportMessagesProvider(widget.conversationId));
      ref.invalidate(supportConversationsProvider);
      _scrollToBottom();
    } catch (e) {
      if (_isIdempotentConflict(e)) {
        setState(() => _pendingMsgs.remove(pending));
        ref.invalidate(supportMessagesProvider(widget.conversationId));
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
    setState(() {
      msg.status = _SendStatus.sending;
      msg.error = null;
    });
    try {
      final repo = ref.read(supportRepositoryProvider);
      String? attachPath;
      if (msg.imageBytes != null && msg.attachmentMimeType != null) {
        attachPath = await repo.uploadAttachment(
          conversationId: widget.conversationId,
          bytes: msg.imageBytes!,
          filename: '${msg.localId}.jpg',
          mimeType: msg.attachmentMimeType!,
        );
      }
      await repo.sendAdminMessage(
        widget.conversationId,
        msg.text.isEmpty && attachPath != null ? '📎 Attachment' : msg.text,
        messageId: msg.localId,
        attachmentUrl: attachPath,
        attachmentType: msg.attachmentMimeType,
        contextType: msg.contextType,
        contextId: msg.contextId,
      );
      setState(() => _pendingMsgs.remove(msg));
      ref.invalidate(supportMessagesProvider(widget.conversationId));
      ref.invalidate(supportConversationsProvider);
      _scrollToBottom();
    } catch (e) {
      if (_isIdempotentConflict(e)) {
        setState(() => _pendingMsgs.remove(msg));
        ref.invalidate(supportMessagesProvider(widget.conversationId));
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

  @override
  Widget build(BuildContext context) {
    final asyncConv =
        ref.watch(supportConversationDetailProvider(widget.conversationId));

    if (!widget.viewHistory) {
      ref.listen<AsyncValue<List<SupportMessage>>>(
        supportMessagesProvider(widget.conversationId),
        (prev, next) {
          next.whenData((msgs) {
            final prevCount = prev?.valueOrNull?.length ?? 0;
            if (msgs.length > prevCount) {
              if (_atBottom) {
                _scrollToBottom();
              } else {
                setState(() => _hasNewMessages = true);
              }
            }
          });
        },
      );
    }

    return asyncConv.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e',
            style: const TextStyle(color: Color(0xFFE53E3E))),
      ),
      data: (conv) {
        if (conv == null) {
          return const Center(child: Text('Conversation not found.'));
        }
        return _buildChat(conv);
      },
    );
  }

  Widget _buildChat(SupportConversation conv) {
    return Column(
      children: [
        _ChatHeader(
          conversation: conv,
          searchActive: _searchActive,
          onDeselect: () {
            ref.read(selectedSupportConversationIdProvider.notifier).state =
                null;
            ref.read(selectedSupportHistoryModeProvider.notifier).state = false;
          },
          onClose: (conv.isClosed || widget.viewHistory)
              ? null
              : () => _closeConversation(conv.id),
          onRefresh: () {
            ref.invalidate(
                supportConversationDetailProvider(widget.conversationId));
            ref.invalidate(supportConversationsProvider);
            if (widget.viewHistory) {
              ref.invalidate(
                  supportHistoricalMessagesProvider(widget.conversationId));
            } else {
              ref.invalidate(
                  supportMessagesProvider(widget.conversationId));
            }
          },
          onToggleSearch: () => setState(() {
            _searchActive = !_searchActive;
            if (!_searchActive) _searchQuery = '';
          }),
        ),
        if (_searchActive)
          _SearchBar(
            onChanged: (q) => setState(() => _searchQuery = q),
            onClose: () => setState(() {
              _searchActive = false;
              _searchQuery = '';
            }),
          ),
        const Divider(height: 1),
        Expanded(
          child: Stack(
            children: [
              _MessageList(
                conversationId: widget.conversationId,
                scrollCtrl: _scrollCtrl,
                pendingMsgs: widget.viewHistory ? const [] : _pendingMsgs,
                unreadFromIndex: _unreadFromIndex,
                searchQuery: _searchQuery,
                onFirstLoad: _onFirstLoad,
                onRetry: _retrySend,
                repository: ref.read(supportRepositoryProvider),
                viewHistory: widget.viewHistory,
              ),
              if (!widget.viewHistory && _hasNewMessages && !_atBottom)
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: _NewMsgFab(onTap: () {
                    setState(() => _hasNewMessages = false);
                    _scrollToBottom();
                  }),
                ),
            ],
          ),
        ),
        if (!widget.viewHistory && _customerIsTyping)
          const _TypingIndicatorBar(label: 'Customer'),
        if (widget.viewHistory)
          _HistoryBanner(reopenedAt: conv.currentEpisodeStartedAt)
        else if (conv.isClosed)
          _ClosedBanner()
        else ...[
          _AutoCloseBanner(
            conversation: conv,
            settings: ref.watch(settingsNotifierProvider).valueOrNull ?? {},
          ),
          const Divider(height: 1),
          _ReplyInput(
            conversationId: conv.id,
            customerId: conv.customerId,
            onSend: _sendMessage,
            onTyping: _sendTyping,
            repository: ref.read(supportRepositoryProvider),
          ),
        ],
      ],
    );
  }

  Future<void> _closeConversation(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Close Conversation?'),
        content: const Text(
            'The customer can reopen it by sending another message.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Close')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(supportRepositoryProvider).closeConversation(id);
      ref.read(selectedSupportConversationIdProvider.notifier).state = null;
      ref.invalidate(supportConversationsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to close: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }
}

// ── Chat header ────────────────────────────────────────────────────────────────

class _ChatHeader extends StatelessWidget {
  final SupportConversation conversation;
  final bool searchActive;
  final VoidCallback onDeselect;
  final VoidCallback? onClose;
  final VoidCallback onRefresh;
  final VoidCallback onToggleSearch;

  const _ChatHeader({
    required this.conversation,
    required this.searchActive,
    required this.onDeselect,
    required this.onClose,
    required this.onRefresh,
    required this.onToggleSearch,
  });

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final initials = (c.customerName?.isNotEmpty == true)
        ? c.customerName![0].toUpperCase()
        : 'C';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white,
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withAlpha(20),
            child: Text(
              initials,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        c.customerName ?? 'Customer',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A202C),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _StatusBadge(label: c.statusLabel, color: c.statusColor),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => context
                          .go('/dashboard/customers/${c.customerId}'),
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Profile',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600)),
                            Icon(Icons.open_in_new_rounded,
                                size: 11, color: AppColors.primary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 12,
                  children: [
                    if (c.customerPhone != null)
                      _InfoChip(
                          icon: Icons.phone_outlined,
                          text: c.customerPhone!),
                    if (c.customerEmail != null)
                      _InfoChip(
                          icon: Icons.email_outlined,
                          text: c.customerEmail!),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onToggleSearch,
            icon: Icon(searchActive
                ? Icons.search_off_rounded
                : Icons.search_rounded),
            tooltip: searchActive ? 'Close search' : 'Search messages',
            iconSize: 18,
            color: searchActive
                ? AppColors.primary
                : const Color(0xFF718096),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: onDeselect,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Deselect',
            iconSize: 18,
            color: const Color(0xFF718096),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
          ),
          if (onClose != null)
            OutlinedButton.icon(
              onPressed: onClose,
              icon:
                  const Icon(Icons.do_not_disturb_on_outlined, size: 14),
              label: const Text('Close'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: const Color(0xFF718096)),
        const SizedBox(width: 3),
        Text(text,
            style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
      ],
    );
  }
}

// ── Search bar ─────────────────────────────────────────────────────────────────

class _SearchBar extends StatefulWidget {
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  const _SearchBar({required this.onChanged, required this.onClose});

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search messages…',
                hintStyle:
                    const TextStyle(fontSize: 13, color: Color(0xFFA0AEC0)),
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _ctrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          _ctrl.clear();
                          widget.onChanged('');
                          setState(() {});
                        },
                        tooltip: 'Clear',
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
              onChanged: (v) {
                setState(() {});
                widget.onChanged(v);
              },
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: widget.onClose,
            child: const Text('Done',
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ── Message list ───────────────────────────────────────────────────────────────

class _MessageList extends ConsumerWidget {
  final String conversationId;
  final ScrollController scrollCtrl;
  final List<_PendingMsg> pendingMsgs;
  final int? unreadFromIndex;
  final String searchQuery;
  final void Function(List<SupportMessage>) onFirstLoad;
  final void Function(_PendingMsg) onRetry;
  final SupportRepository repository;
  final bool viewHistory;

  const _MessageList({
    required this.conversationId,
    required this.scrollCtrl,
    required this.pendingMsgs,
    required this.unreadFromIndex,
    required this.searchQuery,
    required this.onFirstLoad,
    required this.onRetry,
    required this.repository,
    this.viewHistory = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncMessages = viewHistory
        ? ref.watch(supportHistoricalMessagesProvider(conversationId))
        : ref.watch(supportMessagesProvider(conversationId));

    return asyncMessages.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Could not load messages: $e',
            style: const TextStyle(color: Color(0xFFE53E3E))),
      ),
      data: (messages) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => onFirstLoad(messages));

        final filtered = searchQuery.isEmpty
            ? messages
            : messages
                .where((m) => m.message
                    .toLowerCase()
                    .contains(searchQuery.toLowerCase()))
                .toList();

        if (filtered.isEmpty && pendingMsgs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.chat_bubble_outline,
                    size: 40, color: Color(0xFFCBD5E0)),
                const SizedBox(height: 12),
                Text(
                  viewHistory ? 'No prior messages.' : 'No messages yet.',
                  style: const TextStyle(color: Color(0xFF718096)),
                ),
                const SizedBox(height: 4),
                if (!viewHistory)
                  const Text('Send a message to start the conversation.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFA0AEC0))),
              ],
            ),
          );
        }

        final total = filtered.length + pendingMsgs.length;

        return ListView.separated(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(16),
          itemCount: total,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (ctx, i) {
            if (i < filtered.length) {
              final msg = filtered[i];
              final originalIndex = messages.indexOf(msg);
              final showDivider = unreadFromIndex != null &&
                  searchQuery.isEmpty &&
                  originalIndex == unreadFromIndex;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showDivider) const _UnreadDivider(),
                  _MessageBubble(
                    message: msg,
                    searchQuery: searchQuery,
                    repository: repository,
                  ),
                ],
              );
            }
            final p = pendingMsgs[i - filtered.length];
            return _PendingBubble(pending: p, onRetry: () => onRetry(p));
          },
        );
      },
    );
  }
}

// ── Message bubble ─────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final SupportMessage message;
  final String searchQuery;
  final SupportRepository repository;

  const _MessageBubble({
    required this.message,
    required this.searchQuery,
    required this.repository,
  });

  @override
  Widget build(BuildContext context) {
    final isAdmin = message.isFromAdmin;
    final dimmed = searchQuery.isNotEmpty &&
        !message.message
            .toLowerCase()
            .contains(searchQuery.toLowerCase()) &&
        !message.hasAttachment;

    return Opacity(
      opacity: dimmed ? 0.35 : 1.0,
      child: Align(
        alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.55,
          ),
          child: Column(
            crossAxisAlignment: isAdmin
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  isAdmin ? 'You (Admin)' : 'Customer',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF718096)),
                ),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isAdmin ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: isAdmin
                        ? const Radius.circular(16)
                        : const Radius.circular(4),
                    bottomRight: isAdmin
                        ? const Radius.circular(4)
                        : const Radius.circular(16),
                  ),
                  border: isAdmin
                      ? null
                      : Border.all(color: const Color(0xFFE2E8F0)),
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
                      _ContextChip(
                        contextType: message.contextType!,
                        contextId: message.contextId!,
                        isAdmin: isAdmin,
                        repository: repository,
                      ),
                    if (message.hasContext && message.message.isNotEmpty)
                      const SizedBox(height: 6),
                    if (message.hasAttachment)
                      _AttachmentView(
                        storagePath: message.attachmentUrl!,
                        mimeType: message.attachmentType,
                        isAdmin: isAdmin,
                        repository: repository,
                      ),
                    if (message.hasAttachment && message.message.isNotEmpty)
                      const SizedBox(height: 6),
                    if (message.message.isNotEmpty)
                      searchQuery.isEmpty
                          ? Text(
                              message.message,
                              style: TextStyle(
                                fontSize: 13,
                                color: isAdmin
                                    ? Colors.white
                                    : const Color(0xFF2D3748),
                                height: 1.5,
                              ),
                            )
                          : _HighlightedText(
                              text: message.message,
                              query: searchQuery,
                              baseStyle: TextStyle(
                                fontSize: 13,
                                color: isAdmin
                                    ? Colors.white
                                    : const Color(0xFF2D3748),
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
                    if (isAdmin) ...[
                      const SizedBox(width: 4),
                      _ReadReceipt(
                        isReadByCustomer: message.isReadByCustomer,
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

// ── Pending bubble ─────────────────────────────────────────────────────────────

class _PendingBubble extends StatelessWidget {
  final _PendingMsg pending;
  final VoidCallback onRetry;

  const _PendingBubble({required this.pending, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isFailed = pending.status == _SendStatus.failed;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.55,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('You (Admin)',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF718096))),
            ),
            const SizedBox(height: 3),
            Opacity(
              opacity: isFailed ? 0.7 : 0.6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isFailed
                      ? const Color(0xFFE53E3E)
                      : AppColors.primary,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (pending.imageBytes != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(pending.imageBytes!,
                            width: 120, height: 120, fit: BoxFit.cover),
                      ),
                    if (pending.contextType != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              pending.contextType == 'booking'
                                  ? Icons.receipt_long_outlined
                                  : Icons.currency_rupee_outlined,
                              size: 12,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              pending.contextType == 'booking'
                                  ? 'Booking linked'
                                  : 'Refund linked',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      if (pending.text.isNotEmpty)
                        const SizedBox(height: 6),
                    ],
                    if (pending.text.isNotEmpty)
                      Text(pending.text,
                          style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white,
                              height: 1.5)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 3),
            if (isFailed)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 12, color: Color(0xFFE53E3E)),
                  const SizedBox(width: 4),
                  const Text('Failed',
                      style: TextStyle(
                          fontSize: 10, color: Color(0xFFE53E3E))),
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
            else
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: Color(0xFFA0AEC0)),
                  ),
                  SizedBox(width: 4),
                  Text('Sending…',
                      style: TextStyle(
                          fontSize: 10, color: Color(0xFFA0AEC0))),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ── Read receipt ───────────────────────────────────────────────────────────────

// Shown only on admin-sent messages; reflects whether the customer has read them.
class _ReadReceipt extends StatelessWidget {
  final bool isReadByCustomer;

  const _ReadReceipt({required this.isReadByCustomer});

  @override
  Widget build(BuildContext context) {
    return Icon(
      isReadByCustomer ? Icons.done_all_rounded : Icons.done_rounded,
      size: 13,
      color: isReadByCustomer
          ? const Color(0xFF38A169)
          : const Color(0xFFCBD5E0),
    );
  }
}

// ── Unread divider ─────────────────────────────────────────────────────────────

class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Expanded(
              child: Divider(color: Color(0xFFE53E3E), thickness: 0.8)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFE53E3E).withAlpha(20),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: const Color(0xFFE53E3E).withAlpha(80)),
            ),
            child: const Text(
              'New Messages',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE53E3E),
              ),
            ),
          ),
          const Expanded(
              child: Divider(color: Color(0xFFE53E3E), thickness: 0.8)),
        ],
      ),
    );
  }
}

// ── New message FAB ────────────────────────────────────────────────────────────

class _NewMsgFab extends StatelessWidget {
  final VoidCallback onTap;

  const _NewMsgFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

// ── Typing indicator bar ───────────────────────────────────────────────────────

class _TypingIndicatorBar extends StatelessWidget {
  final String label;

  const _TypingIndicatorBar({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: Color(0xFFA0AEC0)),
          ),
          const SizedBox(width: 8),
          Text(
            '$label is typing…',
            style:
                const TextStyle(fontSize: 12, color: Color(0xFF718096)),
          ),
        ],
      ),
    );
  }
}

// ── Context chip (lazy fetch) ─────────────────────────────────────────────────

class _ContextChip extends StatefulWidget {
  final String contextType;
  final String contextId;
  final bool isAdmin;
  final SupportRepository repository;

  const _ContextChip({
    required this.contextType,
    required this.contextId,
    required this.isAdmin,
    required this.repository,
  });

  @override
  State<_ContextChip> createState() => _ContextChipState();
}

class _ContextChipState extends State<_ContextChip> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = widget.contextType == 'booking'
          ? await widget.repository.fetchBookingById(widget.contextId)
          : await widget.repository.fetchRefundById(widget.contextId);
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBooking = widget.contextType == 'booking';
    final baseColor = widget.isAdmin
        ? Colors.white.withAlpha(40)
        : const Color(0xFFEBF8FF);
    final textColor =
        widget.isAdmin ? Colors.white : const Color(0xFF2B6CB0);

    String label;
    if (_loading) {
      label = isBooking ? 'Loading booking…' : 'Loading refund…';
    } else if (_data == null) {
      label = isBooking ? 'Booking' : 'Refund Request';
    } else if (isBooking) {
      final num = _data!['booking_number'] ?? '';
      final status = _data!['status'] ?? '';
      label = 'Booking #$num • $status';
    } else {
      final num = _data!['ticket_number'] ?? '';
      final status = _data!['status'] ?? '';
      label = 'Refund #$num • $status';
    }

    return Container(
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
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 11,
                  color: textColor,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Attachment view ────────────────────────────────────────────────────────────

class _AttachmentView extends StatefulWidget {
  final String storagePath;
  final String? mimeType;
  final bool isAdmin;
  final SupportRepository repository;

  const _AttachmentView({
    required this.storagePath,
    required this.mimeType,
    required this.isAdmin,
    required this.repository,
  });

  @override
  State<_AttachmentView> createState() => _AttachmentViewState();
}

class _AttachmentViewState extends State<_AttachmentView> {
  String? _signedUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = await widget.repository
        .getSignedAttachmentUrl(widget.storagePath);
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
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (_signedUrl == null) {
      return const Text('⚠ Attachment unavailable',
          style: TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)));
    }

    if (isImage) {
      return GestureDetector(
        onTap: () => _openUrl(_signedUrl!),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            _signedUrl!,
            width: 200,
            height: 160,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const Text('⚠ Image load failed',
                    style: TextStyle(
                        fontSize: 12, color: Color(0xFFA0AEC0))),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _openUrl(_signedUrl!),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: widget.isAdmin
              ? Colors.white.withAlpha(30)
              : const Color(0xFFF7FAFC),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 16,
              color: widget.isAdmin
                  ? Colors.white70
                  : const Color(0xFF718096),
            ),
            const SizedBox(width: 6),
            Text(
              'View Attachment',
              style: TextStyle(
                fontSize: 12,
                color: widget.isAdmin ? Colors.white : AppColors.primary,
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

// ── Highlighted text ───────────────────────────────────────────────────────────

class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle baseStyle;

  const _HighlightedText({
    required this.text,
    required this.query,
    required this.baseStyle,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) return Text(text, style: baseStyle);
    final lower = text.toLowerCase();
    final lowerQ = query.toLowerCase();
    final spans = <TextSpan>[];
    int last = 0;
    int idx = lower.indexOf(lowerQ, last);
    while (idx != -1) {
      if (idx > last) spans.add(TextSpan(text: text.substring(last, idx)));
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: const TextStyle(
            backgroundColor: Color(0xFF1A202C),
            color: Colors.white),
      ));
      last = idx + query.length;
      idx = lower.indexOf(lowerQ, last);
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return RichText(text: TextSpan(style: baseStyle, children: spans));
  }
}

// ── Reply input ────────────────────────────────────────────────────────────────

class _ReplyInput extends StatefulWidget {
  final String conversationId;
  final String customerId;
  final Future<void> Function({
    required String text,
    _PendingFile? file,
    _ContextRef? context,
  }) onSend;
  final VoidCallback onTyping;
  final SupportRepository repository;

  const _ReplyInput({
    required this.conversationId,
    required this.customerId,
    required this.onSend,
    required this.onTyping,
    required this.repository,
  });

  @override
  State<_ReplyInput> createState() => _ReplyInputState();
}

class _ReplyInputState extends State<_ReplyInput> {
  final _ctrl = TextEditingController();
  bool _sending = false;
  String? _error;
  _PendingFile? _pendingFile;
  _ContextRef? _pendingContext;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if ((text.isEmpty && _pendingFile == null) || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final file = _pendingFile;
    final ctx = _pendingContext;
    _ctrl.clear();
    setState(() {
      _pendingFile = null;
      _pendingContext = null;
    });
    try {
      await widget.onSend(text: text, file: file, context: ctx);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null) return;
    final ext = (f.extension ?? 'jpg').toLowerCase();
    final mime = ext == 'png'
        ? 'image/png'
        : ext == 'webp'
            ? 'image/webp'
            : ext == 'pdf'
                ? 'application/pdf'
                : 'image/jpeg';
    if (mounted) {
      setState(() => _pendingFile =
          _PendingFile(bytes: f.bytes!, filename: f.name, mimeType: mime));
    }
  }

  Future<void> _pickContext() async {
    final result = await showDialog<_ContextRef>(
      context: context,
      builder: (_) => _ContextPickerDialog(
        customerId: widget.customerId,
        repository: widget.repository,
      ),
    );
    if (result != null && mounted) setState(() => _pendingContext = result);
  }

  void _showCannedReplies() {
    final ro = RelativeRect.fromLTRB(
      MediaQuery.of(context).size.width - 300,
      MediaQuery.of(context).size.height - 320,
      16,
      80,
    );
    showMenu<String>(
      context: context,
      position: ro,
      constraints: const BoxConstraints(maxWidth: 320, maxHeight: 280),
      items: _kCannedReplies
          .map((r) => PopupMenuItem<String>(
                value: r,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                child: Text(r,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ))
          .toList(),
    ).then((val) {
      if (val != null && mounted) {
        _ctrl.text = val;
        _ctrl.selection = TextSelection.fromPosition(
            TextPosition(offset: _ctrl.text.length));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null)
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFFFFF5F5),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    size: 14, color: Color(0xFFE53E3E)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_error!,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFFE53E3E)))),
                IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  onPressed: () => setState(() => _error = null),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        if (_pendingFile != null)
          Container(
            height: 70,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF7FAFC),
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                if (_pendingFile!.mimeType.startsWith('image/'))
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(_pendingFile!.bytes,
                        width: 50, height: 50, fit: BoxFit.cover),
                  )
                else
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.insert_drive_file,
                        size: 24, color: Color(0xFF718096)),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _pendingFile!.filename,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF2D3748)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 16, color: Color(0xFF718096)),
                  onPressed: () => setState(() => _pendingFile = null),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        if (_pendingContext != null)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFFF7FAFC),
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Icon(
                  _pendingContext!.type == 'booking'
                      ? Icons.receipt_long_outlined
                      : Icons.currency_rupee_outlined,
                  size: 14,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _pendingContext!.label,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 16, color: Color(0xFF718096)),
                  onPressed: () =>
                      setState(() => _pendingContext = null),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                onPressed: _pickFile,
                icon: const Icon(Icons.attach_file_rounded),
                iconSize: 18,
                tooltip: 'Attach file',
                color: const Color(0xFF718096),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(6),
              ),
              IconButton(
                onPressed: _pickContext,
                icon: const Icon(Icons.link_rounded),
                iconSize: 18,
                tooltip: 'Link booking or refund',
                color: _pendingContext != null
                    ? AppColors.primary
                    : const Color(0xFF718096),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(6),
              ),
              IconButton(
                onPressed: _showCannedReplies,
                icon: const Icon(Icons.quickreply_rounded),
                iconSize: 18,
                tooltip: 'Quick reply',
                color: const Color(0xFF718096),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(6),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 5,
                  onChanged: (_) => widget.onTyping(),
                  decoration: InputDecoration(
                    hintText: 'Type a reply…',
                    hintStyle: const TextStyle(
                        color: Color(0xFFA0AEC0), fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFFF7FAFC),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide:
                          const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide:
                          const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide:
                          BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _sending
                      ? AppColors.primary.withAlpha(160)
                      : AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: _sending ? null : _send,
                  padding: EdgeInsets.zero,
                  icon: _sending
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded,
                          size: 15, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Context picker dialog ─────────────────────────────────────────────────────

class _ContextPickerDialog extends StatefulWidget {
  final String customerId;
  final SupportRepository repository;

  const _ContextPickerDialog({
    required this.customerId,
    required this.repository,
  });

  @override
  State<_ContextPickerDialog> createState() => _ContextPickerDialogState();
}

class _ContextPickerDialogState extends State<_ContextPickerDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<Map<String, dynamic>>? _bookings;
  List<Map<String, dynamic>>? _refunds;
  bool _loading = true;

  static final _dateFmt = DateFormat('d MMM');
  static final _currency =
      NumberFormat.currency(symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final b = await widget.repository
          .fetchCustomerBookings(widget.customerId);
      final r = await widget.repository
          .fetchCustomerRefunds(widget.customerId);
      if (mounted) {
        setState(() {
          _bookings = b;
          _refunds = r;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Link Booking or Refund',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabs,
              labelStyle: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600),
              labelColor: AppColors.primary,
              unselectedLabelColor: const Color(0xFF718096),
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: 'Bookings'),
                Tab(text: 'Refund Requests'),
              ],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _buildList(
                          items: _bookings ?? [],
                          emptyLabel: 'No bookings found',
                          itemBuilder: (b) {
                            final num = b['booking_number'] ?? '—';
                            final date = b['service_date'] != null
                                ? _dateFmt.format(DateTime.parse(
                                    b['service_date'] as String))
                                : '—';
                            final amount = b['total_amount'] != null
                                ? _currency.format(b['total_amount'])
                                : '';
                            final status =
                                b['status'] as String? ?? '';
                            return ListTile(
                              dense: true,
                              leading: const Icon(
                                  Icons.receipt_long_outlined,
                                  size: 18,
                                  color: Color(0xFF718096)),
                              title: Text('#$num',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  '$date${amount.isNotEmpty ? ' • $amount' : ''}',
                                  style: const TextStyle(fontSize: 11)),
                              trailing: _MiniStatusBadge(status),
                              onTap: () => Navigator.of(context).pop(
                                _ContextRef(
                                  type: 'booking',
                                  id: b['id'] as String,
                                  label: 'Booking #$num ($status)',
                                ),
                              ),
                            );
                          },
                        ),
                        _buildList(
                          items: _refunds ?? [],
                          emptyLabel: 'No refund requests found',
                          itemBuilder: (r) {
                            final num = r['ticket_number'] ?? '—';
                            final amount = r['requested_amount'] != null
                                ? _currency.format(r['requested_amount'])
                                : '';
                            final status =
                                r['status'] as String? ?? '';
                            return ListTile(
                              dense: true,
                              leading: const Icon(
                                  Icons.currency_rupee_outlined,
                                  size: 18,
                                  color: Color(0xFF718096)),
                              title: Text('#$num',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  amount.isNotEmpty ? amount : '—',
                                  style: const TextStyle(fontSize: 11)),
                              trailing: _MiniStatusBadge(status),
                              onTap: () => Navigator.of(context).pop(
                                _ContextRef(
                                  type: 'refund',
                                  id: r['id'] as String,
                                  label: 'Refund #$num ($status)',
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList({
    required List<Map<String, dynamic>> items,
    required String emptyLabel,
    required Widget Function(Map<String, dynamic>) itemBuilder,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Text(emptyLabel,
            style: const TextStyle(
                fontSize: 13, color: Color(0xFF718096))),
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => itemBuilder(items[i]),
    );
  }
}

class _MiniStatusBadge extends StatelessWidget {
  final String status;

  const _MiniStatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    final (color, bg) = _colors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  (Color, Color) _colors(String s) {
    switch (s) {
      case 'completed':
        return (const Color(0xFF38A169), const Color(0xFFF0FFF4));
      case 'cancelled':
        return (const Color(0xFFE53E3E), const Color(0xFFFFF5F5));
      case 'pending':
        return (const Color(0xFFDD6B20), const Color(0xFFFEEBC8));
      case 'approved':
        return (const Color(0xFF3182CE), const Color(0xFFEBF8FF));
      default:
        return (const Color(0xFF718096), const Color(0xFFF7FAFC));
    }
  }
}

// ── Closed banner ──────────────────────────────────────────────────────────────

class _ClosedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF7FAFC),
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline_rounded,
              size: 14, color: Color(0xFF718096)),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'This conversation is closed. '
              'The customer can reopen it by sending a new message.',
              style: TextStyle(fontSize: 12, color: Color(0xFF718096)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── History banner ─────────────────────────────────────────────────────────────

class _HistoryBanner extends StatelessWidget {
  final DateTime? reopenedAt;

  const _HistoryBanner({required this.reopenedAt});

  @override
  Widget build(BuildContext context) {
    final dateStr = reopenedAt != null
        ? DateFormat('d MMM y').format(reopenedAt!.toLocal())
        : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF8E1),
        border: Border(top: BorderSide(color: Color(0xFFD69E2E))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.history_rounded, size: 14, color: Color(0xFF8B6914)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              dateStr != null
                  ? 'Prior episode — customer reopened on $dateStr.'
                  : 'Prior episode — read-only history.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF8B6914)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Auto-close warning banner ──────────────────────────────────────────────────
//
// Shown above the reply input when auto-close is enabled. Tells the admin how
// long is left before the conversation is automatically closed due to inactivity.
// Hidden entirely when auto-close is disabled or no message has been sent yet.

class _AutoCloseBanner extends StatelessWidget {
  final SupportConversation conversation;
  final Map<String, String> settings;

  const _AutoCloseBanner({
    required this.conversation,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final enabled =
        SettingsNotifier.effectiveValue(settings, 'support_auto_close_enabled') ==
            'true';
    if (!enabled) return const SizedBox.shrink();

    final lastMsgAt = conversation.lastMessageAt;
    if (lastMsgAt == null) return const SizedBox.shrink();

    final idleHours =
        int.tryParse(SettingsNotifier.effectiveValue(
              settings, 'support_auto_close_idle_hours')) ??
            24;

    final now = DateTime.now();
    final closesAt = lastMsgAt.add(Duration(hours: idleHours));
    final remaining = closesAt.difference(now);
    final elapsed = now.difference(lastMsgAt);

    final elapsedStr = _humanizeDuration(elapsed);
    final remainingStr = remaining.isNegative || remaining.inMinutes < 1
        ? 'any moment now'
        : _humanizeDuration(remaining);

    // Urgency: red tint when < 20 % of idle period remains.
    final urgent = remaining.inMinutes < (idleHours * 60 * 0.2).round();
    final bgColor = urgent ? const Color(0xFFFFF5F5) : const Color(0xFFFFFBEB);
    final borderColor =
        urgent ? const Color(0xFFFC8181) : const Color(0xFFF6AD55);
    final iconColor =
        urgent ? const Color(0xFFE53E3E) : const Color(0xFFDD6B20);
    final textColor =
        urgent ? const Color(0xFF9B2C2C) : const Color(0xFF7B341E);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 14, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No reply for $elapsedStr — this conversation auto-closes in $remainingStr.',
              style: TextStyle(fontSize: 12, color: textColor),
            ),
          ),
        ],
      ),
    );
  }

  static String _humanizeDuration(Duration d) {
    if (d.inMinutes < 1) return 'less than a minute';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (d.inHours < 24) return m > 0 ? '${h}h ${m}m' : '${h}h';
    final days = d.inDays;
    final hrs = d.inHours.remainder(24);
    return hrs > 0 ? '${days}d ${hrs}h' : '${days}d';
  }
}

// ── Empty states ───────────────────────────────────────────────────────────────

class _EmptyListView extends StatelessWidget {
  const _EmptyListView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.support_agent_rounded,
              size: 40, color: Color(0xFFCBD5E0)),
          SizedBox(height: 12),
          Text('No conversations found',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF718096))),
          SizedBox(height: 4),
          Text('Customer conversations will appear here.',
              style: TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _EmptySelectionView extends StatelessWidget {
  const _EmptySelectionView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_outlined, size: 56, color: Color(0xFFCBD5E0)),
          SizedBox(height: 16),
          Text('Select a conversation',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF718096))),
          SizedBox(height: 6),
          Text(
            'Choose a conversation from the list to view\n'
            'and reply to customer messages.',
            style: TextStyle(
                fontSize: 13, color: Color(0xFFA0AEC0), height: 1.6),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Shared status badge ────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
