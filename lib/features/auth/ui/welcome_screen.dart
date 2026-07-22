import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/providers/auth_provider.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to SafeCircle GPS')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'SafeCircle GPS',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'Privacy-first family location sharing',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              child: const Text('Log in'),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const LoginScreen(),
                ));
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              child: const Text('Create account'),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SignupScreen(),
                ));
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              child: state.isLoading ? const Text('Starting Google sign in...') : const Text('Sign up with Google'),
              onPressed: state.isLoading
                  ? null
                  : () {
                      ref.read(authControllerProvider.notifier).signUpWithGoogle().then((success) {
                        if (!success && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(ref.read(authControllerProvider).errorMessage ?? 'Google sign-up failed.'),
                            ),
                          );
                        }
                      });
                    },
            ),
            const SizedBox(height: 24),
            const Text(
              'Background sharing is off by default. You can enable, pause, or stop it anytime.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
