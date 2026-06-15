import 'package:karunstream/features/karunstream/model/file_offer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FileOffer parses PRD file transfer payload', () {
    final offer = FileOffer.fromJson({
      'transfer_id': 't9821a',
      'sender_id': 'u2',
      'file_name': 'ProjectMasterclass.mp4',
      'file_size': 2451092834,
      'sha256':
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    });

    expect(offer.transferId, 't9821a');
    expect(offer.senderId, 'u2');
    expect(offer.fileName, 'ProjectMasterclass.mp4');
    expect(offer.fileSize, 2451092834);
  });
}
