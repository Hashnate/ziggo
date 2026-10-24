import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../auth/auth_provider.dart';

/// Lets a customer set their gender once. Afterwards only Ziggo support can
/// change it (it decides who can ask for a lady driver). Returns true if saved.
Future<bool> chooseGenderOnce(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  if (auth.gender == 'female' || auth.gender == 'male') {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Gender'),
        content: const Text('Your gender is already set. Please contact Ziggo support to change it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
    return false;
  }

  final gender = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Select Gender'),
      children: [
        for (final g in const [('female', 'Female'), ('male', 'Male')])
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, g.$1),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(g.$2, style: const TextStyle(fontSize: 16)),
            ),
          ),
      ],
    ),
  );
  if (gender == null || !context.mounted) return false;

  final label = gender == 'female' ? 'Female' : 'Male';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Set your gender to $label?'),
      content: const Text(
        'You can set this only once. To change it later, please contact Ziggo support.\n\n'
        'Female customers can ask for a lady driver.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  try {
    await auth.updateProfile(gender: gender);
    return true;
  } on DioException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.response?.data?['detail']?.toString() ?? 'Could not save your gender. Please try again.')),
      );
    }
    return false;
  }
}
