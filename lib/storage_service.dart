import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class StorageService {
  Future<List<String>> uploadEventImages(List<XFile> images, String eventId) async {
    List<String> downloadUrls = [];
    try {
      for (var image in images) {
        String fileName = '${DateTime.now().millisecondsSinceEpoch}_${image.name}';
        Reference ref = FirebaseStorage.instance.ref().child('eventos/$eventId/$fileName');
        UploadTask uploadTask = ref.putFile(File(image.path));
        TaskSnapshot snapshot = await uploadTask;
        String downloadUrl = await snapshot.ref.getDownloadURL();
        downloadUrls.add(downloadUrl);
      }
    } catch (e) {
      print('Error uploading images: $e');
    }
    return downloadUrls;
  }
}
