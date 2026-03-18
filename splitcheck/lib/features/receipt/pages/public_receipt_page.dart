import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:splitcheck/features/receipt/data/receipt_repository.dart';
import 'package:splitcheck/models/participant_model.dart';
import 'package:splitcheck/models/receipt_model.dart';
import 'package:splitcheck/theme.dart';
import 'package:url_launcher/url_launcher.dart';

class PublicReceiptPage extends StatefulWidget {
  final String slug;

  const PublicReceiptPage({super.key, required this.slug});

  @override
  State<PublicReceiptPage> createState() => _PublicReceiptPageState();
}

class _PublicReceiptPageState extends State<PublicReceiptPage> {
  final ReceiptRepository _repo = ReceiptRepository();
  final TextEditingController _tipController = TextEditingController();

  String? _participantId;
  bool _hasJoined = false;

  @override
  void dispose() {
    _tipController.dispose();
    super.dispose();
  }

  void _syncJoinState(List<Participant> participants) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _hasJoined) return;

    final match = participants.where((p) => p.id == uid);
    if (match.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_hasJoined) {
          setState(() {
            _participantId = uid;
            _hasJoined = true;
          });
        }
      });
    }
  }

  Future<void> _showJoinDialog() async {
    final nameController = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Center(
          child: Padding(
            padding: const EdgeInsets.all(15.0),
            child: Text('Join this receipt'),
          ),
        ),
        content: Padding(
          padding: const EdgeInsets.all(15.0),
          child: TextField(
            controller: nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Your name',
              hintText: 'e.g. Alex',
            ),
            onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(nameController.text.trim()),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            child: const Text('Join'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await _repo.addParticipant(
      receiptId: widget.slug,
      participant: Participant(id: uid, name: name, joinedAt: DateTime.now()),
    );

    setState(() {
      _participantId = uid;
      _hasJoined = true;
    });
  }

  Future<void> _onItemTap(String itemId) async {
    if (_participantId == null) return;
    HapticFeedback.lightImpact();
    try {
      await _repo.toggleItemClaim(
        receiptId: widget.slug,
        itemId: itemId,
        participantId: _participantId!,
      );
    } catch (e) {
      debugPrint('toggleItemClaim failed: $e');
    }
  }

  String get _receiptLink =>
      'https://varun9729.github.io/Splitcheck/#/r/${widget.slug}';

  void _shareReceipt() {
    Clipboard.setData(ClipboardData(text: _receiptLink));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link copied to clipboard!')),
      );
    }
  }

  void _showQrCode() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scan to join', textAlign: TextAlign.center),
        content: SizedBox(
          width: 220,
          height: 220,
          child: QrImageView(
            data: _receiptLink,
            size: 220,
            backgroundColor: Colors.white,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveTip(double tip) async {
    await _repo.updateReceiptTip(receiptId: widget.slug, tip: tip);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt),
            onPressed: _saveFullReceipt,
          ),
          IconButton(icon: const Icon(Icons.qr_code), onPressed: _showQrCode),
          IconButton(icon: const Icon(Icons.share), onPressed: _shareReceipt),
        ],
      ),
      body: StreamBuilder<Receipt?>(
        stream: _repo.watchReceipt(widget.slug),
        builder: (context, receiptSnap) {
          if (receiptSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!receiptSnap.hasData || receiptSnap.data == null) {
            return const Center(child: Text('Receipt not found'));
          }

          final receipt = receiptSnap.data!;
          final isOwner =
              FirebaseAuth.instance.currentUser?.uid == receipt.ownerUid;

          return StreamBuilder<List<ReceiptItem>>(
            stream: _repo.watchReceiptItems(widget.slug),
            builder: (context, itemsSnap) {
              final items = itemsSnap.data ?? [];

              return StreamBuilder<List<Participant>>(
                stream: _repo.watchParticipants(widget.slug),
                builder: (context, partSnap) {
                  final participants = partSnap.data ?? [];
                  _syncJoinState(participants);

                  final unclaimedCount = items
                      .where((i) => i.claimedBy.isEmpty)
                      .length;

                  return Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          children: [
                            // Centered header
                            _buildCenteredHeader(receipt, participants),
                            const SizedBox(height: 20),

                            // Join button
                            if (!_hasJoined && !isOwner) ...[
                              FilledButton.icon(
                                onPressed: _showJoinDialog,
                                icon: const Icon(Icons.person_add),
                                label: const Text('Join & Claim Your Items'),
                              ),
                              const SizedBox(height: 20),
                            ],

                            // Participant avatars row
                            if (participants.isNotEmpty) ...[
                              _buildAvatarRow(participants),
                              const SizedBox(height: 6),
                              if (_hasJoined)
                                Text(
                                  'Tap items to claim and share the receipt with your friends.',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: AppColors.textPrimary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              const SizedBox(height: 16),
                            ],

                            const Divider(),
                            const SizedBox(height: 8),

                            // Equal split banner
                            if (receipt.splitMode == 'equal') ...[
                              _buildEqualSplitView(receipt),
                              const SizedBox(height: 16),
                            ],

                            // Items (always show, but no claiming in equal mode)
                            ...items.map(
                              (item) => receipt.splitMode == 'equal'
                                  ? _buildSimpleItemRow(item)
                                  : _buildItemRow(item, participants),
                            ),

                            const Divider(height: 32),

                            // Totals
                            _buildTotalRow('Subtotal', receipt.subtotal),
                            if (receipt.tax > 0)
                              _buildTotalRow('Tax', receipt.tax),

                            // Tip
                            if (isOwner) ...[
                              const SizedBox(height: 8),
                              _buildTipInput(receipt),
                            ] else if (receipt.tip > 0)
                              _buildTotalRow('Tip', receipt.tip),

                            const Divider(height: 24),
                            _buildTotalRow(
                              'Total',
                              receipt.total,
                              isTotal: true,
                            ),

                            // Settlement cards
                            if (items.any((i) => i.claimedBy.isNotEmpty)) ...[
                              const SizedBox(height: 24),
                              _buildSettlementCards(
                                receipt: receipt,
                                items: items,
                                participants: participants,
                              ),
                            ],

                            const SizedBox(height: 80),
                          ],
                        ),
                      ),

                      // Bottom bar
                      if (_hasJoined && items.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: unclaimedCount == 0
                                ? AppColors.primary.withValues(alpha: 0.1)
                                : AppColors.surface,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 8,
                                offset: const Offset(0, -2),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              unclaimedCount == 0
                                  ? 'All items claimed!'
                                  : '$unclaimedCount item${unclaimedCount == 1 ? '' : 's'} unclaimed',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: unclaimedCount == 0
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildCenteredHeader(Receipt receipt, List<Participant> participants) {
    final claimants = participants.where((p) => !p.isOwner).length;
    final splitCount = claimants + 1; // owner + friends

    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          receipt.placeName,
          style: const TextStyle(
            fontSize: 24,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          '\$${receipt.total.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          splitCount > 1
              ? 'Split between $splitCount people'
              : 'Pay @${receipt.ownerVenmo}',
          style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildAvatarRow(List<Participant> participants) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ...participants.asMap().entries.map((entry) {
          final i = entry.key;
          final p = entry.value;
          final isMe = p.id == _participantId;
          final color = AppColors
              .participantColors[i % AppColors.participantColors.length];
          final initials = p.name.length >= 2
              ? p.name.substring(0, 2).toUpperCase()
              : p.name.toUpperCase();

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                Container(
                  decoration: isMe
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary,
                            width: 2.5,
                          ),
                        )
                      : null,
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: color,
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isMe ? 'You' : p.name,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: isMe ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        }),
        // Add friend button
        if (_hasJoined)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 16),
            child: GestureDetector(
              onTap: _shareReceipt,
              child: CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.surfaceVariant,
                child: Icon(
                  Icons.add,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildItemRow(ReceiptItem item, List<Participant> participants) {
    final isClaimed =
        _participantId != null && item.claimedBy.contains(_participantId);

    // Get claimer colors
    final claimerWidgets = <Widget>[];
    for (final pid in item.claimedBy) {
      final pIndex = participants.indexWhere((p) => p.id == pid);
      if (pIndex >= 0) {
        final color = AppColors
            .participantColors[pIndex % AppColors.participantColors.length];
        claimerWidgets.add(
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        );
      }
    }

    return GestureDetector(
      onTap: _hasJoined ? () => _onItemTap(item.id) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isClaimed
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isClaimed
                ? AppColors.primary.withValues(alpha: 0.3)
                : AppColors.cardBorder,
          ),
        ),
        child: Row(
          children: [
            // Left border indicator
            Container(
              width: 3,
              height: 32,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: item.claimedBy.isNotEmpty
                    ? AppColors.primary
                    : AppColors.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Item details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.quantity > 1
                        ? '${item.quantity}x ${item.itemName}'
                        : item.itemName,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (item.claimedBy.isEmpty && _hasJoined)
                    Text(
                      'Tap to claim',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    )
                  else if (isClaimed) ...[
                    const SizedBox(height: 6),
                    _buildSplitPills(item),
                  ] else if (claimerWidgets.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: claimerWidgets),
                    ),
                ],
              ),
            ),

            // Price
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${item.itemPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (item.splitCount > 1)
                  Text(
                    '\$${(item.itemPrice / item.splitCount).toStringAsFixed(2)} each',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSplitPills(ReceiptItem item) {
    return Row(
      children: [
        Text(
          'Split: ',
          style: TextStyle(fontSize: 11, color: AppColors.textPrimary),
        ),
        ...[1, 2, 3, 4].map((n) {
          final isSelected = item.splitCount == n;
          final label = n == 1 ? 'Just me' : '÷$n';
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: GestureDetector(
              onTap: () {
                _repo.updateItemSplitCount(
                  receiptId: widget.slug,
                  itemId: item.id,
                  splitCount: n,
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          );
        }),
        // Custom split pill
        GestureDetector(
          onTap: () => _showCustomSplit(item),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: item.splitCount > 4
                  ? AppColors.primary
                  : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              item.splitCount > 4 ? '÷${item.splitCount}' : '÷#',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: item.splitCount > 4
                    ? Colors.white
                    : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showCustomSplit(ReceiptItem item) async {
    final controller = TextEditingController(
      text: item.splitCount > 4 ? '${item.splitCount}' : '',
    );

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Padding(
          padding: const EdgeInsets.all(15.0),
          child: const Text('Split between how many?'),
        ),
        content: Padding(
          padding: const EdgeInsets.all(15.0),
          child: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'e.g. 5'),
            onSubmitted: (val) {
              final n = int.tryParse(val);
              if (n != null && n > 0) Navigator.of(ctx).pop(n);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(controller.text);
              if (n != null && n > 0) Navigator.of(ctx).pop(n);
            },
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            child: const Text('Set'),
          ),
        ],
      ),
    );

    if (result != null) {
      _repo.updateItemSplitCount(
        receiptId: widget.slug,
        itemId: item.id,
        splitCount: result,
      );
    }
  }

  Widget _buildEqualSplitView(Receipt receipt) {
    final perPerson = receipt.total / receipt.equalSplitCount;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.people, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Split equally between ${receipt.equalSplitCount} people',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Each person pays', style: TextStyle(fontSize: 14)),
              Text(
                '\$${perPerson.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          if (receipt.ownerVenmo.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Pay @${receipt.ownerVenmo}',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],

          // Payment buttons for equal split
          if (FirebaseAuth.instance.currentUser?.uid != receipt.ownerUid) ...[
            const SizedBox(height: 14),
            _buildPaymentGrid(
              amount: perPerson,
              note: 'Splitcheck - ${receipt.placeName}',
              venmoHandle: receipt.ownerVenmo,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSimpleItemRow(ReceiptItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.quantity > 1
                  ? '${item.quantity}x ${item.itemName}'
                  : item.itemName,
              style: const TextStyle(fontSize: 15),
            ),
          ),
          Text(
            '\$${item.itemPrice.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildTipInput(Receipt receipt) {
    if (_tipController.text.isEmpty && receipt.tip > 0) {
      _tipController.text = receipt.tip.toStringAsFixed(2);
    }
    return Row(
      children: [
        const Text('Tip', style: TextStyle(fontSize: 14)),
        const Spacer(),
        SizedBox(
          width: 90,
          child: TextField(
            controller: _tipController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              prefixText: '\$ ',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            onSubmitted: (val) {
              _saveTip(double.tryParse(val) ?? 0.0);
            },
            onEditingComplete: () {
              _saveTip(double.tryParse(_tipController.text) ?? 0.0);
              FocusScope.of(context).unfocus();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTotalRow(String label, double amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 17 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isTotal ? 17 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// Per-person settlement cards like the Lovable design.
  Widget _buildSettlementCards({
    required Receipt receipt,
    required List<ReceiptItem> items,
    required List<Participant> participants,
  }) {
    final Map<String, double> itemTotals = {};
    final Map<String, List<ReceiptItem>> claimedItems = {};

    for (final item in items) {
      if (item.claimedBy.isEmpty) continue;
      // Use splitCount if set, otherwise fall back to claimedBy count
      final divisor = item.splitCount > 1
          ? item.splitCount
          : item.claimedBy.length;
      final share = item.itemPrice / divisor;
      for (final pid in item.claimedBy) {
        itemTotals[pid] = (itemTotals[pid] ?? 0) + share;
        claimedItems.putIfAbsent(pid, () => []).add(item);
      }
    }

    final totalClaimed = itemTotals.values.fold<double>(0, (a, b) => a + b);
    if (totalClaimed == 0) return const SizedBox.shrink();

    final ownerUid = receipt.ownerUid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment Status',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        ...itemTotals.entries.map((entry) {
          final pid = entry.key;
          final itemsSubtotal = entry.value;
          final proportion = itemsSubtotal / totalClaimed;
          final taxShare = receipt.tax * proportion;
          final tipShare = receipt.tip * proportion;
          final amount = itemsSubtotal + taxShare + tipShare;
          final pIndex = participants.indexWhere((p) => p.id == pid);
          final participant = pIndex >= 0 ? participants[pIndex] : null;
          final name = participant?.name ?? 'Unknown';
          final color = pIndex >= 0
              ? AppColors.participantColors[pIndex %
                    AppColors.participantColors.length]
              : AppColors.textSecondary;
          final isOwnerRow = pid == ownerUid;
          final isMe = pid == _participantId;
          final initials = name.length >= 2
              ? name.substring(0, 2).toUpperCase()
              : name.toUpperCase();

          // Show Pay on the owner's card, but only if YOU are not the owner
          final currentUserIsOwner =
              FirebaseAuth.instance.currentUser?.uid == ownerUid;
          final showPay = isOwnerRow && !currentUserIsOwner && _hasJoined;
          final myItems = claimedItems[pid] ?? [];

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              children: [
                // Person header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: color,
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isMe ? '$name (you)' : name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (isOwnerRow)
                              Text(
                                'Owner',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '\$${amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // Claimed items
                if (myItems.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    child: Column(
                      children: [
                        ...myItems.map((item) {
                          final divisor = item.splitCount > 1
                              ? item.splitCount
                              : item.claimedBy.length;
                          final share = item.itemPrice / divisor;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  item.itemName,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                Text(
                                  '\$${share.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          );
                        }),
                        const Divider(height: 16),
                        _settRow('Subtotal', itemsSubtotal),
                        if (taxShare > 0) _settRow('Tax', taxShare),
                        if (tipShare > 0) _settRow('Tip', tipShare),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '\$${amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        // Payment buttons for non-owner viewing their own card
                        if (showPay) ...[
                          const SizedBox(height: 12),
                          Builder(
                            builder: (_) {
                              final mySubtotal =
                                  itemTotals[_participantId] ?? 0;
                              final myProportion = totalClaimed > 0
                                  ? mySubtotal / totalClaimed
                                  : 0.0;
                              final myTotal =
                                  mySubtotal +
                                  receipt.tax * myProportion +
                                  receipt.tip * myProportion;
                              return _buildPaymentGrid(
                                amount: myTotal,
                                note: 'Splitcheck - ${receipt.placeName}',
                                venmoHandle: receipt.ownerVenmo,
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPaymentGrid({
    required double amount,
    required String note,
    required String venmoHandle,
  }) {
    final amountStr = amount.toStringAsFixed(2);
    final encodedNote = Uri.encodeComponent(note);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _payChip(
          label: 'Venmo',
          icon: Icons.payment,
          color: const Color(0xFF3D95CE),
          onTap: () {
            // Use Venmo web URL (works in browsers and opens app if installed)
            final uri = Uri.parse(
              'https://venmo.com/$venmoHandle'
              '?txn=pay&amount=$amountStr'
              '&note=$encodedNote',
            );
            launchUrl(uri, mode: LaunchMode.externalApplication);
          },
        ),
        _payChip(
          label: 'PayPal',
          icon: Icons.account_balance_wallet,
          color: const Color(0xFF003087),
          onTap: () {
            final uri = Uri.parse(
              'https://www.paypal.com/paypalme/$venmoHandle/$amountStr',
            );
            launchUrl(uri, mode: LaunchMode.externalApplication);
          },
        ),
        _payChip(
          label: 'Zelle',
          icon: Icons.send,
          color: const Color(0xFF6D1ED4),
          onTap: () {
            Clipboard.setData(ClipboardData(text: '\$$amountStr for $note'));
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Amount copied! Open your bank app to send via Zelle.',
                  ),
                ),
              );
            }
          },
        ),
        _payChip(
          label: 'Splitwise',
          icon: Icons.group,
          color: const Color(0xFF5BC5A7),
          onTap: () async {
            // Copy details first
            Clipboard.setData(ClipboardData(text: '$note — \$$amountStr'));

            // Try opening Splitwise app
            final appUri = Uri.parse('splitwise://');
            if (await canLaunchUrl(appUri)) {
              await launchUrl(appUri, mode: LaunchMode.externalApplication);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Amount copied! Paste it in Splitwise.'),
                  ),
                );
              }
            } else {
              // App not installed — open App Store / Play Store
              final storeUri = Uri.parse(
                'https://apps.apple.com/app/splitwise/id458023433',
              );
              await launchUrl(storeUri, mode: LaunchMode.externalApplication);
            }
          },
        ),
      ],
    );
  }

  Widget _payChip({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveFullReceipt() async {
    final receipt = await _repo.getReceipt(widget.slug);
    if (receipt == null) return;

    final items = await _repo.getReceiptItems(widget.slug);
    final text = StringBuffer();
    text.writeln(receipt.placeName);
    text.writeln('─' * 30);
    for (final item in items) {
      final name = item.quantity > 1
          ? '${item.quantity}x ${item.itemName}'
          : item.itemName;
      text.writeln('$name  \$${item.itemPrice.toStringAsFixed(2)}');
    }
    text.writeln('─' * 30);
    text.writeln('Subtotal: \$${receipt.subtotal.toStringAsFixed(2)}');
    if (receipt.tax > 0) {
      text.writeln('Tax: \$${receipt.tax.toStringAsFixed(2)}');
    }
    if (receipt.tip > 0) {
      text.writeln('Tip: \$${receipt.tip.toStringAsFixed(2)}');
    }
    text.writeln('Total: \$${receipt.total.toStringAsFixed(2)}');
    if (receipt.splitMode == 'equal') {
      text.writeln('');
      final perPerson = receipt.total / receipt.equalSplitCount;
      text.writeln(
        'Split equally: ${receipt.equalSplitCount} people × \$${perPerson.toStringAsFixed(2)}',
      );
    }
    text.writeln('');
    text.writeln('Link: $_receiptLink');

    Clipboard.setData(ClipboardData(text: text.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt saved to clipboard!')),
      );
    }
  }

  Widget _settRow(String label, double val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          Text(
            '\$${val.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
