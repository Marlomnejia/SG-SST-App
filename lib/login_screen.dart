
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';
import 'user_dashboard_screen.dart';
import 'admin_dashboard_screen.dart'; // Importar la nueva pantalla

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _isPasswordObscured = true;

  void _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });
      try {
        User? user = await _authService.signInWithEmailAndPassword(
          _emailController.text,
          _passwordController.text,
        );
        if (user != null) {
          if (user.email == 'admin@gmail.com') {
            // Navega al panel de Admin
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
            );
          } else {
            // Navega al panel de Usuario
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const UserDashboardScreen()),
            );
          }
        }
      } on FirebaseAuthException catch (e) {
        String message;
        switch (e.code) {
          case 'user-not-found':
            message = 'No se encontró un usuario con ese correo.';
            break;
          case 'wrong-password':
            message = 'Contraseña incorrecta.';
            break;
          default:
            message = 'Ocurrió un error. Por favor, inténtalo de nuevo.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _resetPassword() async {
    if (_emailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Por favor, ingresa tu correo electrónico.')),
      );
      return;
    }
    try {
      await _authService.sendPasswordResetEmail(_emailController.text);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Se ha enviado un enlace para restablecer la contraseña a tu correo.')),
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Inicio de Sesión')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(labelText: 'Correo Electrónico'),
                validator: (value) => value!.isEmpty ? 'Ingresa tu correo' : null,
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordObscured ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _isPasswordObscured = !_isPasswordObscured;
                      });
                    },
                  ),
                ),
                obscureText: _isPasswordObscured,
                validator: (value) => value!.isEmpty ? 'Ingresa tu contraseña' : null,
              ),
              SizedBox(height: 24),
              _isLoading
                  ? CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _login,
                      child: Text('Ingresar'),
                    ),
              TextButton(
                onPressed: _resetPassword,
                child: Text('Olvidé mi contraseña'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

