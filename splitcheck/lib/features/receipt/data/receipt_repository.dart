import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:splitcheck/models/receipt_model.dart';

class ReceiptRepository {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  //Saving a new receipt

  Future<void> saveReceipt(Receipt receipt) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("User not signed in");

    await firestore.collection('receipts').doc(receipt.id).set({
      'placeName': receipt.placeName,
      'ownerVenmo': receipt.ownerVenmo,
      'tip': receipt.tip,
      'createdAt': receipt.createdAt.toIso8601String(),
      'ownerUid': user.uid,
      'items': receipt.items
          .map(
            (i) => {
              'itemName': i.itemName,
              'itemPrice': i.itemPrice,
              'assignedTo': i.assignedTo,
            },
          )
          .toList(),
    });
  }

  //Loading a receipt

  Future<Receipt?> getReceipt(String id) async {
    final doc = await firestore.collection('receipts').doc(id).get();
    if (!doc.exists) return null;

    final data = doc.data()!;
    final itemsData = (data['items'] as List<dynamic>)
        .map(
          (i) => ReceiptItem(
            itemName: i['itemName'],
            itemPrice: i['itemPrice'],
            assignedTo: i['assignedTo'],
          ),
        )
        .toList();

    return Receipt(
      id: doc.id,
      placeName: data['placeName'],
      ownerVenmo: data['ownerVenmo'],
      tip: (data['tip'] as num).toDouble(),
      items: itemsData,
      createdAt: DateTime.parse(data['createdAt']),
    );
  }
}
