import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/tax_record.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';

void main() {
  group('FirestoreService', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService firestoreService;
    const userId = 'test_user';

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(db: fakeFirestore);
    });

    test('saveTaxRecord adds a new record if id is null', () async {
      final record = TaxRecord(userId: userId, financialYear: '2024-2025');
      
      await firestoreService.saveTaxRecord(record);
      
      final snapshot = await fakeFirestore
          .collection('users')
          .doc(userId)
          .collection('tax_records')
          .get();
          
      expect(snapshot.docs.length, 1);
      expect(snapshot.docs.first.data()['financialYear'], '2024-2025');
    });

    test('saveTaxRecord updates existing record if id is present', () async {
      final docRef = await fakeFirestore
          .collection('users')
          .doc(userId)
          .collection('tax_records')
          .add({'financialYear': 'Old Year'});
          
      final record = TaxRecord(
        id: docRef.id,
        userId: userId,
        financialYear: 'New Year',
      );
      
      await firestoreService.saveTaxRecord(record);
      
      final updatedDoc = await docRef.get();
      expect(updatedDoc.data()!['financialYear'], 'New Year');
    });

    test('getUserTaxRecords returns list of records', () async {
      await fakeFirestore
          .collection('users')
          .doc(userId)
          .collection('tax_records')
          .add({'userId': userId, 'financialYear': '2023-2024'});
          
      final stream = firestoreService.getUserTaxRecords(userId);
      final list = await stream.first;
      
      expect(list.length, 1);
      expect(list.first.financialYear, '2023-2024');
    });

    test('deleteTaxRecord removes the record', () async {
      final docRef = await fakeFirestore
          .collection('users')
          .doc(userId)
          .collection('tax_records')
          .add({'financialYear': '2024'});
          
      await firestoreService.deleteTaxRecord(userId, docRef.id);
      
      final snapshot = await fakeFirestore
          .collection('users')
          .doc(userId)
          .collection('tax_records')
          .get();
          
      expect(snapshot.docs.isEmpty, true);
    });
  });
}
