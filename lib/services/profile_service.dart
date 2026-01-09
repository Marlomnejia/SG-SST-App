import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class ProfileService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<String> uploadProfilePhoto(String uid, XFile file) async {
    final String fileName =
        'profile_${DateTime.now().millisecondsSinceEpoch}_${file.name}';
    final Reference ref = _storage.ref().child('users/$uid/$fileName');
    final UploadTask uploadTask = ref.putFile(File(file.path));
    final TaskSnapshot snapshot = await uploadTask;
    return snapshot.ref.getDownloadURL();
  }
}
