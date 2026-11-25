import '../core/material.dart';
import 'screens/practice_screen.dart';
import 'screens/routine_player_screen.dart';

Future<void> openPractice(BuildContext context, String trackId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PracticeScreen(trackId: trackId)),
    );

Future<void> openRoutinePlayer(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const RoutinePlayerScreen()),
    );

void showSnack(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: actionLabel == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
      ),
    );
}
