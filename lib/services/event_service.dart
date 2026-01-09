import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'storage_service.dart';

class EventService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final StorageService _storageService = StorageService();

  Future<void> addEvent(
    String tipo,
    String descripcion,
    List<XFile> images, {
    String? location,
    String? category,
    String? severity,
    DateTime? eventDateTime,
    double? latitude,
    double? longitude,
    String? gpsAddress,
  }) async {
    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('No hay un usuario autenticado.');
      }

      // Step 1: Create the document with an empty list of photoUrls
      final Map<String, dynamic> data = {
        'tipo': tipo,
        'descripcion': descripcion,
        'fechaReporte': Timestamp.now(),
        'estado': 'reportado',
        'reportadoPor_uid': currentUser.uid,
        'reportadoPor_email': currentUser.email,
        'lugar': location,
        'categoria': category,
        'severidad': severity,
        'fotoUrls': [], // Initialize as an empty list
      };

      if (eventDateTime != null) {
        data['fechaEvento'] = Timestamp.fromDate(eventDateTime);
      }

      if (latitude != null && longitude != null) {
        data['ubicacionGps'] = GeoPoint(latitude, longitude);
      }
      if (gpsAddress != null && gpsAddress.trim().isNotEmpty) {
        data['direccionGps'] = gpsAddress.trim();
      }

      DocumentReference docRef = await _firestore.collection('eventos').add(data);

      // Step 2: Upload photos if there are any
      if (images.isNotEmpty) {
        // Call the storage service
        List<String> downloadUrls = await _storageService.uploadEventImages(images, docRef.id);
        
        // Step 3: Update the document with the photo URLs
        await docRef.update({'fotoUrls': downloadUrls});
      }
    } on FirebaseException catch (e) {
      // Re-throw the exception to be handled by the UI
      throw Exception('Error al guardar el evento: ${e.message}');
    }
  }
}
