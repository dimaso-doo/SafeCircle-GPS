import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/primary_button.dart';
import '../../../services/location/location_service.dart';
import '../../map/providers/map_provider.dart';
import '../providers/auth_provider.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isPreparing = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_isPreparing || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isPreparing = true;
    });

    try {
      final locationService = ref.read(locationServiceProvider);
      var permission = await locationService.checkPermission();
      if (permission != LocationPermissionState.granted) {
        permission = await locationService.requestPermission();
      }

      if (!mounted) {
        return;
      }

      if (permission != LocationPermissionState.granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Allow location to open your personal map.'),
          ),
        );
        return;
      }

      ref.invalidate(permissionStateProvider);
      ref.invalidate(currentPositionProvider);

      final success = await ref
          .read(authControllerProvider.notifier)
          .continueWithName(_nameController.text);

      if (!mounted || success) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.read(authControllerProvider).errorMessage ??
                'KinOrbit could not start. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPreparing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.location_on_rounded,
                          size: 48,
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'KinOrbit',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Private location sharing for the people you trust.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 36),
                    Text(
                      'What should your family call you?',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _nameController,
                      autofocus: true,
                      maxLength: 50,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(
                        labelText: 'Your name',
                        hintText: 'For example, Sandra',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) {
                        final length = value?.trim().length ?? 0;
                        if (length < 2) {
                          return 'Enter at least 2 characters.';
                        }
                        if (length > 50) {
                          return 'Use no more than 50 characters.';
                        }
                        return null;
                      },
                      onFieldSubmitted: state.isLoading ? null : (_) => _continue(),
                    ),
                    const SizedBox(height: 12),
                    PrimaryButton(
                      label: 'Continue',
                      isLoading: state.isLoading || _isPreparing,
                      onPressed: _continue,
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.privacy_tip_outlined),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No email or password is required. Location sharing '
                              'stays off until you join a circle and press Start sharing. '
                              'This device keeps your account session.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
