import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/institution.dart';
import '../services/auth_service.dart';
import '../services/document_upload_service.dart';
import 'social_onboarding_screen.dart';

class RegisterInstitutionScreen extends StatefulWidget {
  final SocialUserData? socialUserData;

  const RegisterInstitutionScreen({super.key, this.socialUserData});

  @override
  State<RegisterInstitutionScreen> createState() =>
      _RegisterInstitutionScreenState();
}

class _RegisterInstitutionScreenState extends State<RegisterInstitutionScreen> {
  final _step0FormKey = GlobalKey<FormState>();
  final _step1FormKey = GlobalKey<FormState>();
  final _step2FormKey = GlobalKey<FormState>();

  // Controladores de Institucion (Paso 0)
  final _institutionNameController = TextEditingController();
  final _nitController = TextEditingController();
  final _addressController = TextEditingController();

  // Controladores de Contacto (Paso 1)
  final _institutionPhoneController = TextEditingController();
  final _rectorCellPhoneController = TextEditingController();
  final _emailController = TextEditingController();

  // Controladores de Administrador (Paso 2)
  final _adminNameController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _authService = AuthService();
  final _documentService = DocumentUploadService();

  int _currentStep = 0;
  bool _isLoading = false;
  bool _isPasswordObscured = true;
  bool _isUploading = false;
  String _uploadingDocument = '';

  // Tipo de institucion
  InstitutionType _institutionType = InstitutionType.private;

  // Documentos seleccionados
  final Map<DocumentType, SelectedFile> _selectedDocuments = {};

  // Ubicacion - Departamentos y Ciudades
  List<Map<String, dynamic>> _departamentos = [];
  List<String> _ciudades = [];
  String? _selectedDepartment;
  String? _selectedCity;
  bool _isLoadingLocations = true;

  /// Indica si el registro viene de un proveedor social (Google/Microsoft)
  bool get _isSocialRegistration => widget.socialUserData != null;

  /// Documentos requeridos segun el tipo de institucion
  List<DocumentType> get _requiredDocuments {
    final docs = [DocumentType.rectorIdCard];
    if (_institutionType == InstitutionType.public) {
      docs.add(DocumentType.appointmentAct);
    } else {
      docs.add(DocumentType.chamberOfCommerce);
      docs.add(DocumentType.rut);
    }
    return docs;
  }

