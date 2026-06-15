import 'package:karunstream/features/karunstream/model/file_transfer.dart';
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
      'download_url': '/api/v1/files/t9821a/download',
    });

    expect(offer.transferId, 't9821a');
    expect(offer.senderId, 'u2');
    expect(offer.fileName, 'ProjectMasterclass.mp4');
    expect(offer.fileSize, 2451092834);
    expect(offer.downloadUrl, '/api/v1/files/t9821a/download');
  });

  test('FileTransfer parses upload response metadata', () {
    final transfer = FileTransfer.fromJson({
      'transfer_id': 't1',
      'sender_id': 'sender',
      'recipient_id': 'recipient',
      'file_name': 'local.zip',
      'bytes': 4096,
      'sha256':
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      'stored_path': '/tmp/karunstream/uploads/local.zip',
      'download_url': '/api/v1/files/t1/download',
      'created_at': 1718290312,
      'duration_seconds': 0.42,
    });

    expect(transfer.transferId, 't1');
    expect(transfer.recipientId, 'recipient');
    expect(transfer.bytes, 4096);
    expect(transfer.downloadUrl, '/api/v1/files/t1/download');
  });
}
