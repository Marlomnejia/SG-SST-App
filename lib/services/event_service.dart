import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'storage_service.dart';
import 'user_service.dart';

class EventService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final StorageService _storageService = StorageService();
  final UserService _userService = UserService();

  /// Obtiene el stream de eventos filtrados por institución
  /// Requerido para cumplir con las reglas de seguridad de Firestore
  Stream<QuerySnapshot> getEventsStream(String institutionId) {
    return _firestore
        .collection('eventos')
        .where('institutionId', isEqualTo: institutionId)
        .orderBy('fechaReporte', descending: true)
        .snapshots();
  }

  /// Obtiene eventos de una institución (Future)
  Future<QuerySnapshot> getEvents(String institutionId) {
    return _firestore
        .collection('eventos')
        .where('institutionId', isEqualTo: institutionId)
        .orderBy('fechaReporte', descending: true)
        .get();
  }

  /// Obtiene el institutionId del usuario actual
  Future<String?> getCurrentUserInstitutionId() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return await _userService.getUserInstitutionId(user.uid);
  }

  Future<void> addEvent(
    String tipo,
    String descripcion,
    List<XFile> images, {
    List<XFile> videos = const [],
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

      // Obtener institutionId del usuario actual
      final institutionId = await _userService.getUserInstitutionId(currentUser.uid);
      if (institutionId == null) {
        throw Exception('El usuario no pertenece a ninguna institución.');
      }

      // Step 1: Create the document with institutionId for security rules
      final Map<String, dynamic> data = {
        'tipo': tipo,
        'descripcion': descripcion,
        'fechaReporte': Timestamp.now(),
        'estado': 'reportado',
        'reportadoPor_uid': currentUser.uid,
        'reportadoPor_email': currentUser.email,
        'institutionId': institutionId, // Requerido para reglas de seguridad
        'lugar': location,
        'categoria': category,
        'severidad': severity,
        'fotoUrls': [], // Initialize as an empty list
        'videoUrls': [], // Initialize as an empty list
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
      if (videos.isNotEmpty) {
        List<String> downloadUrls =
            await _storageService.uploadEventVideos(videos, docRef.id);
        await docRef.update({'videoUrls': downloadUrls});
      }
    } on FirebaseException catch (e) {
      // Re-throw the exception to be handled by the UI
      throw Exception('Error al guardar el evento: ${e.message}');
    }
  }
}
