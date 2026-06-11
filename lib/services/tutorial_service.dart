import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

class TutorialService {
  static void showOnboarding({
    required BuildContext context,
    required List<TargetFocus> targets,
    required VoidCallback onFinish,
  }) {
    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.blue.shade900,
      textSkip: "SKIP TUTORIAL",
      paddingFocus: 10,
      opacityShadow: 0.8,
      onFinish: onFinish,
      onClickTarget: (target) {
        // Optional: specific logic when a circled area is clicked
      },
      onSkip: () {
        onFinish();
        return true;
      },
    ).show(context: context);
  }

  static TargetFocus createTarget({
    required GlobalKey key,
    required String identify,
    required String title,
    required String content,
    ContentAlign align = ContentAlign.bottom,
  }) {
    return TargetFocus(
      identify: identify,
      keyTarget: key,
      alignSkip: Alignment.topRight,
      contents: [
        TargetContent(
          align: align,
          builder: (context, controller) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  content,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            );
          },
        ),
      ],
      shape: ShapeLightFocus.Circle,
    );
  }
}
