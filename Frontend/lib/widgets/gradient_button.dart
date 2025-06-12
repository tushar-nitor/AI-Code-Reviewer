import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A custom button with a gradient border and gradient text, perfect for
/// highlighting special "AI" actions.
class GradientAiButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String text;
  final IconData iconData;
  final List<Color> borderGradientColors;
  final List<Color> textGradientColors;

  const GradientAiButton({
    super.key,
    required this.onPressed,
    required this.text,
    this.iconData = Icons.auto_awesome, // A nice default "AI" icon
    this.borderGradientColors = const [Colors.purple, Colors.blue, Colors.cyan],
    this.textGradientColors = const [Colors.deepPurple, Colors.blueAccent],
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(1), // This creates the border thickness
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: borderGradientColors),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor, // Use cardColor for good contrast
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min, // Button takes the size of its content
            children: [
              // Gradient for the Icon
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(colors: textGradientColors).createShader(bounds),
                child: Icon(
                  iconData,
                  color: Colors.white, // This color is masked, so it needs to be non-transparent
                ),
              ),
              const SizedBox(width: 12),
              // Gradient for the Text
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: textGradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(bounds),
                child: Text(
                  text,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w400,
                    fontSize: 15,
                    // This color is masked by the shader, so it's just a placeholder.
                    // It must be non-transparent.
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
