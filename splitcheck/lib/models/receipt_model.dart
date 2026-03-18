class Receipt {
  final String id;
  final String placeName;
  final String ownerVenmo;
  final String ownerUid;
  final String? imageUrl;
  final double subtotal;
  final double tax;
  final double tip;
  final double total;
  final DateTime createdAt;
  final String status;
  final String splitMode; // 'items' or 'equal'
  final int equalSplitCount;

  Receipt({
    required this.id,
    required this.placeName,
    required this.ownerVenmo,
    required this.ownerUid,
    required this.subtotal,
    required this.tax,
    required this.tip,
    required this.total,
    required this.createdAt,
    required this.status,
    this.imageUrl,
    this.splitMode = 'items',
    this.equalSplitCount = 2,
  });

  Map<String, dynamic> toMap() {
    return {
      'placeName': placeName,
      'ownerVenmo': ownerVenmo,
      'ownerUid': ownerUid,
      'imageUrl': imageUrl,
      'subtotal': subtotal,
      'tax': tax,
      'tip': tip,
      'total': total,
      'createdAt': createdAt.toIso8601String(),
      'status': status,
      'splitMode': splitMode,
      'equalSplitCount': equalSplitCount,
    };
  }

  factory Receipt.fromMap(String id, Map<String, dynamic> data) {
    return Receipt(
      id: id,
      placeName: data['placeName'] ?? '',
      ownerVenmo: data['ownerVenmo'] ?? '',
      ownerUid: data['ownerUid'] ?? '',
      imageUrl: data['imageUrl'],
      subtotal: (data['subtotal'] as num?)?.toDouble() ?? 0.0,
      tax: (data['tax'] as num?)?.toDouble() ?? 0.0,
      tip: (data['tip'] as num?)?.toDouble() ?? 0.0,
      total: (data['total'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
      status: data['status'] ?? 'draft',
      splitMode: data['splitMode'] ?? 'items',
      equalSplitCount: data['equalSplitCount'] ?? 2,
    );
  }
}

class ReceiptItem {
  final String id;
  String itemName;
  double itemPrice;
  int quantity;
  List<String> claimedBy;
  int position;
  int splitCount; // 1 = just me, 2 = split between 2, etc.

  ReceiptItem({
    required this.id,
    required this.itemName,
    required this.itemPrice,
    this.quantity = 1,
    this.claimedBy = const [],
    this.position = 0,
    this.splitCount = 1,
  });

  Map<String, dynamic> toMap() {
    return {
      'itemName': itemName,
      'itemPrice': itemPrice,
      'quantity': quantity,
      'claimedBy': claimedBy,
      'position': position,
      'splitCount': splitCount,
    };
  }

  factory ReceiptItem.fromMap(String id, Map<String, dynamic> data) {
    return ReceiptItem(
      id: id,
      itemName: data['itemName'] ?? '',
      itemPrice: (data['itemPrice'] as num?)?.toDouble() ?? 0.0,
      quantity: data['quantity'] ?? 1,
      claimedBy: List<String>.from(data['claimedBy'] ?? const []),
      position: data['position'] ?? 0,
      splitCount: data['splitCount'] ?? 1,
    );
  }
}
