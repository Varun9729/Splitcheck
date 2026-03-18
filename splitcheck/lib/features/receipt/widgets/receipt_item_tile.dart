import 'package:flutter/material.dart';
import 'package:splitcheck/models/participant_model.dart';
import 'package:splitcheck/models/receipt_model.dart';

class ReceiptItemTile extends StatelessWidget {
  final ReceiptItem item;
  final List<Participant> participants;
  final String? currentParticipantId;
  final VoidCallback? onTap;

  const ReceiptItemTile({
    super.key,
    required this.item,
    required this.participants,
    this.currentParticipantId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isClaimed = currentParticipantId != null &&
        item.claimedBy.contains(currentParticipantId);

    // Build a map of participant id -> name for display
    final participantNames = {
      for (final p in participants) p.id: p.name,
    };

    final claimers = item.claimedBy
        .map((id) => participantNames[id] ?? 'Unknown')
        .toList();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isClaimed ? Colors.blue.shade50 : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isClaimed ? Colors.blue.shade200 : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            // Claim indicator
            Icon(
              isClaimed
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: isClaimed ? Colors.blue : Colors.grey.shade400,
              size: 22,
            ),
            const SizedBox(width: 12),

            // Item details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.quantity > 1
                        ? '${item.quantity}x ${item.itemName}'
                        : item.itemName,
                    style: const TextStyle(fontSize: 15),
                  ),
                  if (claimers.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: claimers
                          .map(
                            (name) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue.shade800,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),

            // Price
            Text(
              '\$${item.itemPrice.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