  /// Verifica si todos los documentos requeridos estan seleccionados
  bool get _hasAllRequiredDocuments {
    for (final doc in _requiredDocuments) {
      if (!_selectedDocuments.containsKey(doc)) return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    AuthService.socialAuthFlowActive = true;
    _loadLocations();
    if (widget.socialUserData != null) {
      _adminNameController.text = widget.socialUserData!.displayName;
      _emailController.text = widget.socialUserData!.email;
    }
  }

  Future<void> _loadLocations() async {
    try {
      final jsonString = await rootBundle.loadString(
        'assets/json/ciudades-departamentos-colombia.json',
      );
      final data = json.decode(jsonString) as Map<String, dynamic>;
      final departamentos = (data['departamentos'] as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList();

      if (mounted) {
        setState(() {
          _departamentos = departamentos;
          _isLoadingLocations = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingLocations = false);
        _showMessage('Error al cargar ubicaciones: $e');
      }
    }
  }

  void _onDepartmentChanged(String? value) {
    setState(() {
      _selectedDepartment = value;
      _selectedCity = null;
      if (value != null) {
        final dept = _departamentos.firstWhere(
          (d) => d['nombre'] == value,
          orElse: () => {'ciudades': <String>[]},
        );
        _ciudades = List<String>.from(dept['ciudades'] ?? []);
      } else {
        _ciudades = [];
      }
    });
  }

  @override
  void dispose() {
    AuthService.socialAuthFlowActive = false;
    _institutionNameController.dispose();
    _nitController.dispose();
    _addressController.dispose();
    _institutionPhoneController.dispose();
    _rectorCellPhoneController.dispose();
    _emailController.dispose();
    _adminNameController.dispose();
    _jobTitleController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _step0FormKey.currentState?.validate() ?? false;
      case 1:
        return _step1FormKey.currentState?.validate() ?? false;
      case 2:
        if (!_hasAllRequiredDocuments) {
          _showMessage('Debes cargar todos los documentos requeridos.');
          return false;
        }
        return true;
      case 3:
        return _step2FormKey.currentState?.validate() ?? false;
      default:
        return false;
    }
  }

  void _onStepContinue() {
    if (!_validateCurrentStep()) return;

    if (_currentStep < 3) {
      setState(() => _currentStep++);
    } else {
      _registerInstitution();
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    } else {
      Navigator.pop(context);
    }
  }

  void _onStepTapped(int step) {
    if (step < _currentStep) {
      setState(() => _currentStep = step);
    } else if (step == _currentStep + 1 && _validateCurrentStep()) {
      setState(() => _currentStep = step);
    }
  }

  Future<void> _pickDocument(DocumentType type) async {
    try {
      setState(() {
        _isUploading = true;
        _uploadingDocument = type.displayName;
      });

      final file = await _documentService.pickDocument();
      if (file != null) {
        setState(() {
          _selectedDocuments[type] = file;
        });
      }
    } on DocumentUploadException catch (e) {
      _showMessage(e.message);
    } finally {
      setState(() {
        _isUploading = false;
        _uploadingDocument = '';
      });
    }
  }

  void _removeDocument(DocumentType type) {
    setState(() {
      _selectedDocuments.remove(type);
    });
  }

  Future<void> _registerInstitution() async {
    // Validar todos los formularios
    if (!(_step0FormKey.currentState?.validate() ?? false)) {
      setState(() => _currentStep = 0);
      _showMessage('Por favor completa los datos de la institucion.');
      return;
    }

    if (!(_step1FormKey.currentState?.validate() ?? false)) {
      setState(() => _currentStep = 1);
      _showMessage('Por favor completa los datos de contacto.');
      return;
    }

    if (!_hasAllRequiredDocuments) {
      setState(() => _currentStep = 2);
      _showMessage('Debes cargar todos los documentos requeridos.');
      return;
    }

    if (!_isSocialRegistration &&
        !(_step2FormKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final nit = _nitController.text.trim();

      // Callback para mostrar progreso
      void updateProgress(String message) {
        if (mounted) {
          setState(() {
            _uploadingDocument = message;
          });
        }
      }

      // Registrar la institucion y el administrador
      // AuthService se encarga de: 1) Crear usuario, 2) Subir docs, 3) Crear Firestore
      if (_isSocialRegistration) {
        await _authService.registerInstitutionAdminWithSocialUser(
          socialUser: widget.socialUserData!.user,
          institutionName: _institutionNameController.text.trim(),
          institutionNit: nit,
          institutionDepartment: _selectedDepartment!,
          institutionCity: _selectedCity!,
          institutionAddress: _addressController.text.trim(),
          institutionType: _institutionType,
          institutionPhone: _institutionPhoneController.text.trim(),
          rectorCellPhone: _rectorCellPhoneController.text.trim(),
          email: _emailController.text.trim(),
          selectedDocuments: _selectedDocuments,
          jobTitle: _jobTitleController.text.trim(),
          onProgress: updateProgress,
        );
      } else {
        await _authService.registerInstitutionAdmin(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          institutionName: _institutionNameController.text.trim(),
          institutionNit: nit,
          institutionDepartment: _selectedDepartment!,
          institutionCity: _selectedCity!,
          institutionAddress: _addressController.text.trim(),
          institutionType: _institutionType,
          institutionPhone: _institutionPhoneController.text.trim(),
          rectorCellPhone: _rectorCellPhoneController.text.trim(),
          selectedDocuments: _selectedDocuments,
          adminDisplayName: _adminNameController.text.trim(),
          onProgress: updateProgress,
        );
      }

      if (mounted) {
        final email = _emailController.text.trim();
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('¡Registro Exitoso!'),
            content: Text(
              'La institucion ha sido registrada. Hemos enviado un correo de verificacion a $email. Por favor revisalo (incluyendo la carpeta de Spam) antes de continuar.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      }
    } on FirebaseAuthException catch (e) {
      _showMessage(_mapAuthError(e.code));
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        _showMessage(
          'Permisos insuficientes para completar el registro (${e.code}). ${e.message ?? ''}',
        );
      } else {
        _showMessage(
          e.message ?? 'Error de Firebase al registrar. Intenta de nuevo.',
        );
      }
    } on AuthException catch (e) {
      _showMessage(e.message);
    } on DocumentUploadException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('Error al registrar. Intenta de nuevo.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _uploadingDocument = '';
        });
      }
    }
  }

  String _mapAuthError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'El correo ya esta registrado.';
      case 'invalid-email':
        return 'Correo no valido.';
      case 'weak-password':
        return 'La contrasena es muy debil.';
      case 'nit-already-exists':
        return 'El NIT ya esta registrado en el sistema.';
      default:
        return 'Error al registrar. Intenta de nuevo.';
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar Institucion'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _isLoading ? null : () => Navigator.pop(context),
        ),
      ),
      body: _isLoading ? _buildLoadingView() : _buildStepperView(scheme),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            _uploadingDocument.isNotEmpty
                ? _uploadingDocument
                : 'Procesando...',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildStepperView(ColorScheme scheme) {
    return Stepper(
      currentStep: _currentStep,
      onStepContinue: _onStepContinue,
      onStepCancel: _onStepCancel,
      onStepTapped: _onStepTapped,
      controlsBuilder: (context, details) {
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            children: [
              FilledButton(
                onPressed: details.onStepContinue,
                child: Text(_currentStep == 3 ? 'Finalizar' : 'Continuar'),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: details.onStepCancel,
                child: Text(_currentStep == 0 ? 'Cancelar' : 'Atras'),
              ),
            ],
          ),
        );
      },
      steps: [
        Step(
          title: const Text('Datos de la Institucion'),
          subtitle: const Text('Nombre, NIT y direccion'),
          isActive: _currentStep >= 0,
          state: _currentStep > 0 ? StepState.complete : StepState.indexed,
          content: _buildStep0InstitutionData(scheme),
        ),
        Step(
          title: const Text('Tipo y Contacto'),
          subtitle: const Text('Telefonos y correo'),
          isActive: _currentStep >= 1,
          state: _currentStep > 1 ? StepState.complete : StepState.indexed,
          content: _buildStep1ContactData(scheme),
        ),
        Step(
          title: const Text('Documentos'),
          subtitle: Text(
            _institutionType == InstitutionType.public
                ? 'Cedula y Acta de Posesion'
                : 'Cedula, Camara de Comercio y RUT',
          ),
          isActive: _currentStep >= 2,
          state: _currentStep > 2 ? StepState.complete : StepState.indexed,
          content: _buildStep2Documents(scheme),
        ),
        Step(
          title: const Text('Administrador'),
          subtitle: Text(
            _isSocialRegistration
                ? 'Cargo del administrador'
                : 'Datos del administrador',
          ),
          isActive: _currentStep >= 3,
          state: StepState.indexed,
          content: _buildStep3AdminData(scheme),
        ),
      ],
    );
  }

  Widget _buildStep0InstitutionData(ColorScheme scheme) {
    return Form(
      key: _step0FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(
            scheme,
            icon: Icons.business_rounded,
            title: 'Informacion basica',
            subtitle: 'Datos legales de la institucion',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _institutionNameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre de la Institucion *',
              prefixIcon: Icon(Icons.business_outlined),
              hintText: 'Ej: Colegio San Jose',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Ingresa el nombre de la institucion.';
              }
              if (value.trim().length < 3) {
                return 'El nombre es muy corto.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _nitController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'NIT *',
              prefixIcon: Icon(Icons.numbers_outlined),
              hintText: 'Ej: 900123456',
              helperText: 'Sin digito de verificacion ni guiones',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Ingresa el NIT.';
              }
              if (value.length < 9) {
                return 'El NIT debe tener al menos 9 digitos.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          // Dropdown de Departamento
          _isLoadingLocations
              ? const Center(child: CircularProgressIndicator())
              : DropdownButtonFormField<String>(
                  initialValue: _selectedDepartment,
                  decoration: const InputDecoration(
                    labelText: 'Departamento *',
                    prefixIcon: Icon(Icons.map_outlined),
                  ),
                  hint: const Text('Selecciona un departamento'),
                  isExpanded: true,
                  items: _departamentos.map((dep) {
                    return DropdownMenuItem<String>(
                      value: dep['nombre'] as String,
                      child: Text(dep['nombre'] as String),
                    );
                  }).toList(),
                  onChanged: _onDepartmentChanged,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Selecciona un departamento.';
                    }
                    return null;
                  },
                ),
          const SizedBox(height: 16),
          // Dropdown de Ciudad
          DropdownButtonFormField<String>(
            initialValue: _selectedCity,
            decoration: const InputDecoration(
              labelText: 'Ciudad *',
              prefixIcon: Icon(Icons.location_city_outlined),
            ),
            hint: Text(
              _selectedDepartment == null
                  ? 'Primero selecciona un departamento'
                  : 'Selecciona una ciudad',
            ),
            isExpanded: true,
            items: _ciudades.map((ciudad) {
              return DropdownMenuItem<String>(
                value: ciudad,
                child: Text(ciudad),
              );
            }).toList(),
            onChanged: _selectedDepartment == null
                ? null
                : (value) {
                    setState(() {
                      _selectedCity = value;
                    });
                  },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Selecciona una ciudad.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _addressController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Direccion *',
              prefixIcon: Icon(Icons.location_on_outlined),
              hintText: 'Ej: Calle 10 # 20-30',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Ingresa la direccion.';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStep1ContactData(ColorScheme scheme) {
    return Form(
      key: _step1FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(
            scheme,
            icon: Icons.category_rounded,
            title: 'Tipo de Institucion',
            subtitle:
                'Selecciona el tipo para determinar los documentos requeridos',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<InstitutionType>(
            initialValue: _institutionType,
            decoration: const InputDecoration(
              labelText: 'Tipo de Institucion *',
              prefixIcon: Icon(Icons.account_balance_outlined),
            ),
            items: InstitutionType.values.map((type) {
              return DropdownMenuItem(
                value: type,
                child: Text(type.displayName),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _institutionType = value;
                  // Limpiar documentos al cambiar de tipo
                  _selectedDocuments.clear();
                });
              }
            },
          ),
          const SizedBox(height: 24),
          _buildSectionHeader(
            scheme,
            icon: Icons.phone_rounded,
            title: 'Datos de Contacto',
            subtitle: 'Telefonos y correo electronico',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _institutionPhoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Telefono Fijo de la Institucion *',
              prefixIcon: Icon(Icons.phone_outlined),
              hintText: 'Ej: 6011234567',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Ingresa el telefono fijo.';
              }
              if (value.length < 7) {
                return 'Telefono no valido.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _rectorCellPhoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Celular del Rector *',
              prefixIcon: Icon(Icons.smartphone_outlined),
              hintText: 'Ej: 3001234567',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Ingresa el celular del rector.';
              }
              if (value.length < 10) {
                return 'Celular no valido.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            enabled: !_isSocialRegistration,
            decoration: InputDecoration(
              labelText: 'Correo Electronico *',
              prefixIcon: const Icon(Icons.email_outlined),
              hintText: 'Ej: rector@colegio.edu.co',
              helperText:
                  'Se recomienda el uso de correo institucional si dispone de uno',
              helperMaxLines: 2,
              suffixIcon: _isSocialRegistration
                  ? const Icon(Icons.lock_outline)
                  : null,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Ingresa el correo.';
              }
              if (!value.contains('@') || !value.contains('.')) {
                return 'Correo no valido.';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStep2Documents(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(
          scheme,
          icon: Icons.folder_open_rounded,
          title: 'Documentos Requeridos',
          subtitle: _institutionType == InstitutionType.public
              ? 'Para instituciones publicas'
              : 'Para instituciones privadas',
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: scheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Formatos permitidos: PDF, JPG, PNG. Maximo 5 MB por archivo.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ..._requiredDocuments.map((doc) => _buildDocumentCard(scheme, doc)),
      ],
    );
  }

  Widget _buildDocumentCard(ColorScheme scheme, DocumentType type) {
    final isSelected = _selectedDocuments.containsKey(type);
    final file = _selectedDocuments[type];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? Colors.green : scheme.outlineVariant,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.green.withValues(alpha: 0.1)
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isSelected
                        ? Icons.check_circle
                        : Icons.description_outlined,
                    color: isSelected ? Colors.green : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            type.displayName,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Requerido',
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.error,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (isSelected && file != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          file.name,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: isSelected
                  ? TextButton.icon(
                      onPressed: () => _removeDocument(type),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Quitar'),
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.error,
                      ),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: _isUploading
                          ? null
                          : () => _pickDocument(type),
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: const Text('Cargar'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep3AdminData(ColorScheme scheme) {
    return Form(
      key: _step2FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(
            scheme,
            icon: _isSocialRegistration
                ? Icons.account_circle
                : Icons.admin_panel_settings_rounded,
            title: 'Datos del Administrador',
            subtitle: _isSocialRegistration
                ? 'Usando tu cuenta de ${widget.socialUserData?.providerName ?? 'proveedor'}'
                : 'Seras el administrador principal de SG-SST',
          ),
          if (_isSocialRegistration) ...[
            const SizedBox(height: 16),
            _buildSocialProfileCard(scheme),
          ],
          const SizedBox(height: 16),
          if (!_isSocialRegistration) ...[
            TextFormField(
              controller: _adminNameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nombre completo *',
                prefixIcon: Icon(Icons.person_outline),
                hintText: 'Ej: Juan Perez Garcia',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Ingresa tu nombre.';
                }
                if (value.trim().length < 3) {
                  return 'El nombre es muy corto.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: _jobTitleController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Cargo *',
              prefixIcon: Icon(Icons.work_outline),
              hintText: 'Ej: Coordinador de SST',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Ingresa tu cargo.';
              }
              return null;
            },
          ),
          if (!_isSocialRegistration) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: _isPasswordObscured,
              decoration: InputDecoration(
                labelText: 'Contrasena *',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isPasswordObscured
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      _isPasswordObscured = !_isPasswordObscured;
                    });
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Ingresa una contrasena.';
                }
                if (value.length < 6) {
                  return 'Minimo 6 caracteres.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _isPasswordObscured,
              decoration: const InputDecoration(
                labelText: 'Confirmar Contrasena *',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              validator: (value) {
                if (value != _passwordController.text) {
                  return 'Las contrasenas no coinciden.';
                }
                return null;
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSocialProfileCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundImage: widget.socialUserData?.photoUrl != null
                ? NetworkImage(widget.socialUserData!.photoUrl!)
                : null,
            backgroundColor: scheme.primaryContainer,
            child: widget.socialUserData?.photoUrl == null
                ? Icon(Icons.person, color: scheme.onPrimaryContainer)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.socialUserData?.displayName ?? '',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  widget.socialUserData?.email ?? '',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (widget.socialUserData?.providerColor ?? Colors.green)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified,
                  size: 14,
                  color: widget.socialUserData?.providerColor ?? Colors.green,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.socialUserData?.providerName ?? 'Social',
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.socialUserData?.providerColor ?? Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    ColorScheme scheme, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.primary,
                  ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
