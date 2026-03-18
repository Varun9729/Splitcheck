import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:splitcheck/models/receipt_model.dart';
import 'package:splitcheck/models/participant_model.dart';

class ReceiptRepository {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  Future<void> saveReceipt(Receipt receipt, List<ReceiptItem> items) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("User not signed in");

    final receiptRef = firestore.collection('receipts').doc(receipt.id);

    await receiptRef.set(receipt.toMap());

    final batch = firestore.batch();

    for (final item in items) {
      final itemRef = receiptRef.collection('items').doc(item.id);
      batch.set(itemRef, item.toMap());
    }

    final ownerParticipantRef = receiptRef
        .collection('participants')
        .doc(user.uid);

    batch.set(
      ownerParticipantRef,
      Participant(
        id: user.uid,
        name: 'Owner',
        isOwner: true,
        joinedAt: DateTime.now(),
      ).toMap(),
    );

    await batch.commit();
  }

  Future<Receipt?> getReceipt(String id) async {
    final doc = await firestore.collection('receipts').doc(id).get();
    if (!doc.exists) return null;
    return Receipt.fromMap(doc.id, doc.data()!);
  }

  Future<List<ReceiptItem>> getReceiptItems(String receiptId) async {
    final snapshot = await firestore
        .collection('receipts')
        .doc(receiptId)
        .collection('items')
        .orderBy('position')
        .get();

    return snapshot.docs
        .map((doc) => ReceiptItem.fromMap(doc.id, doc.data()))
        .toList();
  }

  Stream<Receipt?> watchReceipt(String id) {
    return firestore.collection('receipts').doc(id).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return Receipt.fromMap(doc.id, doc.data()!);
    });
  }

  Stream<List<ReceiptItem>> watchReceiptItems(String receiptId) {
    return firestore
        .collection('receipts')
        .doc(receiptId)
        .collection('items')
        .orderBy('position')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ReceiptItem.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<void> addParticipant({
    required String receiptId,
    required Participant participant,
  }) async {
    await firestore
        .collection('receipts')
        .doc(receiptId)
        .collection('participants')
        .doc(participant.id)
        .set(participant.toMap(), SetOptions(merge: true));
  }

  Stream<List<Participant>> watchParticipants(String receiptId) {
    return firestore
        .collection('receipts')
        .doc(receiptId)
        .collection('participants')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Participant.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<void> updateReceiptTip({
    required String receiptId,
    required double tip,
  }) async {
    final ref = firestore.collection('receipts').doc(receiptId);
    final doc = await ref.get();
    if (!doc.exists) throw Exception('Receipt not found');

    final data = doc.data()!;
    final subtotal = (data['subtotal'] as num?)?.toDouble() ?? 0.0;
    final tax = (data['tax'] as num?)?.toDouble() ?? 0.0;

    await ref.update({
      'tip': tip,
      'total': subtotal + tax + tip,
    });
  }

  Future<void> toggleItemClaim({
    required String receiptId,
    required String itemId,
    required String participantId,
  }) async {
    final itemRef = firestore
        .collection('receipts')
        .doc(receiptId)
        .collection('items')
        .doc(itemId);

    final doc = await itemRef.get();
    if (!doc.exists) throw Exception('Item not found');

    final data = doc.data()!;
    final claimedBy = List<String>.from(data['claimedBy'] ?? const []);

    if (claimedBy.contains(participantId)) {
      claimedBy.remove(participantId);
    } else {
      claimedBy.add(participantId);
    }

    await itemRef.update({'claimedBy': claimedBy});
  }

  Future<void> updateItemSplitCount({
    required String receiptId,
    required String itemId,
    required int splitCount,
  }) async {
    await firestore
        .collection('receipts')
        .doc(receiptId)
        .collection('items')
        .doc(itemId)
        .update({'splitCount': splitCount});
  }
}
