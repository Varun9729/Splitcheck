class Receipt {
  final String id;
  final String placeName;
  final String ownerVenmo;
  final List<ReceiptItem> items;
  final double tip;
  final DateTime createdAt;

  Receipt({
    required this.id,
    required this.placeName,
    required this.ownerVenmo,
    required this.items,
    required this.tip,
    required this.createdAt,
  });
}

class ReceiptItem {
  String itemName;
  double itemPrice;
  final String? assignedTo;
  final int? quantity;

  ReceiptItem({
    required this.itemName,
    required this.itemPrice,
    this.assignedTo,
    this.quantity = 1,
  });
}
