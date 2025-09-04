import 'package:flutter/material.dart';
import 'package:splitcheck/features/receipt/data/receipt_repository.dart';
import 'package:splitcheck/models/receipt_model.dart';

class PublicReceiptPage extends StatelessWidget {
  final String slug;
  const PublicReceiptPage({super.key, required this.slug});

  @override
  Widget build(BuildContext context) {
    final repo = ReceiptRepository();

    return Scaffold(
      appBar: AppBar(title: const Text("Receipt")),
      body: FutureBuilder<Receipt?>(
        future: repo.getReceipt(slug),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text("Receipt not found"));
          }

          final receipt = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                "Title: ${receipt.placeName}",
                style: const TextStyle(fontSize: 20),
              ),
              Text("Venmo: ${receipt.ownerVenmo}"),
              const SizedBox(height: 16),
              ...receipt.items.map(
                (item) => ListTile(
                  title: Text(item.itemName),
                  trailing: Text("\$${item.itemPrice.toStringAsFixed(2)}"),
                ),
              ),
              ListTile(
                title: const Text("Tip"),
                trailing: Text("\$${receipt.tip.toStringAsFixed(2)}"),
              ),
              ListTile(
                title: const Text("Total"),
                trailing: Text(
                  "\$${(receipt.items.fold(0.0, (sum, i) => sum + i.itemPrice) + receipt.tip).toStringAsFixed(2)}",
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
